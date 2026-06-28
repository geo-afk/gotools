-- lua/gotools/ui/diff.lua
-- Generic diff preview + accept/reject UI
local win = require("gotools.ui.window")
local M = {}

---Show a split float: left=current file, right=proposed change.
---on_accept receives the new_lines table.
---@param original_lines string[]
---@param new_lines string[]
---@param title string
---@param on_accept fun(lines: string[])
function M.show(original_lines, new_lines, title, on_accept)
  local panes = win.open_split_float(" " .. title .. " ", {
    left_ft  = "go",
    right_ft = "go",
    w_ratio  = 0.9,
    h_ratio  = 0.8,
  })

  -- Left: original
  local orig_display = { "── Original ──", "" }
  vim.list_extend(orig_display, original_lines)
  win.set_lines(panes.left_buf, orig_display)

  -- Right: proposed with diff highlights
  local ns  = vim.api.nvim_create_namespace("gotools_diff")
  local new_display = { "── Proposed ──", "" }
  vim.list_extend(new_display, new_lines)

  vim.bo[panes.right_buf].modifiable = true
  vim.api.nvim_buf_set_lines(panes.right_buf, 0, -1, false, new_display)
  vim.bo[panes.right_buf].modifiable = false

  -- Simple diff highlighting (added/removed)
  local orig_set = {}
  for _, l in ipairs(original_lines) do orig_set[l] = true end

  for i, l in ipairs(new_lines) do
    local lnum = i + 1  -- offset by header lines
    if not orig_set[l] then
      vim.api.nvim_buf_add_highlight(panes.right_buf, ns, "GotoolsDiffAdd", lnum, 0, -1)
    end
  end

  -- Header hints
  local hint_lines = {
    "",
    "  [<CR> / a]  Accept    [r]  Reject    [q]  Close",
  }
  local hint_buf = win.scratch_buf(nil, false)
  win.set_lines(hint_buf, hint_lines, {
    { line = 1, col_start = 0, col_end = -1, hl = "GotoolsDim" },
  })

  local hint_rows = vim.o.lines
  local hint_win = vim.api.nvim_open_win(hint_buf, false, {
    relative = "editor",
    row      = math.floor(hint_rows * 0.8) + 1,
    col      = math.floor(vim.o.columns * 0.05),
    width    = math.floor(vim.o.columns * 0.9),
    height   = 2,
    style    = "minimal",
    border   = "none",
    zindex   = 55,
  })

  -- Resize handler for hint window
  local group_hint = vim.api.nvim_create_augroup("GotoolsDiffHintResize_" .. hint_win, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group_hint,
    callback = function()
      if vim.api.nvim_win_is_valid(hint_win) then
        local rows = vim.o.lines
        local cols = vim.o.columns
        vim.api.nvim_win_set_config(hint_win, {
          row    = math.floor(rows * 0.8) + 1,
          col    = math.floor(cols * 0.05),
          width  = math.floor(cols * 0.9),
        })
      else
        pcall(vim.api.nvim_del_augroup_by_id, group_hint)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(hint_win),
    once = true,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group_hint)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(panes.left_win),
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(hint_win) then
        vim.api.nvim_win_close(hint_win, true)
      end
    end,
  })

  local function close_all()
    for _, w in ipairs({ panes.cont_win, panes.left_win, panes.right_win, hint_win }) do
      win.close(w)
    end
  end

  local function accept()
    close_all()
    on_accept(new_lines)
  end

  for _, buf in ipairs({ panes.left_buf, panes.right_buf }) do
    win.buf_map(buf, {
      ["<CR>"] = accept,
      ["a"]    = accept,
      ["r"]    = close_all,
      ["q"]    = close_all,
      ["<Esc>"]= close_all,
      ["<Tab>"]= function()
        -- Toggle focus between panes
        local cur = vim.api.nvim_get_current_win()
        if cur == panes.left_win then
          vim.api.nvim_set_current_win(panes.right_win)
        else
          vim.api.nvim_set_current_win(panes.left_win)
        end
      end,
    })
  end
end

---Apply lines to a buffer at a given range.
---@param bufnr integer
---@param lines string[]
---@param start_line integer  0-indexed
---@param end_line integer    0-indexed, exclusive
function M.apply_to_buf(bufnr, lines, start_line, end_line)
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, lines)
end

return M
