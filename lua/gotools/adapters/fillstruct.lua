-- lua/gotools/adapters/fillstruct.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local diff_ui = require("gotools.ui.diff")
local notify  = require("gotools.ui.notify")
local spinner = require("gotools.ui.spinner")
local M = {}

---Byte offset of cursor
local function byte_offset(bufnr, row, col)
  local lines  = vim.api.nvim_buf_get_lines(bufnr, 0, row - 1, false)
  local offset = 0
  for _, l in ipairs(lines) do offset = offset + #l + 1 end
  return offset + col
end

---Run fillstruct and show diff preview
function M.run()
  if not detect.require_tool("fillstruct") then
    -- Fallback: attempt via gopls code action
    M.run_via_gopls()
    return
  end

  local bufnr  = vim.api.nvim_get_current_buf()
  local file   = vim.api.nvim_buf_get_name(bufnr)
  if not file:match("%.go$") then
    notify.error("fillstruct: not a Go file")
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local offset   = byte_offset(bufnr, row, col)
  local cwd      = detect.find_module_root(file) or vim.uv.cwd()

  local orig = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local sid     = spinner.start("fillstruct: filling…")
  local stdout  = {}

  job.run({
    cmd      = { "fillstruct", "-file", file, "-offset", tostring(offset) },
    cwd      = cwd,
    on_stdout= function(l) table.insert(stdout, l) end,
    on_exit  = function(code, _, stderr)
      spinner.stop(sid)
      if code ~= 0 or #stdout == 0 then
        notify.error("fillstruct: " .. (stderr ~= "" and stderr or "no output"))
        return
      end

      diff_ui.show(
        orig, stdout,
        "fillstruct preview",
        function(new_lines)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
          notify.info("fillstruct: struct filled")
        end
      )
    end,
  })
end

---Fallback: trigger gopls "Fill struct" code action
function M.run_via_gopls()
  -- Use vim.lsp.buf.code_action filtered to "source.fillStruct"
  vim.lsp.buf.code_action({
    filter = function(action)
      return action.kind and action.kind:find("refactor") ~= nil
    end,
    apply = false,
  })
end

return M
