-- lua/gotools/async/job.lua
-- Thin, non-blocking wrapper around vim.system (Neovim 0.10+)
local state = require("gotools.state")
local M = {}

---@class JobOpts
---@field cmd string[]
---@field cwd? string
---@field env? table<string,string>
---@field stdin? string
---@field on_stdout? fun(line: string)
---@field on_stderr? fun(line: string)
---@field on_exit? fun(code: integer, stdout: string, stderr: string)
---@field timeout? integer  milliseconds

---Run a command asynchronously.
---Returns a job id that can be used to cancel.
---@param opts JobOpts
---@return integer job_id
function M.run(opts)
  local id      = state.next_job_id()
  local stdout_buf = {}
  local stderr_buf = {}

  local sys_opts = {
    cwd   = opts.cwd or vim.uv.cwd(),
    env   = opts.env,
    text  = true,
    stdin = opts.stdin and opts.stdin or false,
    stdout = function(err, data)
      if data then
        for _, line in ipairs(vim.split(data, "\n", { plain = true })) do
          if line ~= "" then
            table.insert(stdout_buf, line)
            if opts.on_stdout then
              vim.schedule(function() opts.on_stdout(line) end)
            end
          end
        end
      end
    end,
    stderr = function(err, data)
      if data then
        for _, line in ipairs(vim.split(data, "\n", { plain = true })) do
          if line ~= "" then
            table.insert(stderr_buf, line)
            if opts.on_stderr then
              vim.schedule(function() opts.on_stderr(line) end)
            end
          end
        end
      end
    end,
  }

  local handle = vim.system(opts.cmd, sys_opts, function(result)
    state.remove_job(id)
    vim.schedule(function()
      if opts.on_exit then
        opts.on_exit(
          result.code,
          table.concat(stdout_buf, "\n"),
          table.concat(stderr_buf, "\n")
        )
      end
    end)
  end)

  state.add_job(id, handle)
  return id
end

---Cancel a running job.
---@param id integer
function M.cancel(id)
  local handle = state.get("jobs")[id]
  if handle then
    handle:kill(9)
    state.remove_job(id)
  end
end

---Run a command synchronously (blocking). Use only for quick tool checks.
---@param cmd string[]
---@param cwd? string
---@return integer code, string stdout, string stderr
function M.run_sync(cmd, cwd)
  local result = vim.system(cmd, {
    cwd  = cwd or vim.uv.cwd(),
    text = true,
  }):wait(5000)
  return result.code, result.stdout or "", result.stderr or ""
end

return M
