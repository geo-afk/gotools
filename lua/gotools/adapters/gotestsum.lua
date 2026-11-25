-- lua/gotools/adapters/gotestsum.lua
local job = require("gotools.async.job")
local detect = require("gotools.utils.detect")
local win = require("gotools.ui.window")
local spinner = require("gotools.ui.spinner")
local notify = require("gotools.ui.notify")
local state = require("gotools.state")
local M = {}

-- Test status symbols
local ICONS = {
	run = "⟳",
	pass = "✓",
	fail = "✗",
	skip = "⊘",
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
	if ok and ev and ev.Action then
		return ev
	end
	return nil
end

---@class RunTestOpts
---@field pkg?     string    go package or pattern (default "./...")
---@field run?     string    -run regexp
---@field verbose? boolean
---@field rerun?   boolean   rerun failed tests

---Open the test runner UI panel
---@param opts RunTestOpts
function M.run(opts)
	if not detect.require_tool("gotestsum") then
		return
	end
	opts = opts or {}

	local current_file = vim.api.nvim_buf_get_name(0)
	local cwd = detect.find_module_root(current_file) or vim.uv.cwd()
	local pkg = opts.pkg
	if not pkg or pkg == "" then
		if opts.run then
			pkg = detect.package_rel(0)
		else
			pkg = "./..."
		end
	end

	local title_str = opts.run and (" gotestsum — " .. pkg .. " : " .. opts.run .. " ")
		or (" gotestsum — " .. pkg .. " ")

	-- Build UI
	local buf = win.scratch_buf("gotools_tests", false)
	local panel_win = win.open_float(buf, {
		title = title_str,
		w_ratio = 0.8,
		h_ratio = 0.8,
	})

	local ns = vim.api.nvim_create_namespace("gotools_tests")
	local tests = {} -- { [pkg/name] = TestResult }
	local pkg_list = {} -- ordered unique pkgs
	local seen_pkg = {}
	local pkg_outputs = {} -- { [pkg] = string[] }
	local pkg_failed = {} -- { [pkg] = boolean }
	local line_map = {} -- line_nr -> { type = "test"|"pkg", ... }
	local by_pkg = {}

	-- If a specific test was requested, pre-populate it so it's immediately visible
	if opts.run then
		local init_pkg = (pkg and pkg ~= "./...") and pkg or detect.package_rel(0)
		local init_key = init_pkg .. "/" .. opts.run
		tests[init_key] = {
			name = opts.run,
			pkg = init_pkg,
			status = "run",
			output = {},
		}
		if not seen_pkg[init_pkg] then
			seen_pkg[init_pkg] = true
			table.insert(pkg_list, init_pkg)
		end
	end

	-- Debounced render
	local render_timer = vim.uv.new_timer()
	local function render()
		render_timer:stop()
		render_timer:start(
			50,
			0,
			vim.schedule_wrap(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
				local lines = {}
				local hls = {}
				line_map = {}

				local function hl(l, cs, ce, grp)
					table.insert(hls, { line = l, col_start = cs, col_end = ce, hl = grp })
				end

				table.insert(lines, "  Test Results  —  " .. pkg)
				hl(0, 0, -1, "GotoolsTitle")
				table.insert(lines, "")

				-- Group by package
				by_pkg = {}
				for _, t in pairs(tests) do
					if not by_pkg[t.pkg] then
						by_pkg[t.pkg] = {}
					end
					table.insert(by_pkg[t.pkg], t)
				end

				-- Sort packages
				table.sort(pkg_list)

				for _, p in ipairs(pkg_list) do
					local pkg_tests = by_pkg[p] or {}
					local pkg_pass = vim.tbl_filter(function(t)
						return t.status == "pass"
					end, pkg_tests)
					local pkg_fail = vim.tbl_filter(function(t)
						return t.status == "fail"
					end, pkg_tests)
					local pkg_skip = vim.tbl_filter(function(t)
						return t.status == "skip"
					end, pkg_tests)

					local is_pkg_failed = #pkg_fail > 0 or pkg_failed[p]
					local pkg_hl = is_pkg_failed and "GotoolsTestFail"
						or #pkg_pass > 0 and "GotoolsTestPass"
						or "GotoolsDim"
					local pl = #lines
					local psummary = ("  📦 %s  [%d/%d pass]"):format(
						vim.fn.fnamemodify(p, ":t"),
						#pkg_pass,
						#pkg_tests
					)
					table.insert(lines, psummary)
					line_map[pl + 1] = { type = "pkg", pkg = p }
					hl(pl, 2, -1, pkg_hl)

					-- If no test cases ran and package failed (compilation / build error)
					if #pkg_tests == 0 and (pkg_failed[p] or (pkg_outputs[p] and #pkg_outputs[p] > 0)) then
						local bl = #lines
						table.insert(lines, "      ⚙  [build failed / error] (press <CR> to view output)")
						hl(bl, 6, 8, "GotoolsTestFail")
						hl(bl, 8, -1, "Normal")
						line_map[bl + 1] = { type = "pkg", pkg = p }
					end

					-- Sort: fails first
					table.sort(pkg_tests, function(a, b)
						local order = { fail = 0, run = 1, skip = 2, pass = 3 }
						local ao = order[a.status] or 9
						local bo = order[b.status] or 9
						if ao ~= bo then
							return ao < bo
						end
						return a.name < b.name
					end)

					for _, t in ipairs(pkg_tests) do
						local icon = ICONS[t.status] or "?"
						local hl_g = t.status == "pass" and "GotoolsTestPass"
							or t.status == "fail" and "GotoolsTestFail"
							or t.status == "skip" and "GotoolsTestSkip"
							or "GotoolsTestRun"
						local dur = t.duration and ("  %.3fs"):format(t.duration) or ""
						local l = #lines
						table.insert(lines, ("      %s  %s%s"):format(icon, t.name, dur))
						line_map[l + 1] = { type = "test", test = t, pkg = p }
						hl(l, 6, 8, hl_g)
						hl(l, 8, #t.name + 9, "Normal")
						if dur ~= "" then
							hl(l, #t.name + 9, -1, "GotoolsDim")
						end
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
			end)
		)
	end

	-- Key: show test output
	local function show_test_output()
		local row = vim.api.nvim_win_get_cursor(panel_win)[1]
		local item = line_map[row]
		if not item then
			for d = 1, 3 do
				if line_map[row - d] then
					item = line_map[row - d]
					break
				elseif line_map[row + d] then
					item = line_map[row + d]
					break
				end
			end
		end

		if item and item.type == "test" then
			local t = item.test
			local out = (t.output and #t.output > 0) and t.output or { "(no output recorded for " .. t.name .. ")" }
			require("gotools.ui.terminal").show_output(out, "Test: " .. t.name .. " [" .. (t.status or "unknown") .. "]")
			return
		elseif item and item.type == "pkg" then
			local p = item.pkg
			local out = {}
			if pkg_outputs[p] and #pkg_outputs[p] > 0 then
				vim.list_extend(out, pkg_outputs[p])
			end
			local pkg_tests = by_pkg[p] or {}
			for _, t in ipairs(pkg_tests) do
				if #out > 0 then table.insert(out, "") end
				table.insert(out, "=== RUN   " .. t.name)
				if t.output and #t.output > 0 then
					vim.list_extend(out, t.output)
				end
				table.insert(out, "--- " .. (t.status or "FAIL"):upper() .. ": " .. t.name .. (t.duration and (" (%.3fs)"):format(t.duration) or ""))
			end
			if #out == 0 then
				table.insert(out, "(no output recorded for package " .. p .. ")")
			end
			require("gotools.ui.terminal").show_output(out, "Package: " .. vim.fn.fnamemodify(p, ":t"))
			return
		end

		-- UTF-8 safe line match fallback
		local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
		local test_name = line:match("^%s+%S+%s+([%w_/%.-]+)")
		if test_name then
			for _, t in pairs(tests) do
				if t.name == test_name then
					local out = (t.output and #t.output > 0) and t.output or { "(no output recorded for " .. t.name .. ")" }
					require("gotools.ui.terminal").show_output(out, "Test: " .. t.name .. " [" .. (t.status or "unknown") .. "]")
					return
				end
			end
		end

		-- Global fallback: show all output
		local all_out = {}
		for _, p in ipairs(pkg_list) do
			if pkg_outputs[p] and #pkg_outputs[p] > 0 then
				vim.list_extend(all_out, pkg_outputs[p])
			end
		end
		for _, t in pairs(tests) do
			if t.output and #t.output > 0 then
				table.insert(all_out, "=== RUN   " .. t.name)
				vim.list_extend(all_out, t.output)
			end
		end
		if #all_out > 0 then
			require("gotools.ui.terminal").show_output(all_out, "All Test Output")
		else
			notify.info("No test output recorded")
		end
	end

	render()

	win.buf_map(buf, {
		["q"] = function()
			win.close(panel_win)
		end,
		["<Esc>"] = function()
			win.close(panel_win)
		end,
		["<CR>"] = show_test_output,
		["r"] = function()
			win.close(panel_win)
			M.run(opts)
		end,
		["f"] = function()
			local failed = vim.tbl_filter(function(t)
				return t.status == "fail"
			end, vim.tbl_values(tests))
			if #failed == 0 then
				notify.info("No failed tests")
				return
			end
			local run_pat = table.concat(
				vim.tbl_map(function(t)
					return t.name
				end, failed),
				"|"
			)
			win.close(panel_win)
			M.run(vim.tbl_extend("force", opts, { run = run_pat }))
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if render_timer then
				render_timer:stop()
				render_timer:close()
			end
		end,
	})

	-- Launch tests; default to verbose (-v) streaming JSON
	local json_cmd = { "go", "test" }
	if opts.verbose ~= false then
		table.insert(json_cmd, "-v")
	end
	table.insert(json_cmd, "-json")
	if opts.run then
		vim.list_extend(json_cmd, { "-run", opts.run })
	end
	if opts.count then
		vim.list_extend(json_cmd, { "-count", tostring(opts.count) })
	end
	table.insert(json_cmd, pkg)

	local sid = spinner.start("Running tests…")

	job.run({
		cmd = json_cmd,
		cwd = cwd,
		on_stdout = function(line)
			local ev = parse_event(line)
			if not ev then
				return
			end

			local action = ev.Action
			local ev_pkg = ev.Package or pkg
			local key = (ev_pkg or "") .. "/" .. (ev.Test or "")
			local t_name = ev.Test
			local clean_out = (ev.Output or ""):gsub("\n$", "")

			if ev_pkg and not seen_pkg[ev_pkg] then
				seen_pkg[ev_pkg] = true
				table.insert(pkg_list, ev_pkg)
			end

			if t_name then
				if action == "run" then
					tests[key] = tests[key] or {
						name = t_name,
						pkg = ev_pkg or "",
						status = "run",
						output = {},
					}
					tests[key].status = "run"
				elseif action == "output" then
					tests[key] = tests[key] or {
						name = t_name,
						pkg = ev_pkg or "",
						status = "run",
						output = {},
					}
					table.insert(tests[key].output, clean_out)
				elseif action == "pass" then
					if tests[key] then
						tests[key].status = "pass"
						tests[key].duration = ev.Elapsed
					end
				elseif action == "fail" then
					if tests[key] then
						tests[key].status = "fail"
						tests[key].duration = ev.Elapsed
					end
				elseif action == "skip" then
					if tests[key] then
						tests[key].status = "skip"
					end
				end
			else
				-- Package-level event (e.g. build failure or compiler error)
				if ev_pkg then
					pkg_outputs[ev_pkg] = pkg_outputs[ev_pkg] or {}
					if action == "output" and clean_out ~= "" then
						table.insert(pkg_outputs[ev_pkg], clean_out)
					elseif action == "fail" then
						pkg_failed[ev_pkg] = true
					end
				end
			end

			vim.schedule(render)
		end,
		on_exit = function(code, _, _)
			spinner.stop(sid, code == 0 and "Tests passed ✓" or "Tests failed ✗")

			-- Save to history
			state.add_test_run({
				time = os.time(),
				pkg = pkg,
				code = code,
				results = vim.deepcopy(tests),
			})

			-- Quickfix: collect failures from individual tests and package-level build errors
			if code ~= 0 then
				local qf = {}
				for _, t in pairs(tests) do
					if t.status == "fail" then
						for _, out_line in ipairs(t.output or {}) do
							local file, lnum, msg = out_line:match("%s*([%w_/%.\\%-]+%.go):(%d+):%s*(.+)")
							if file then
								table.insert(qf, {
									filename = vim.fs.joinpath(cwd, file),
									lnum = tonumber(lnum),
									text = msg,
								})
							end
						end
					end
				end
				for _, p_outs in pairs(pkg_outputs) do
					for _, out_line in ipairs(p_outs) do
						local file, lnum, msg = out_line:match("%s*([%w_/%.\\%-]+%.go):(%d+):%s*(.+)")
						if file then
							table.insert(qf, {
								filename = vim.fs.joinpath(cwd, file),
								lnum = tonumber(lnum),
								text = msg,
							})
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
	local hist = state.get_test_history()
	local win_mod = require("gotools.ui.window")
	if #hist == 0 then
		notify.info("No test history yet")
		return
	end

	local lines = { "  Test History", "" }
	local hls = { { line = 0, col_start = 0, col_end = -1, hl = "GotoolsTitle" } }

	for i, run in ipairs(hist) do
		local icon = run.code == 0 and "✓" or "✗"
		local hl_g = run.code == 0 and "GotoolsTestPass" or "GotoolsTestFail"
		local t = os.date("%H:%M:%S", run.time)
		local l = #lines
		table.insert(lines, ("  %s  [%s]  %s"):format(icon, t, run.pkg))
		table.insert(hls, { line = l, col_start = 2, col_end = 4, hl = hl_g })
	end

	table.insert(lines, "")
	table.insert(lines, "  [q] Close")

	local buf = win_mod.scratch_buf(nil, false)
	win_mod.set_lines(buf, lines, hls)
	local w = win_mod.open_float(buf, { title = " Test History ", h_ratio = 0.5, w_ratio = 0.5 })
	win_mod.buf_map(buf, {
		["q"] = function()
			win_mod.close(w)
		end,
		["<Esc>"] = function()
			win_mod.close(w)
		end,
	})
end

return M
