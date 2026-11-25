-- lua/gotools/utils/detect.lua
local job = require("gotools.async.job")
local state = require("gotools.state")
local notify = require("gotools.ui.notify")
local M = {}

local IS_WIN = vim.uv.os_uname().sysname:find("Windows") ~= nil

---Check if an executable exists in PATH
---@param bin string
---@return boolean
function M.has_bin(bin)
	return vim.fn.executable(bin) == 1
end

---Try to extract version string from a binary asynchronously
---@param bin string
---@param callback fun(version: string|nil)
function M.get_version_async(bin, callback)
	job.run({
		cmd = { bin, "version" },
		on_exit = function(code, stdout, _)
			if code == 0 and stdout ~= "" then
				local ver = stdout:match("(%d+%.%d+[%.%d]*)")
				if ver then
					callback(ver)
					return
				end
			end
			-- Try --version
			job.run({
				cmd = { bin, "--version" },
				on_exit = function(c2, s2, _)
					if c2 == 0 and s2 ~= "" then
						callback(s2:match("(%d+%.%d+[%.%d]*)"))
					else
						callback(nil)
					end
				end,
			})
		end,
	})
end

---Validate all configured tools and update state
---@param tools_cfg table
function M.validate_all(tools_cfg)
	local missing = {}
	local pending = 0

	for name, cfg in pairs(tools_cfg) do
		if M.has_bin(cfg.bin) then
			pending = pending + 1
			M.get_version_async(cfg.bin, function(ver)
				state.set_tool_status(name, "ok", ver)
				pending = pending - 1
			end)
		else
			state.set_tool_status(name, "missing")
			table.insert(missing, { name = name, cfg = cfg })
		end
	end

	-- Wait for versions quietly or just notify missing
	if #missing > 0 then
		vim.schedule(function()
			notify.missing_tools(missing)
		end)
	end
end

---Validate single tool; return boolean
function M.require_tool(name)
	if state.tool_ok(name) then
		return true
	end
	local cfg = require("gotools.state").get("config").tools[name]
	if not cfg then
		notify.error("Unknown tool: " .. name)
		return false
	end
	if not M.has_bin(cfg.bin) then
		notify.missing_tools({ { name = name, cfg = cfg } })
		return false
	end
	-- Re-validate asynchronously
	M.get_version_async(cfg.bin, function(ver)
		state.set_tool_status(name, "ok", ver)
	end)
	return true
end

---Detect Go module root from given path
---@param path string  file or dir path
---@return string|nil  module root dir
function M.find_module_root(path)
	if not path or path == "" then
		path = vim.uv.cwd()
	end
	local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
	local result = vim.fs.find("go.mod", { upward = true, path = dir })
	if result and #result > 0 then
		return vim.fs.normalize(vim.fn.fnamemodify(result[1], ":h"))
	end
	return nil
end

