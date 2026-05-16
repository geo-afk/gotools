-- lua/gotools/utils/detect.lua
local job   = require("gotools.async.job")
local state = require("gotools.state")
local notify= require("gotools.ui.notify")
local M = {}

local IS_WIN = vim.uv.os_uname().sysname:find("Windows") ~= nil

---Check if an executable exists in PATH
---@param bin string
---@return boolean
function M.has_bin(bin)
  return vim.fn.executable(bin) == 1
end

---Try to extract version string from a binary
---@param bin string
---@return string|nil
function M.get_version(bin)
  local ok, stdout = pcall(function()
    local code, out, _ = job.run_sync({ bin, "version" }, nil)
    if code == 0 and out ~= "" then return out:match("(%d+%.%d+[%.%d]*)") end
    -- some tools: --version
    code, out, _ = job.run_sync({ bin, "--version" }, nil)
    if code == 0 and out ~= "" then return out:match("(%d+%.%d+[%.%d]*)") end
    return nil
  end)
  return ok and stdout or nil
end

---Validate all configured tools and update state
---@param tools_cfg table
function M.validate_all(tools_cfg)
  local missing = {}
  for name, cfg in pairs(tools_cfg) do
    if M.has_bin(cfg.bin) then
      local ver = M.get_version(cfg.bin)
      state.set_tool_status(name, "ok", ver)
    else
      state.set_tool_status(name, "missing")
      table.insert(missing, { name = name, cfg = cfg })
    end
  end

  if #missing > 0 then
    vim.schedule(function()
      notify.missing_tools(missing)
    end)
  end
end

---Validate single tool; return boolean
---@param name string
---@return boolean
function M.require_tool(name)
  if state.tool_ok(name) then return true end
  local cfg = require("gotools.state").get("config").tools[name]
  if not cfg then
    notify.error("Unknown tool: " .. name)
    return false
  end
  if not M.has_bin(cfg.bin) then
    notify.install_prompt(name, cfg)
    return false
  end
  -- Re-validate
  state.set_tool_status(name, "ok", M.get_version(cfg.bin))
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
  local root  = M.find_module_root(file)
  if not root then return "." end
  local rel  = vim.fn.fnamemodify(file, ":h")
  local pkg  = rel:sub(#root + 2)  -- strip root prefix
  -- Read module name from go.mod
  local mod_file = root .. "/go.mod"
  local f = io.open(mod_file, "r")
  if not f then return "./" .. pkg end
  local mod_line = f:read("l")
  f:close()
  local mod_name = mod_line and mod_line:match("^module%s+(%S+)")
  if not mod_name then return "./" .. pkg end
  return mod_name .. (pkg ~= "" and "/" .. pkg or "")
end

---Return OS-aware install command string
---@param cfg table  tool config entry
---@return string
function M.install_cmd(cfg)
  return cfg.install
end

function M.is_windows() return IS_WIN end

---WSL detection
---@return boolean
function M.is_wsl()
  if not IS_WIN then
    local uname = vim.uv.os_uname()
    return uname.release:lower():find("microsoft") ~= nil
  end
  return false
end

return M
