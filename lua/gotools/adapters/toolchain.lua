-- lua/gotools/adapters/toolchain.lua
-- Standard `go` toolchain commands
local job    = require("gotools.async.job")
local term   = require("gotools.ui.terminal")
local detect = require("gotools.utils.detect")
local notify = require("gotools.ui.notify")
local spinner= require("gotools.ui.spinner")
local win    = require("gotools.ui.window")
local M = {}

---Resolve module root cwd
local function cwd(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr or 0)
  return detect.find_module_root(file) or vim.uv.cwd()
end

---Run a go command in the terminal (visible output)
---@param args string[]   e.g. {"build", "./..."}
---@param title? string
---@param bufnr? integer
function M.run_in_term(args, title, bufnr)
  local cmd = table.concat(vim.list_extend({ "go" }, args), " ")
  term.run_in_term(cmd, title or ("go " .. args[1]), {
    key     = "go_toolchain",
    persist = false,
    cwd     = cwd(bufnr),
    direction = "float",
  })
end

-- ─── Build ────────────────────────────────────────────────────────────────────

function M.build(bufnr, pkg)
  pkg = pkg or "./..."
  M.run_in_term({ "build", "-v", pkg }, "go build", bufnr)
end

-- ─── Run ─────────────────────────────────────────────────────────────────────

function M.run(bufnr, args)
  local file = vim.api.nvim_buf_get_name(bufnr or 0)
  local extra = args and (" " .. table.concat(args, " ")) or ""
  M.run_in_term({ "run", file .. extra }, "go run", bufnr)
end

function M.run_pkg(bufnr, args)
  local pkg   = detect.package_of(bufnr or 0)
  local extra = args and (" " .. table.concat(args, " ")) or ""
  M.run_in_term({ "run", pkg .. extra }, "go run pkg", bufnr)
end

-- ─── Test ─────────────────────────────────────────────────────────────────────

function M.test(bufnr, pkg, flags)
  pkg   = pkg or "./..."
  flags = flags or {}
  local cmd_args = vim.list_extend({ "test", "-v" }, flags)
  table.insert(cmd_args, pkg)
  M.run_in_term(cmd_args, "go test", bufnr)
end

function M.test_func()
  local bufnr = vim.api.nvim_get_current_buf()
  local row   = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local func_name
  for i = row, 1, -1 do
    local m = lines[i]:match("^func%s+(Test%w+)")
    if m then func_name = m; break end
  end
  if not func_name then
    notify.warn("toolchain: not inside a Test function")
    return
  end
  local pkg = detect.package_of(bufnr)
  M.run_in_term({ "test", "-v", "-run", func_name, pkg }, "go test: " .. func_name, bufnr)
end

-- ─── Mod ─────────────────────────────────────────────────────────────────────

function M.mod_tidy(bufnr)
  M.run_in_term({ "mod", "tidy" }, "go mod tidy", bufnr)
end

function M.mod_vendor(bufnr)
  M.run_in_term({ "mod", "vendor" }, "go mod vendor", bufnr)
end

function M.mod_download(bufnr)
  M.run_in_term({ "mod", "download" }, "go mod download", bufnr)
end

-- ─── Generate ────────────────────────────────────────────────────────────────

function M.generate(bufnr, pkg)
  pkg = pkg or "./..."
  M.run_in_term({ "generate", pkg }, "go generate", bufnr)
end

-- ─── Fmt ─────────────────────────────────────────────────────────────────────

function M.fmt(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if not file:match("%.go$") then return end

  local orig = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stdout = {}
  job.run({
    cmd      = { "gofmt", file },
    on_stdout= function(l) table.insert(stdout, l) end,
    on_exit  = function(code, _, stderr)
      if code ~= 0 then
        notify.error("gofmt: " .. stderr)
        return
      end
      -- Apply in-place quietly
      if #stdout > 0 then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, stdout)
      end
    end,
  })
end

-- ─── Imports ─────────────────────────────────────────────────────────────────

function M.organize_imports(bufnr)
  -- Delegate to gopls if available
  local clients = vim.lsp.get_clients({ bufnr = bufnr or 0, name = "gopls" })
  if #clients > 0 then
    local params = vim.lsp.util.make_range_params()
    params.context = { only = { "source.organizeImports" } }
    local results = vim.lsp.buf_request_sync(bufnr or 0, "textDocument/codeAction", params, 3000)
    if results then
      for _, res in pairs(results) do
        for _, action in pairs(res.result or {}) do
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, "utf-8")
          end
        end
      end
    end
    return
  end
  -- Fallback: goimports
  if vim.fn.executable("goimports") == 1 then
    local file   = vim.api.nvim_buf_get_name(bufnr or 0)
    local stdout = {}
    job.run({
      cmd      = { "goimports", file },
      on_stdout= function(l) table.insert(stdout, l) end,
      on_exit  = function(code, _, _)
        if code == 0 and #stdout > 0 then
          vim.api.nvim_buf_set_lines(bufnr or 0, 0, -1, false, stdout)
        end
      end,
    })
  else
    M.fmt(bufnr)
  end
end

-- ─── Doc ─────────────────────────────────────────────────────────────────────

function M.doc(pkg)
  if not pkg then
    -- Use word under cursor
    pkg = vim.fn.expand("<cword>")
  end
  if pkg == "" then
    notify.warn("toolchain: provide a package name for go doc")
    return
  end

  local lines  = {}
  local sid    = spinner.start("go doc: " .. pkg)
  job.run({
    cmd      = { "go", "doc", pkg },
    on_stdout= function(l) table.insert(lines, l) end,
    on_exit  = function(code, _, stderr)
      spinner.stop(sid)
      if code ~= 0 then
        notify.error("go doc: " .. stderr)
        return
      end
      term.show_output(lines, "go doc — " .. pkg)
    end,
  })
end

-- ─── Vet ─────────────────────────────────────────────────────────────────────

function M.vet(bufnr, pkg)
  pkg = pkg or "./..."
  local sid = spinner.start("go vet " .. pkg .. "…")
  job.run({
    cmd     = { "go", "vet", pkg },
    cwd     = cwd(bufnr),
    on_exit = function(code, stdout, stderr)
      spinner.stop(sid)
      if code ~= 0 then
        local combined = (stdout ~= "" and stdout or "") .. (stderr ~= "" and "\n" .. stderr or "")
        local qf = {}
        for _, line in ipairs(vim.split(combined, "\n")) do
          local file, lnum, msg = line:match("^(.+%.go):(%d+):(.+)$")
          if file then
            table.insert(qf, {
              filename = file,
              lnum     = tonumber(lnum),
              text     = msg:gsub("^%s+", ""),
            })
          end
        end

        if #qf > 0 then
          vim.fn.setqflist(qf)
          notify.warn("go vet: issues found — :copen")
          vim.cmd("copen")
        else
          -- If not parsable as qf, show raw output in floating window
          local lines = vim.split(combined, "\n")
          term.show_output(lines, "go vet output")
        end
      else
        notify.info("go vet: clean ✓")
      end
    end,
  })
end

return M
