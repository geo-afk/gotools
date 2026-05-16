-- lua/gotools/adapters/gotestsum.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local win     = require("gotools.ui.window")
local spinner = require("gotools.ui.spinner")
local notify  = require("gotools.ui.notify")
local state   = require("gotools.state")
local M = {}

-- Test status symbols
local ICONS = {
  run   = "⟳",
  pass  = "✓",
  fail  = "✗",
  skip  = "⊘",
  build = "⚙",
}

---@class TestResult
---@field name     string
---@field pkg      string
---@field status   "pass"|"fail"|"skip"|"run"
---@field duration number   seconds
---@field output   string[]

---Parse a single JSON event line from `go test -json`
---@param line string
---@return table|nil
local function parse_event(line)
  local ok, ev = pcall(vim.json.decode, line)
  if ok and ev and ev.Action then return ev end
  return nil
end

---Build the gotestsum command
---@param pkg string
---@param opts table
local function build_cmd(pkg, opts)
  local cfg = require("gotools.state").get("config").gotestsum
  local cmd = {
    "gotestsum",
    "--format", opts.format or cfg.format or "testname",
    "--",
  }

  if opts.run then
    table.insert(cmd, "-run")
    table.insert(cmd, opts.run)
  end

  if opts.count then
    table.insert(cmd, "-count")
    table.insert(cmd, tostring(opts.count))
  end

  if opts.verbose or opts.v then
    table.insert(cmd, "-v")
  end

  table.insert(cmd, pkg)
  return cmd
end

---@class RunTestOpts
---@field pkg?     string    go package or pattern (default "./...")
---@field run?     string    -run regexp
---@field verbose? boolean
---@field rerun?   boolean   rerun failed tests

