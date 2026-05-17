-- lua/gotools/ui/notify.lua
local M = {}

local PREFIX = "gotools"

local function fmt_msg(msg) return ("[%s] %s"):format(PREFIX, msg) end

function M.info(msg)
  vim.notify(fmt_msg(msg), vim.log.levels.INFO, { title = "gotools" })
end

function M.warn(msg)
  vim.notify(fmt_msg(msg), vim.log.levels.WARN, { title = "gotools" })
end

function M.error(msg)
  vim.notify(fmt_msg(msg), vim.log.levels.ERROR, { title = "gotools" })
end

---Show a floating panel listing missing tools with one-click install.
---@param missing { name: string, cfg: table }[]
function M.missing_tools(missing)
  if #missing == 0 then return end

  local win_mod = require("gotools.ui.window")
  local lines   = {}
  local hls     = {}
  local actions = {}   -- { line_idx, install_cmd }

  table.insert(lines, "  gotools — Missing Tools")
  table.insert(hls, { line = 0, col_start = 0, col_end = -1, hl = "GotoolsTitle" })
  table.insert(lines, "")

  for i, t in ipairs(missing) do
    local detect = require("gotools.utils.detect")
    local l_idx = #lines
    table.insert(lines, ("  ✗  %-18s  →  %s"):format(t.name, detect.install_cmd(t.cfg)))
    table.insert(hls, { line = l_idx, col_start = 0,  col_end = 5,  hl = "GotoolsError" })
    table.insert(hls, { line = l_idx, col_start = 5,  col_end = 24, hl = "GotoolsWarn" })
    table.insert(hls, { line = l_idx, col_start = 24, col_end = -1, hl = "GotoolsDim" })
    table.insert(actions, { line = l_idx, cmd = detect.install_cmd(t.cfg), name = t.name })
  end

  table.insert(lines, "")
  table.insert(lines, "  [<CR>] Install selected    [I] Install all    [q] Close")
  local hint_l = #lines - 1
  table.insert(hls, { line = hint_l, col_start = 0, col_end = -1, hl = "GotoolsDim" })

  local buf = win_mod.scratch_buf("gotools_install", false)
  win_mod.set_lines(buf, lines, hls)

  local win = win_mod.open_float(buf, {
    title  = " Missing Go Tools ",
    height = math.min(#lines + 2, 20),
    w_ratio = 0.6,
  })

  local function install_line(lnum)
    for _, a in ipairs(actions) do
      if a.line == lnum then
        M.info("Installing " .. a.name .. "…")
        require("gotools.ui.terminal").run_in_term(a.cmd, "Install: " .. a.name)
        return
      end
    end
  end

  local function install_all()
    local cmds = vim.tbl_map(function(a) return a.cmd end, actions)
    local combined = table.concat(cmds, " && ")
    M.info("Installing all missing tools…")
    require("gotools.ui.terminal").run_in_term(combined, "Install: all tools")
  end

  win_mod.buf_map(buf, {
    ["<CR>"] = function()
      local lnum = vim.api.nvim_win_get_cursor(win)[1] - 1
      install_line(lnum)
    end,
    ["I"] = install_all,
    ["q"] = function() win_mod.close(win) end,
    ["<Esc>"] = function() win_mod.close(win) end,
  })
end

function M.install_prompt(name, cfg)
  M.missing_tools({ { name = name, cfg = cfg } })
end

---Show tool status dashboard
function M.status_dashboard()
  local state   = require("gotools.state")
  local win_mod = require("gotools.ui.window")
  local cfg     = state.get("config")

  local lines = {}
  local hls   = {}

  local function hl(line, col_s, col_e, group)
    table.insert(hls, { line = line, col_start = col_s, col_end = col_e, hl = group })
  end

  table.insert(lines, "  gotools — Tool Status")
  hl(0, 0, -1, "GotoolsTitle")
  table.insert(lines, "")

  for name, tool_cfg in pairs(cfg.tools) do
    local status  = state.get("tool_status")[name] or "unknown"
    local ver     = state.tool_version(name)
    local icon    = status == "ok" and "✓" or "✗"
    local hl_grp  = status == "ok" and "GotoolsStatusOk" or "GotoolsStatusMissing"
    local ver_str = ver and (" v" .. ver) or ""
    local l       = #lines
    table.insert(lines, ("  %s  %-18s%s"):format(icon, name, ver_str))
    hl(l, 2, 4, hl_grp)
    hl(l, 5, 24, "GotoolsHeader")
    if ver_str ~= "" then hl(l, 24, -1, "GotoolsDim") end
  end

  table.insert(lines, "")
  table.insert(lines, "  [R] Re-validate    [q] Close")
  hl(#lines - 1, 0, -1, "GotoolsDim")

  local buf = win_mod.scratch_buf("gotools_status", false)
  win_mod.set_lines(buf, lines, hls)
  local win = win_mod.open_float(buf, {
    title   = " Go Tools Status ",
    h_ratio = 0.5, w_ratio = 0.5,
  })

  win_mod.buf_map(buf, {
    ["R"] = function()
      win_mod.close(win)
      require("gotools.utils.detect").validate_all(cfg.tools)
    end,
    ["q"]     = function() win_mod.close(win) end,
    ["<Esc>"] = function() win_mod.close(win) end,
  })
end

return M
