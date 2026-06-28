-- lua/gotools/ui/terminal.lua
-- Dedicated terminal system. No external terminal plugin dependency.
local state = require("gotools.state")
local win   = require("gotools.ui.window")
local M = {}

local TERM_NS = vim.api.nvim_create_namespace("gotools_terminal")

---@class TermOpts
---@field title?     string
---@field direction? "float"|"split"|"vsplit"
---@field height?    integer
---@field width?     integer
---@field persist?   boolean   reuse if same key
---@field key?       string    identity key for persistent reuse
---@field cwd?       string
---@field on_exit?   fun(code: integer)

---Internal: create a fresh terminal buffer running `cmd`
---@param cmd string  shell command string
---@param opts TermOpts
---@return { buf: integer, win: integer, chan: integer }
local function _make_term(cmd, opts)
  local buf  = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = opts.persist and "hide" or "wipe"
  vim.bo[buf].buflisted = false

  -- Determine window
  local term_win
  local dir = opts.direction or "float"

  if dir == "float" then
    term_win = win.open_float(buf, {
      title   = opts.title and (" " .. opts.title .. " ") or " Terminal ",
      height  = opts.height,
      width   = opts.width,
      w_ratio = 0.85,
      h_ratio = 0.75,
      enter   = true,
    })
  elseif dir == "split" then
    local h = opts.height or 15
    vim.cmd("botright " .. h .. "split")
    term_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(term_win, buf)
  elseif dir == "vsplit" then
    local w = opts.width or 80
    vim.cmd("botright " .. w .. "vsplit")
    term_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(term_win, buf)
  end

  vim.wo[term_win].number     = false
  vim.wo[term_win].signcolumn = "no"
  vim.wo[term_win].wrap       = false

  local function close_term()
    local current_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(current_win) == buf then
      vim.api.nvim_win_close(current_win, true)
    end
  end

  -- Launch terminal job
  local chan = vim.fn.termopen(cmd, {
    cwd      = opts.cwd or vim.uv.cwd(),
    on_exit  = function(_, code, _)
      if opts.on_exit then opts.on_exit(code) end
      -- Map q and Esc in terminal mode to close the window easily once the process exits
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.keymap.set("t", "q",     close_term, { buffer = buf, nowait = true })
          vim.keymap.set("t", "<Esc>", close_term, { buffer = buf, nowait = true })
        end
      end)
    end,
  })

  -- Auto enter insert in terminal
  vim.cmd("startinsert")

  -- Keymaps
  vim.keymap.set("n", "q",     close_term, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_term, { buffer = buf, nowait = true })
  vim.keymap.set("t", "<C-\\><C-n>", "<C-\\><C-n>", { buffer = buf })

  return { buf = buf, win = term_win, chan = chan, opts = opts }
end

---Run a shell command in a terminal window.
---If `key` is given and `persist=true`, reuses existing terminal if alive.
---@param cmd string
---@param title? string
---@param opts? TermOpts
function M.run_in_term(cmd, title, opts)
  opts       = opts or {}
  opts.title = title or opts.title or "gotools"
  -- Default to persist = true for better UX unless explicitly disabled
  if opts.persist == nil then opts.persist = true end

  local key = opts.key or (title and title:gsub("%s+", "_"):lower())
  if key and opts.persist ~= false then
    local existing = state.get_terminal(key)
    if existing and vim.api.nvim_buf_is_valid(existing.buf) then
      -- Re-show the window if closed
      if not vim.api.nvim_win_is_valid(existing.win) then
        local new_win
        local dir = (existing.opts and existing.opts.direction) or "float"
        if dir == "float" then
          new_win = win.open_float(existing.buf, {
            title   = opts.title,
            w_ratio = 0.85,
            h_ratio = 0.75,
          })
        elseif dir == "split" then
          local h = (existing.opts and existing.opts.height) or 15
          vim.cmd("botright " .. h .. "split")
          new_win = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(new_win, existing.buf)
        elseif dir == "vsplit" then
          local w = (existing.opts and existing.opts.width) or 80
          vim.cmd("botright " .. w .. "vsplit")
          new_win = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_buf(new_win, existing.buf)
        end

        vim.wo[new_win].number     = false
        vim.wo[new_win].signcolumn = "no"
        vim.wo[new_win].wrap       = false

        existing.win = new_win
        state.set_terminal(key, existing)
      end
      -- Focus window
      vim.api.nvim_set_current_win(existing.win)
      -- Send new command: clear first if needed, or just append
      vim.fn.chansend(existing.chan, cmd .. "\n")
      return existing
    end
  end

  local term = _make_term(cmd, opts)
  if key then
    state.set_terminal(key, term)
  end
  return term
end

---Open a persistent REPL-like terminal for Go commands.
function M.open_go_repl()
  local shell = vim.o.shell
  local term  = M.run_in_term(shell, "Go Terminal", {
    key     = "go_repl",
    persist = true,
    direction = "float",
  })
  return term
end

---Show a read-only output window (not a real terminal, just buffer).
---@param lines string[]
---@param title? string
---@param hls?   table
function M.show_output(lines, title, hls)
  local buf  = win.scratch_buf("gotools_output", false)
  win.set_lines(buf, lines, hls)
  local w = win.open_float(buf, {
    title   = title and (" " .. title .. " ") or " Output ",
    w_ratio = 0.75,
    h_ratio = 0.7,
  })
  win.buf_map(buf, {
    ["q"]     = function() win.close(w) end,
    ["<Esc>"] = function() win.close(w) end,
  })
  return buf, w
end

return M