---Open the test runner UI panel
---@param opts RunTestOpts
function M.run(opts)
  if not detect.require_tool("gotestsum") then return end
  opts = opts or {}

  local pkg = opts.pkg or "./..."
  local cwd = detect.find_module_root(vim.api.nvim_buf_get_name(0)) or vim.uv.cwd()

  -- Build UI
  local buf = win.scratch_buf("gotools_tests", false)
  local panel_win = win.open_float(buf, {
    title   = " gotestsum — " .. pkg .. " ",
    w_ratio = 0.8,
    h_ratio = 0.8,
  })

  local ns       = vim.api.nvim_create_namespace("gotools_tests")
  local tests    = {}    -- { [pkg/name] = TestResult }
  local pkg_list = {}    -- ordered unique pkgs
  local seen_pkg = {}

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local lines = {}
    local hls   = {}

    local function hl(l, cs, ce, grp)
      table.insert(hls, { line = l, col_start = cs, col_end = ce, hl = grp })
    end

    table.insert(lines, "  Test Results  —  " .. pkg)
    hl(0, 0, -1, "GotoolsTitle")
    table.insert(lines, "")

    -- Group by package
    local by_pkg = {}
    for key, t in pairs(tests) do
      if not by_pkg[t.pkg] then by_pkg[t.pkg] = {} end
      table.insert(by_pkg[t.pkg], t)
    end

    for _, p in ipairs(pkg_list) do
      local pkg_tests = by_pkg[p] or {}
      local pkg_pass  = vim.tbl_filter(function(t) return t.status == "pass" end, pkg_tests)
      local pkg_fail  = vim.tbl_filter(function(t) return t.status == "fail" end, pkg_tests)
      local pkg_skip  = vim.tbl_filter(function(t) return t.status == "skip" end, pkg_tests)

      local pkg_hl = #pkg_fail > 0 and "GotoolsTestFail"
                     or #pkg_pass > 0 and "GotoolsTestPass"
                     or "GotoolsDim"
      local pl = #lines
      local psummary = ("  📦 %s  [%d/%d pass]"):format(
        vim.fn.fnamemodify(p, ":t"), #pkg_pass, #pkg_tests)
      table.insert(lines, psummary)
      hl(pl, 2, -1, pkg_hl)

      -- Sort: fails first
      table.sort(pkg_tests, function(a, b)
        local order = { fail = 0, run = 1, skip = 2, pass = 3 }
        return (order[a.status] or 9) < (order[b.status] or 9)
      end)

      for _, t in ipairs(pkg_tests) do
        local icon  = ICONS[t.status] or "?"
        local hl_g  = t.status == "pass" and "GotoolsTestPass"
                      or t.status == "fail" and "GotoolsTestFail"
                      or t.status == "skip" and "GotoolsTestSkip"
                      or "GotoolsTestRun"
        local dur   = t.duration and ("  %.3fs"):format(t.duration) or ""
        local l     = #lines
        table.insert(lines, ("      %s  %s%s"):format(icon, t.name, dur))
        hl(l, 6, 8, hl_g)
        hl(l, 8, #t.name + 9, "Normal")
        if dur ~= "" then hl(l, #t.name + 9, -1, "GotoolsDim") end
      end
      table.insert(lines, "")
    end

    table.insert(lines, "  [r] Rerun    [f] Rerun failed    [q] Close    [<CR>] Show output")
    hl(#lines - 1, 0, -1, "GotoolsDim")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, h in ipairs(hls) do
      vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, h.col_start, h.col_end)
    end
    vim.bo[buf].modifiable = false
  end

  -- Key: show test output
  local function show_test_output()
    local row = vim.api.nvim_win_get_cursor(panel_win)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local test_name = line:match("%s+[✓✗⊘⟳]%s+(%S+)")
    if not test_name then return end
    for _, t in pairs(tests) do
      if t.name == test_name then
        require("gotools.ui.terminal").show_output(
          t.output or { "(no output)" },
          "Output: " .. test_name
        )
        return
      end
    end
  end

  render()

  win.buf_map(buf, {
    ["q"]     = function() win.close(panel_win) end,
    ["<Esc>"] = function() win.close(panel_win) end,
    ["<CR>"]  = show_test_output,
    ["r"]     = function() win.close(panel_win); M.run(opts) end,
    ["f"]     = function()
      local failed = vim.tbl_filter(function(t) return t.status == "fail" end,
        vim.tbl_values(tests))
      if #failed == 0 then notify.info("No failed tests"); return end
      local run_pat = table.concat(vim.tbl_map(function(t) return t.name end, failed), "|")
      win.close(panel_win)
      M.run(vim.tbl_extend("force", opts, { run = run_pat }))
    end,
  })

  -- Launch gotestsum; parse JSON from stderr/stdout
  -- gotestsum passes through test2json output; use -jsonfile for structured data
  -- We'll run `go test -json` ourselves for streaming and gotestsum for display
  local json_cmd = { "go", "test", "-json" }
  if opts.run then vim.list_extend(json_cmd, { "-run", opts.run }) end
  table.insert(json_cmd, pkg)

  local sid = spinner.start("Running tests…")

  local test_output_buf = {}   -- accumulate per-test output

  job.run({
    cmd       = json_cmd,
    cwd       = cwd,
    on_stdout = function(line)
      local ev = parse_event(line)
      if not ev then return end

      local action = ev.Action
      local key    = (ev.Package or "") .. "/" .. (ev.Test or "")
      local t_name = ev.Test

      if ev.Package and not seen_pkg[ev.Package] then
        seen_pkg[ev.Package] = true
        table.insert(pkg_list, ev.Package)
      end

      if action == "run" and t_name then
        tests[key] = {
          name   = t_name,
          pkg    = ev.Package or "",
          status = "run",
          output = {},
        }
      elseif action == "output" and t_name and tests[key] then
        table.insert(tests[key].output, (ev.Output or ""):gsub("\n$", ""))
      elseif action == "pass" and t_name and tests[key] then
        tests[key].status   = "pass"
        tests[key].duration = ev.Elapsed
      elseif action == "fail" and t_name and tests[key] then
        tests[key].status   = "fail"
        tests[key].duration = ev.Elapsed
      elseif action == "skip" and t_name and tests[key] then
        tests[key].status   = "skip"
      end

      vim.schedule(render)
    end,
    on_exit = function(code, _, _)
      spinner.stop(sid, code == 0 and "Tests passed ✓" or "Tests failed ✗")

      -- Save to history
      state.add_test_run({
        time    = os.time(),
        pkg     = pkg,
        code    = code,
        results = vim.deepcopy(tests),
      })

      -- Quickfix: collect failures
      if code ~= 0 then
        local qf = {}
        for _, t in pairs(tests) do
          if t.status == "fail" then
            for _, out_line in ipairs(t.output or {}) do
              local file, lnum, msg = out_line:match("%s+([%w_/%.]+%.go):(%d+): (.+)")
              if file then
                table.insert(qf, {
                  filename = cwd .. "/" .. file,
                  lnum     = tonumber(lnum),
                  text     = msg,
                })
              end
            end
          end
        end
        if #qf > 0 then
          vim.fn.setqflist(qf)
          notify.warn("gotestsum: failures written to quickfix (:copen)")
        end
      end

      vim.schedule(render)
    end,
  })
end

---Show test history panel
function M.history()
  local hist    = state.get_test_history()
  local win_mod = require("gotools.ui.window")
  if #hist == 0 then
    notify.info("No test history yet")
    return
  end

  local lines = { "  Test History", "" }
  local hls   = {{ line = 0, col_start = 0, col_end = -1, hl = "GotoolsTitle" }}

  for i, run in ipairs(hist) do
    local icon = run.code == 0 and "✓" or "✗"
    local hl_g = run.code == 0 and "GotoolsTestPass" or "GotoolsTestFail"
    local t    = os.date("%H:%M:%S", run.time)
    local l    = #lines
    table.insert(lines, ("  %s  [%s]  %s"):format(icon, t, run.pkg))
    table.insert(hls, { line = l, col_start = 2, col_end = 4, hl = hl_g })
  end

  table.insert(lines, "")
  table.insert(lines, "  [q] Close")

  local buf = win_mod.scratch_buf(nil, false)
  win_mod.set_lines(buf, lines, hls)
  local w = win_mod.open_float(buf, { title = " Test History ", h_ratio = 0.5, w_ratio = 0.5 })
  win_mod.buf_map(buf, {
    ["q"]     = function() win_mod.close(w) end,
    ["<Esc>"] = function() win_mod.close(w) end,
  })
end

return M
