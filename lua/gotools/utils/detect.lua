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
	local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
	local result = vim.fs.find("go.mod", { upward = true, path = dir })
	if result and #result > 0 then
		return vim.fn.fnamemodify(result[1], ":h")
	end
	return nil
end

---Detect current package import path
---@param bufnr integer
---@return string  e.g. "github.com/foo/bar/pkg"
function M.package_of(bufnr)
	local file = vim.api.nvim_buf_get_name(bufnr)
	local root = M.find_module_root(file)
	if not root then
		return "."
	end
	local rel = vim.fn.fnamemodify(file, ":h")
	local pkg = rel:sub(#root + 2) -- strip root prefix
	-- Read module name from go.mod
	local mod_file = root .. "/go.mod"
	local f = io.open(mod_file, "r")
	if not f then
		return "./" .. pkg
	end
	local mod_line = f:read("l")
	f:close()
	local mod_name = mod_line and mod_line:match("^module%s+(%S+)")
	if not mod_name then
		return "./" .. pkg
	end
	return mod_name .. (pkg ~= "" and "/" .. pkg or "")
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
---@param bufnr integer
---@param row integer  1-indexed row
---@return string|nil
function M.detect_test_func(bufnr, row)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i = row, 1, -1 do
		local line = lines[i]
		if line then
			local m = line:match("^func%s+(Test%w+)") or line:match("^func%s*%([^%)]+%)%s*(Test%w+)")
			if m then
				return m
			end
		end
	end
	return nil
end

---Detect the name of any function at or above the cursor
---@param bufnr integer
---@param row integer  1-indexed row
---@return string|nil
function M.detect_any_func(bufnr, row)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i = row, 1, -1 do
		local line = lines[i]
		if line then
			local m = line:match("^func%s+[%(]?[^%)]*[%)%s]*(%w+)")
			if m then
				return m
			end
		end
	end
	return nil
end

return M