---Detect relative package path for testing/running from module root or cwd
---@param bufnr integer?
---@return string  e.g. "." or "./pkg/auth"
function M.package_rel(bufnr)
	local file = vim.api.nvim_buf_get_name(bufnr or 0)
	if not file or file == "" then
		return "."
	end
	local root = M.find_module_root(file) or vim.uv.cwd()
	local file_dir = vim.fs.normalize(vim.fn.fnamemodify(file, ":h"))
	local root_norm = vim.fs.normalize(root)
	if file_dir == root_norm or file_dir:sub(1, #root_norm) ~= root_norm then
		return "."
	end
	local rel = file_dir:sub(#root_norm + 2)
	return (rel == "" or rel == ".") and "." or "./" .. rel
end

---Detect current package import path
---@param bufnr integer
---@return string  e.g. "github.com/foo/bar/pkg" or "."
function M.package_of(bufnr)
	local file = vim.api.nvim_buf_get_name(bufnr or 0)
	local root = M.find_module_root(file)
	if not root then
		return "."
	end
	local file_dir = vim.fs.normalize(vim.fn.fnamemodify(file, ":h"))
	local root_norm = vim.fs.normalize(root)
	local rel = ""
	if file_dir ~= root_norm and file_dir:sub(1, #root_norm) == root_norm then
		rel = file_dir:sub(#root_norm + 2)
	end
	-- Read module name from go.mod
	local mod_file = vim.fs.joinpath(root_norm, "go.mod")
	local f = io.open(mod_file, "r")
	if not f then
		return rel == "" and "." or "./" .. rel
	end
	local mod_line = f:read("*l")
	f:close()
	local mod_name = mod_line and mod_line:match("^module%s+(%S+)")
	if not mod_name or mod_name == "main" then
		return rel == "" and "." or "./" .. rel
	end
	return mod_name .. (rel ~= "" and "/" .. rel or "")
end

---Return OS-aware install command string
---@param cfg table  tool config entry
---@return string
function M.install_cmd(cfg)
	return cfg.install
end

function M.is_windows()
	return IS_WIN
end

---WSL detection
---@return boolean
function M.is_wsl()
	if not IS_WIN then
		local uname = vim.uv.os_uname()
		return uname.release:lower():find("microsoft") ~= nil
	end
	return false
end

---Detect the name of the test function at or above the cursor
---@param bufnr integer?
---@param row integer?  1-indexed row
---@return string|nil
function M.detect_test_func(bufnr, row)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]

	-- Try treesitter first (Neovim 0.12 native)
	local ok_ts, ts = pcall(require, "vim.treesitter")
	if ok_ts and ts.get_node then
		local ok_node, node = pcall(ts.get_node, { bufnr = bufnr, pos = { row - 1, 0 } })
		if ok_node and node then
			local curr = node
			while curr do
				local ntype = curr:type()
				if ntype == "function_declaration" or ntype == "method_declaration" then
					for child in curr:iter_children() do
						if child:type() == "identifier" or child:type() == "field_identifier" then
							local name = vim.treesitter.get_node_text(child, bufnr)
							if name and name:match("^(Test|Benchmark|Example)[%w_]*") then
								return name
							end
						end
					end
				end
				curr = curr:parent()
			end
		end
	end

	-- Fallback to regex backwards scan
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i = math.min(row, #lines), 1, -1 do
		local line = lines[i]
		if line then
			local m = line:match("^%s*func%s+((Test|Benchmark|Example)[%w_]*)")
				or line:match("^%s*func%s*%b()%s*((Test|Benchmark|Example)[%w_]*)")
			if m then
				return m
			end
		end
	end
	return nil
end

---Detect the name of any function at or above the cursor
---@param bufnr integer?
---@param row integer?  1-indexed row
---@return string|nil
function M.detect_any_func(bufnr, row)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]

	-- Try treesitter first (Neovim 0.12 native)
	local ok_ts, ts = pcall(require, "vim.treesitter")
	if ok_ts and ts.get_node then
		local ok_node, node = pcall(ts.get_node, { bufnr = bufnr, pos = { row - 1, 0 } })
		if ok_node and node then
			local curr = node
			while curr do
				local ntype = curr:type()
				if ntype == "function_declaration" or ntype == "method_declaration" then
					for child in curr:iter_children() do
						if child:type() == "identifier" or child:type() == "field_identifier" then
							local name = vim.treesitter.get_node_text(child, bufnr)
							if name then
								return name
							end
						end
					end
				end
				curr = curr:parent()
			end
		end
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i = math.min(row, #lines), 1, -1 do
		local line = lines[i]
		if line then
			-- Method with receiver: func (recv Type) MethodName(
			local m = line:match("^%s*func%s+%b()%s+([%w_]+)%s*%(")
			if m then return m end
			-- Plain function: func FuncName(
			m = line:match("^%s*func%s+([%w_]+)%s*%(")
			if m then return m end
		end
	end
	return nil
end

return M
