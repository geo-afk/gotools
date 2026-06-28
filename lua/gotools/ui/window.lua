-- lua/gotools/ui/window.lua
-- Central floating window factory. No business logic.
local state = require("gotools.state")
local M = {}

---@class WinSpec
---@field title?   string
---@field width?   integer   absolute cols
---@field height?  integer   absolute rows
---@field w_ratio? number    0-1 fraction of &columns
---@field h_ratio? number    0-1 fraction of &lines
---@field row?     number    0-1 top offset fraction
---@field col?     number    0-1 left offset fraction
---@field border?  string|table
---@field blend?   integer   0-100
---@field ft?      string    filetype for the buffer
---@field modifiable? boolean
---@field scratch? boolean
---@field enter?   boolean

---Create a scratch buffer
---@param ft? string
---@param modifiable? boolean
---@return integer bufnr
function M.scratch_buf(ft, modifiable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].buflisted  = false
  if ft then vim.bo[buf].filetype = ft end
  if modifiable ~= nil then vim.bo[buf].modifiable = modifiable end
  return buf
end

---Open a floating window.
---@param buf integer
---@param spec WinSpec
---@return integer win_id
function M.open_float(buf, spec)
  spec = spec or {}
  local cfg = require("gotools.state").get("config") or {}
  local ui  = cfg.ui or {}

  local function calc_dims()
    local cols = vim.o.columns
    local rows = vim.o.lines
    local w = spec.width  or math.floor(cols * (spec.w_ratio or ui.width_ratio  or 0.8))
    local h = spec.height or math.floor(rows * (spec.h_ratio or ui.height_ratio or 0.75))
    local r = spec.row    and math.floor(rows * spec.row) or math.floor((rows - h) / 2)
    local c = spec.col    and math.floor(cols * spec.col) or math.floor((cols - w) / 2)
    return { row = r, col = c, width = w, height = h }
  end

  local dims = calc_dims()
  local win_opts = {
    relative  = "editor",
    row       = dims.row,
    col       = dims.col,
    width     = dims.width,
    height    = dims.height,
    style     = "minimal",
    border    = spec.border or ui.border or "rounded",
    title     = spec.title and (" " .. spec.title .. " ") or nil,
    title_pos = "center",
    zindex    = 50,
  }

  local win = vim.api.nvim_open_win(buf, spec.enter ~= false, win_opts)

  vim.wo[win].winblend   = spec.blend or ui.blend or 0
  vim.wo[win].wrap       = true
  vim.wo[win].linebreak  = true
  vim.wo[win].cursorline = true
  vim.wo[win].number     = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winhighlight = table.concat({
    "Normal:NormalFloat",
    "FloatBorder:GotoolsBorder",
    "CursorLine:GotoolsSelected",
  }, ",")

  -- Re-center on resize
  local group = vim.api.nvim_create_augroup("GotoolsWinResize_" .. win, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        local new_dims = calc_dims()
        vim.api.nvim_win_set_config(win, {
          row    = new_dims.row,
          col    = new_dims.col,
          width  = new_dims.width,
          height = new_dims.height,
        })
      else
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end
    end,
  })

  state.push_win(win)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      -- Remove from stack
      local stack = state.get("win_stack")
      for i, w in ipairs(stack) do
        if w == win then
          table.remove(stack, i)
          break
        end
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  return win
end

