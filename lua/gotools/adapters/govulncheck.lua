-- lua/gotools/adapters/govulncheck.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local win     = require("gotools.ui.window")
local spinner = require("gotools.ui.spinner")
local notify  = require("gotools.ui.notify")
local state   = require("gotools.state")
local M = {}

---Parse govulncheck JSON output
---@param json_str string
---@return table[]  list of findings
local function parse_vulns(json_str)
  local vulns = {}
  for line in json_str:gmatch("[^\n]+") do
    local ok, obj = pcall(vim.json.decode, line)
    if ok and obj then
      if obj.finding then
        table.insert(vulns, obj.finding)
      end
    end
  end
  return vulns
end

---Severity heuristic from OSV severity or CVSS
---@param vuln table
---@return string  "critical"|"high"|"medium"|"low"
local function severity(vuln)
  local id = (vuln.osv or ""):upper()
  -- Very rough: GO- CVEs without CVSS data get "medium"
  if id:find("CVE") then return "high" end
  return "medium"
end

local SEV_ICON = {
  critical = "🔴",
  high     = "🟠",
  medium   = "🟡",
  low      = "🟢",
}
local SEV_HL = {
  critical = "GotoolsVulnCritical",
  high     = "GotoolsVulnHigh",
  medium   = "GotoolsVulnMedium",
  low      = "GotoolsVulnLow",
}

---Run govulncheck and show results panel
---@param pkg? string  default "./..."
function M.run(pkg)
  if not detect.require_tool("govulncheck") then return end
  pkg = pkg or "./..."

  local cwd = detect.find_module_root(vim.api.nvim_buf_get_name(0)) or vim.uv.cwd()
  local sid = spinner.start("govulncheck: scanning…")

  local raw_lines = {}
  job.run({
    cmd      = { "govulncheck", "-format", "json", pkg },
    cwd      = cwd,
    on_stdout= function(l) table.insert(raw_lines, l) end,
    on_exit  = function(code, _, stderr)
      spinner.stop(sid)

      -- govulncheck exits 1 when vulns found; that's not a tool error
      if code > 1 then
        notify.error("govulncheck: " .. stderr)
        return
      end

      local vulns = parse_vulns(table.concat(raw_lines, "\n"))

      -- Cache
      state.set("vuln_cache", vulns)

      M._show_panel(vulns, pkg)
    end,
  })
end

function M._show_panel(vulns, pkg)
  local buf = win.scratch_buf("gotools_vulns", false)
  local ns  = vim.api.nvim_create_namespace("gotools_vulns")

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local lines = {}
    local hls   = {}

    local function hl(l, cs, ce, grp)
      table.insert(hls, { line = l, col_start = cs, col_end = ce, hl = grp })
    end

    table.insert(lines, ("  govulncheck — %s"):format(pkg))
    hl(0, 0, -1, "GotoolsTitle")

    if #vulns == 0 then
      table.insert(lines, "")
      table.insert(lines, "  ✓  No vulnerabilities found")
      hl(2, 2, -1, "GotoolsOk")
    else
      table.insert(lines, ("  Found %d vulnerabilities"):format(#vulns))
      hl(1, 0, -1, "GotoolsWarn")
      table.insert(lines, "")

      -- Group by severity
      local grouped = { critical = {}, high = {}, medium = {}, low = {} }
      for _, v in ipairs(vulns) do
        local sev = severity(v)
        table.insert(grouped[sev], v)
      end

      for _, sev in ipairs({ "critical", "high", "medium", "low" }) do
        local group = grouped[sev]
        if #group > 0 then
          local l = #lines
          table.insert(lines, ("  %s  %s (%d)"):format(
            SEV_ICON[sev], sev:upper(), #group))
          hl(l, 2, -1, SEV_HL[sev])

          for _, v in ipairs(group) do
            local osv     = v.osv or "unknown"
            local sym     = v.symbol or ""
            local mod_path= v.trace and v.trace[1] and v.trace[1].module or "?"
            local l2      = #lines
            table.insert(lines, ("      %-22s  %s"):format(osv, sym))
            hl(l2, 6, 28, SEV_HL[sev])
            hl(l2, 28, -1, "GotoolsDim")

            table.insert(lines, ("      Module: %s"):format(mod_path))
            hl(#lines - 1, 0, -1, "GotoolsDim")
          end
          table.insert(lines, "")
        end
      end
    end

    table.insert(lines, "  [<CR>] Details    [q] Close    [r] Rescan")
    hl(#lines - 1, 0, -1, "GotoolsDim")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, h in ipairs(hls) do
      vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, h.col_start, h.col_end)
    end
    vim.bo[buf].modifiable = false
  end

  render()

  local panel_win = win.open_float(buf, {
    title   = " Vulnerability Report ",
    w_ratio = 0.7,
    h_ratio = 0.75,
  })

  -- Details popup for selected vuln
  local function show_details()
    local row  = vim.api.nvim_win_get_cursor(panel_win)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local osv  = line:match("GO%-%d+%-%d+") or line:match("CVE%-%d+%-%d+%-%d+")
    if not osv then return end

    for _, v in ipairs(vulns) do
      if v.osv == osv then
        local detail_lines = {
          "  " .. osv,
          "",
          "  Module:  " .. (v.trace and v.trace[1] and v.trace[1].module or "?"),
          "  Symbol:  " .. (v.symbol or "?"),
          "",
          "  Fix: upgrade affected package to patched version.",
          "  See: https://pkg.go.dev/vuln/" .. osv,
          "",
          "  [q] Close",
        }
        local d_buf = win.scratch_buf(nil, false)
        win.set_lines(d_buf, detail_lines, {
          { line = 0, col_start = 0, col_end = -1, hl = SEV_HL[severity(v)] },
        })
        local d_win = win.open_float(d_buf, {
          title   = " " .. osv .. " ",
          h_ratio = 0.35,
          w_ratio = 0.5,
          zindex  = 60,
        })
        win.buf_map(d_buf, {
          ["q"]     = function() win.close(d_win) end,
          ["<Esc>"] = function() win.close(d_win) end,
        })
        return
      end
    end
  end

  win.buf_map(buf, {
    ["q"]     = function() win.close(panel_win) end,
    ["<Esc>"] = function() win.close(panel_win) end,
    ["<CR>"]  = show_details,
    ["r"]     = function() win.close(panel_win); M.run(pkg) end,
  })
end

return M
