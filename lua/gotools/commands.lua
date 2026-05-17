-- lua/gotools/commands.lua
local M = {}

function M.setup(cfg)
  local function cmd(name, fn, desc, opts)
    vim.api.nvim_create_user_command(name, fn, vim.tbl_extend("force", {
      desc  = desc,
      nargs = "?",
    }, opts or {}))
  end

  -- Helper for package completion
  local function complete_pkg(ArgLead, CmdLine, CursorPos)
    local pkgs = { "./...", "./pkg/...", "main.go" } -- Basic example
    return vim.tbl_filter(function(s) return s:match("^" .. ArgLead) end, pkgs)
  end

  -- ── Status ──────────────────────────────────────────────────────────────────
  cmd("GotoolsStatus", function()
    require("gotools.ui.notify").status_dashboard()
  end, "Show gotools tool status")

  -- ── gotests ──────────────────────────────────────────────────────────────────
  cmd("GoTestGenFile", function()
    require("gotools.adapters.gotests").run_for_package()
  end, "Generate tests for current file (all functions)")

  cmd("GoTestGenFunc", function()
    require("gotools.adapters.gotests").run_for_func()
  end, "Generate test for function under cursor")

  cmd("GoTestGenWrite", function()
    require("gotools.adapters.gotests").run(nil, { all = true, write = true })
  end, "Generate and write tests immediately")

  -- ── gotestsum ────────────────────────────────────────────────────────────────
  cmd("GoTest", function(args)
    local pkg = args.args ~= "" and args.args or "./..."
    require("gotools.adapters.gotestsum").run({ pkg = pkg })
  end, "Run tests with gotestsum UI", { nargs = "?", complete = complete_pkg })

  cmd("GoTestFunc", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local row   = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local func_name
    for i = row, 1, -1 do
      local m = lines[i]:match("^func%s+(Test%w+)")
      if m then func_name = m; break end
    end
    if func_name then
      require("gotools.adapters.gotestsum").run({ run = func_name })
    else
      require("gotools.ui.notify").warn("GoTestFunc: no Test function at cursor")
    end
  end, "Run test function under cursor")

  cmd("GoTestAll", function()
    require("gotools.adapters.gotestsum").run({ pkg = "./..." })
  end, "Run all tests")

  cmd("GoTestHistory", function()
    require("gotools.adapters.gotestsum").history()
  end, "Show test run history")

  -- ── gomodifytags ──────────────────────────────────────────────────────────────
  cmd("GoModifyTags", function()
    require("gotools.adapters.gomodifytags").edit_tags()
  end, "Open interactive tag editor")

  -- ── iferr ────────────────────────────────────────────────────────────────────
  cmd("GoIfErr", function()
    require("gotools.adapters.iferr").run()
  end, "Insert iferr error check at cursor")

  -- ── fillstruct / fillswitch ───────────────────────────────────────────────────
  cmd("GoFillStruct", function()
    require("gotools.adapters.fillstruct").run()
  end, "Fill struct with zero values")

  cmd("GoFillSwitch", function()
    require("gotools.adapters.fillswitch").run()
  end, "Fill switch with all cases")

  -- ── govulncheck ───────────────────────────────────────────────────────────────
  cmd("GoVulnCheck", function(args)
    local pkg = args.args ~= "" and args.args or "./..."
    require("gotools.adapters.govulncheck").run(pkg)
  end, "Run govulncheck vulnerability scan", { nargs = "?", complete = complete_pkg })

  -- ── Toolchain ─────────────────────────────────────────────────────────────────
  cmd("GoBuild", function(args)
    local tc = require("gotools.adapters.toolchain")
    tc.build(nil, args.args ~= "" and args.args or nil)
  end, "go build", { nargs = "?", complete = "file" })

  cmd("GoRun", function(args)
    local tc = require("gotools.adapters.toolchain")
    local extra = args.args ~= "" and vim.split(args.args, " ") or nil
    tc.run(nil, extra)
  end, "go run current file", { nargs = "?", complete = "file" })

  cmd("GoRunPkg", function()
    require("gotools.adapters.toolchain").run_pkg()
  end, "go run current package")

  cmd("GoTestNative", function(args)
    local tc = require("gotools.adapters.toolchain")
    local pkg = args.args ~= "" and args.args or "./..."
    tc.test(nil, pkg)
  end, "go test (native terminal)", { nargs = "?", complete = complete_pkg })

  cmd("GoTestFuncNative", function()
    require("gotools.adapters.toolchain").test_func()
  end, "go test current function (native)")

  cmd("GoModTidy", function()
    require("gotools.adapters.toolchain").mod_tidy()
  end, "go mod tidy")

  cmd("GoModVendor", function()
    require("gotools.adapters.toolchain").mod_vendor()
  end, "go mod vendor")

  cmd("GoGenerate", function(args)
    local pkg = args.args ~= "" and args.args or "./..."
    require("gotools.adapters.toolchain").generate(nil, pkg)
  end, "go generate", { nargs = "?", complete = complete_pkg })

  cmd("GoFmt", function()
    require("gotools.adapters.toolchain").fmt()
  end, "gofmt current file")

  cmd("GoImports", function()
    require("gotools.adapters.toolchain").organize_imports()
  end, "Organize imports (gopls or goimports)")

  cmd("GoDoc", function(args)
    local pkg = args.args ~= "" and args.args or nil
    require("gotools.adapters.toolchain").doc(pkg)
  end, "go doc", { nargs = "?", complete = "customlist,v:lua.package_doc_complete" }) -- Simplified

  cmd("GoVet", function(args)
    local pkg = args.args ~= "" and args.args or "./..."
    require("gotools.adapters.toolchain").vet(nil, pkg)
  end, "go vet", { nargs = "?", complete = complete_pkg })

  -- ── Terminal ──────────────────────────────────────────────────────────────────
  cmd("GoTerminal", function()
    require("gotools.ui.terminal").open_go_repl()
  end, "Open persistent Go terminal")
end

return M