---Split an existing float into two panes: left content + right preview.
---Returns { left_win, right_win, left_buf, right_buf }
function M.open_split_float(title, spec)
  spec = spec or {}
  local cfg  = require("gotools.state").get("config") or {}
  local ui   = cfg.ui or {}

  local function calc_dims()
    local cols   = vim.o.columns
    local rows   = vim.o.lines
    local w      = spec.width  or math.floor(cols * (spec.w_ratio or ui.width_ratio  or 0.85))
    local h      = spec.height or math.floor(rows * (spec.h_ratio or ui.height_ratio or 0.8))
    local r      = math.floor((rows - h) / 2)
    local c      = math.floor((cols - w) / 2)

    local ratio  = spec.preview_ratio or ui.preview_ratio or 0.45
    local lw     = math.floor(w * (1 - ratio)) - 1
    local rw     = w - lw - 1
    return { row = r, col = c, width = w, height = h, lw = lw, rw = rw }
  end

  local d = calc_dims()

  -- Container (invisible, just provides border + title)
  local cont_buf = M.scratch_buf()
  local cont_win = vim.api.nvim_open_win(cont_buf, false, {
    relative  = "editor",
    row = d.row, col = d.col, width = d.width, height = d.height,
    style     = "minimal",
    border    = spec.border or ui.border or "rounded",
    title     = title and (" " .. title .. " ") or nil,
    title_pos = "center",
    zindex    = 48,
  })
  vim.wo[cont_win].winhighlight = "Normal:NormalFloat,FloatBorder:GotoolsBorder"

  -- Left pane
  local l_buf = M.scratch_buf(spec.left_ft, false)
  local l_win = vim.api.nvim_open_win(l_buf, true, {
    relative = "editor",
    row = d.row + 1, col = d.col + 1,
    width = d.lw, height = d.height - 2,
    style = "minimal", border = "none", zindex = 50,
  })
  vim.wo[l_win].winhighlight = "Normal:NormalFloat,CursorLine:GotoolsSelected"
  vim.wo[l_win].cursorline   = true
  vim.wo[l_win].wrap         = true

  -- Right pane
  local r_buf = M.scratch_buf(spec.right_ft, false)
  local r_win = vim.api.nvim_open_win(r_buf, false, {
    relative = "editor",
    row = d.row + 1, col = d.col + d.lw + 2,
    width = d.rw - 1, height = d.height - 2,
    style = "minimal", border = "none", zindex = 50,
  })
  vim.wo[r_win].winhighlight = "Normal:NormalFloat"
  vim.wo[r_win].wrap         = true
  vim.wo[r_win].number       = false

  -- Re-center handler
  local group = vim.api.nvim_create_augroup("GotoolsSplitResize_" .. cont_win, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(cont_win) then
        local nd = calc_dims()
        vim.api.nvim_win_set_config(cont_win, { row = nd.row, col = nd.col, width = nd.width, height = nd.height })
        if vim.api.nvim_win_is_valid(l_win) then
          vim.api.nvim_win_set_config(l_win, { row = nd.row + 1, col = nd.col + 1, width = nd.lw, height = nd.height - 2 })
        end
        if vim.api.nvim_win_is_valid(r_win) then
          vim.api.nvim_win_set_config(r_win, { row = nd.row + 1, col = nd.col + nd.lw + 2, width = nd.rw - 1, height = nd.height - 2 })
        end
      else
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end
    end,
  })

  local closing = false
  local function close_panes()
    if closing then return end
    closing = true
    pcall(vim.api.nvim_del_augroup_by_id, group)
    M.close(l_win)
    M.close(r_win)
    M.close(cont_win)
  end

  for _, w in ipairs({ cont_win, l_win, r_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(w),
      once = true,
      callback = close_panes,
    })
  end

  state.push_win(l_win)
  state.push_win(r_win)

  return {
    cont_win = cont_win, cont_buf = cont_buf,
    left_win = l_win,    left_buf = l_buf,
    right_win= r_win,    right_buf= r_buf,
  }
end

---Close a window safely and clean up state
---@param win integer
function M.close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  -- Clean up from stack
  local stack = state.get("win_stack")
  for i, w in ipairs(stack) do
    if w == win then
      table.remove(stack, i)
      break
    end
  end
end

---Set buffer lines with optional highlight groups per line.
---@param buf integer
---@param lines string[]
---@param hls? { line: integer, col_start: integer, col_end: integer, hl: string }[]
function M.set_lines(buf, lines, hls)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if hls then
    local ns = vim.api.nvim_create_namespace("gotools_win")
    for _, h in ipairs(hls) do
      vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, h.col_start, h.col_end)
    end
  end
end

---Append a line to buffer (used by streaming outputs)
---@param buf integer
---@param line string
---@param hl? string
function M.append_line(buf, line, hl)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, count, count, false, { line })
  if hl then
    local ns = vim.api.nvim_create_namespace("gotools_win")
    vim.api.nvim_buf_add_highlight(buf, ns, hl, count, 0, -1)
  end
  vim.bo[buf].modifiable = false
end

---Map keys inside a window/buffer
---@param buf integer
---@param maps table<string, function>
function M.buf_map(buf, maps)
  for lhs, rhs in pairs(maps) do
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
end

return M
