-- lua/gotools/adapters/iferr.lua
local job    = require("gotools.async.job")
local detect = require("gotools.utils.detect")
local notify = require("gotools.ui.notify")
local M = {}

---Detect the cursor position offset within the file (byte offset for iferr)
---@param bufnr integer
---@param row integer  0-indexed
---@return integer  byte offset
local function byte_offset(bufnr, row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  local offset = 0
  for _, l in ipairs(lines) do
    offset = offset + #l + 1  -- +1 for newline
  end
  return offset
end

---Insert iferr snippet at cursor.
---`iferr` reads from stdin and outputs the snippet.
function M.run()
  if not detect.require_tool("iferr") then return end

  local bufnr  = vim.api.nvim_get_current_buf()
  local file   = vim.api.nvim_buf_get_name(bufnr)
  if not file:match("%.go$") then
    notify.error("iferr: not a Go file")
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local offset   = byte_offset(bufnr, row - 1) + col

  local content  = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

  local snippet  = {}
  job.run({
    cmd      = { "iferr", "-pos", tostring(offset) },
    stdin    = content,
    on_stdout= function(line) table.insert(snippet, line) end,
    on_exit  = function(code, _, stderr)
      if code ~= 0 or #snippet == 0 then
        notify.error("iferr: " .. (stderr ~= "" and stderr or "no output"))
        return
      end

      -- Determine indentation from current line
      local cur_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
      local indent   = cur_line:match("^(%s*)") or ""

      -- Apply indentation to snippet lines
      local indented = vim.tbl_map(function(l)
        return l ~= "" and (indent .. l) or l
      end, snippet)

      -- Insert after current line
      vim.api.nvim_buf_set_lines(bufnr, row, row, false, indented)

      -- Move cursor to end of inserted block
      vim.api.nvim_win_set_cursor(0, { row + #indented, #indent })
      notify.info("iferr: inserted error check")
    end,
  })
end

return M
