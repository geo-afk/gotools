-- lua/gotools/ui/spinner.lua
-- Lightweight spinner using vim.notify or statusline.
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local _active = {}  -- { [id] = { timer, msg } }
local _seq    = 0

---Start a spinner. Returns an id to stop it.
---@param msg string
---@return integer  spinner_id
function M.start(msg)
  _seq = _seq + 1
  local id    = _seq
  local frame = 1

  local timer = vim.uv.new_timer()
  _active[id] = { timer = timer, msg = msg }

  timer:start(0, 100, vim.schedule_wrap(function()
    if not _active[id] then return end
    local icon = FRAMES[frame]
    frame = (frame % #FRAMES) + 1
    
    -- Only echo if this is the most recent active spinner
    local max_id = 0
    for aid, _ in pairs(_active) do if aid > max_id then max_id = aid end end
    
    if id == max_id then
      vim.api.nvim_echo({{ (" %s  %s"):format(icon, msg), "GotoolsSpinner" }}, false, {})
    end
  end))

  return id
end

---Stop a spinner.
---@param id integer
---@param done_msg? string  if given, show as final message
function M.stop(id, done_msg)
  local entry = _active[id]
  if not entry then return end
  entry.timer:stop()
  entry.timer:close()
  _active[id] = nil
  
  if done_msg then
    vim.api.nvim_echo({{ "  " .. done_msg, "GotoolsOk" }}, false, {})
  else
    -- Only clear if no other spinners are active
    if vim.tbl_count(_active) == 0 then
      vim.api.nvim_echo({}, false, {})
    end
  end
end

return M
