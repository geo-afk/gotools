-- lua/gotools/state.lua
local M = {}

-- Central state store
local _state = {
  config       = {},
  tool_status  = {},   -- { [tool] = "ok"|"missing"|"error" }
  tool_versions= {},   -- { [tool] = "v1.2.3" }
  jobs         = {},   -- { [id] = job_handle }
  job_seq      = 0,
  terminals    = {},   -- { [key] = term_obj }
  test_history = {},   -- list of test run results
  vuln_cache   = {},   -- { [pkg] = vulns }
  win_stack    = {},   -- ordered open windows for focus mgmt
}

function M.init(config)
  _state.config = config
end

function M.get(key)
  return _state[key]
end

function M.set(key, val)
  _state[key] = val
end

function M.tool_ok(name)
  return _state.tool_status[name] == "ok"
end

function M.set_tool_status(name, status, version)
  _state.tool_status[name]   = status
  if version then _state.tool_versions[name] = version end
end

function M.tool_version(name)
  return _state.tool_versions[name]
end

function M.next_job_id()
  _state.job_seq = _state.job_seq + 1
  return _state.job_seq
end

function M.add_job(id, handle)
  _state.jobs[id] = handle
end

function M.remove_job(id)
  _state.jobs[id] = nil
end

function M.push_win(win_id)
  table.insert(_state.win_stack, win_id)
end

function M.pop_win()
  return table.remove(_state.win_stack)
end

function M.add_test_run(result)
  table.insert(_state.test_history, 1, result)
  if #_state.test_history > 50 then
    table.remove(_state.test_history)
  end
end

function M.get_test_history()
  return vim.deepcopy(_state.test_history)
end

function M.set_terminal(key, term)
  _state.terminals[key] = term
end

function M.get_terminal(key)
  return _state.terminals[key]
end

return M
