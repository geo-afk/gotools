-- lua/gotools/adapters/fillswitch.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local diff_ui = require("gotools.ui.diff")
local notify  = require("gotools.ui.notify")
local spinner = require("gotools.ui.spinner")
local M = {}

local function byte_offset(bufnr, row, col)
  local lines  = vim.api.nvim_buf_get_lines(bufnr, 0, row - 1, false)
  local offset = 0
  for _, l in ipairs(lines) do offset = offset + #l + 1 end
  return offset + col
end

function M.run()
  if not detect.require_tool("fillswitch") then
    M.run_via_gopls()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file  = vim.api.nvim_buf_get_name(bufnr)
  if not file:match("%.go$") then
    notify.error("fillswitch: not a Go file")
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local offset   = byte_offset(bufnr, row, col)
  local cwd      = detect.find_module_root(file) or vim.uv.cwd()
  local orig     = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local sid    = spinner.start("fillswitch: filling…")
  local stdout = {}

  job.run({
    cmd      = { "fillswitch", "-file", file, "-offset", tostring(offset) },
    cwd      = cwd,
    on_stdout= function(l) table.insert(stdout, l) end,
    on_exit  = function(code, _, stderr)
      spinner.stop(sid)
      if code ~= 0 or #stdout == 0 then
        notify.error("fillswitch: " .. (stderr ~= "" and stderr or "no output"))
        return
      end

      diff_ui.show(
        orig, stdout,
        "fillswitch preview",
        function(new_lines)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
          notify.info("fillswitch: switch filled")
        end
      )
    end,
  })
end

function M.run_via_gopls()
  vim.lsp.buf.code_action({
    filter = function(a)
      return a.kind and (a.kind:find("refactor") ~= nil or a.kind:find("switch") ~= nil)
    end,
    apply = false,
  })
end

return M
