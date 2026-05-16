-- lua/gotools/adapters/gomodifytags.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local diff_ui = require("gotools.ui.diff")
local win     = require("gotools.ui.window")
local notify  = require("gotools.ui.notify")
local M = {}

local SUPPORTED_TAGS = { "json", "yaml", "bson", "db", "validate", "xml", "toml", "form" }

---Build gomodifytags command
---@param file string
---@param line integer   1-indexed struct line
---@param opts table
local function build_cmd(file, line, opts)
  local cfg = require("gotools.state").get("config").gomodifytags
  local cmd = { "gomodifytags" }

  table.insert(cmd, "-file");  table.insert(cmd, file)
  table.insert(cmd, "-line");  table.insert(cmd, tostring(line))

  if opts.add then
    table.insert(cmd, "-add-tags")
    table.insert(cmd, table.concat(opts.add, ","))
  end

  if opts.remove then
    table.insert(cmd, "-remove-tags")
    table.insert(cmd, table.concat(opts.remove, ","))
  end

  if opts.clear_options then
    table.insert(cmd, "-clear-options")
  end

  local transform = opts.transform or cfg.transform or "snakecase"
  table.insert(cmd, "-transform"); table.insert(cmd, transform)

  if opts.skip_unexported or cfg.skip_unexported then
    table.insert(cmd, "-skip-unexported")
  end

  -- Output raw (no formatting)
  table.insert(cmd, "-format")
  table.insert(cmd, "source")

  return cmd
end

---Find the struct start line containing cursor
---@param bufnr integer
---@return integer|nil  1-indexed line
local function find_struct_line(bufnr)
  local row  = vim.api.nvim_win_get_cursor(0)[1]
  local lines= vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Walk up looking for "type Foo struct"
  for i = row, 1, -1 do
    if lines[i]:match("^type%s+%w+%s+struct") then
      return i
    end
  end
  -- Also check if we're already on the line
  return row
end

---Show interactive tag editor UI
---@param bufnr? integer
function M.edit_tags()
  if not detect.require_tool("gomodifytags") then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local file  = vim.api.nvim_buf_get_name(bufnr)
  if not file:match("%.go$") then
    notify.error("gomodifytags: not a Go file")
    return
  end

  local struct_line = find_struct_line(bufnr)
  if not struct_line then
    notify.warn("gomodifytags: could not find struct")
    return
  end

  -- Build choice UI
  local panel_buf = win.scratch_buf(nil, false)
  local tag_states = {}   -- { [tag] = "add"|"remove"|"none" }
  for _, t in ipairs(SUPPORTED_TAGS) do tag_states[t] = "none" end

  local transform = "snakecase"
  local transforms = { "snakecase", "camelcase", "lispcase", "pascalcase", "titlecase" }
  local t_idx = 1

  local ns = vim.api.nvim_create_namespace("gotools_modtags")

  local function render_panel(p_win)
    if not vim.api.nvim_buf_is_valid(panel_buf) then return end
    vim.bo[panel_buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(panel_buf, ns, 0, -1)
    local lines = {}
    local hls   = {}

    local function hl(l, cs, ce, grp)
      table.insert(hls, { line = l, col_start = cs, col_end = ce, hl = grp })
    end

    table.insert(lines, "  gomodifytags — Struct Tag Editor")
    hl(0, 0, -1, "GotoolsTitle")
    table.insert(lines, ("  File: %s  Line: %d"):format(vim.fn.fnamemodify(file, ":t"), struct_line))
    hl(1, 0, -1, "GotoolsDim")
    table.insert(lines, "")

    table.insert(lines, "  Tags:   [a]=add  [r]=remove  [n]=none  [Space]=cycle")
    hl(#lines - 1, 0, -1, "GotoolsDim")
    table.insert(lines, "")

    for _, tag in ipairs(SUPPORTED_TAGS) do
      local s   = tag_states[tag]
      local icon= s == "add" and "+" or s == "remove" and "-" or " "
      local hl_g= s == "add" and "GotoolsOk" or s == "remove" and "GotoolsError" or "GotoolsDim"
      local l   = #lines
      table.insert(lines, ("  [%s]  %-14s"):format(icon, tag))
      hl(l, 2,  5,  hl_g)
      hl(l, 5, -1, s ~= "none" and "GotoolsHeader" or "Normal")
    end

    table.insert(lines, "")
    table.insert(lines, ("  Transform:  ← %s →"):format(transform))
    hl(#lines - 1, 14, -1, "GotoolsValue")
    table.insert(lines, "")
    table.insert(lines, "  [<CR>] Preview & Apply    [q] Cancel")
    hl(#lines - 1, 0, -1, "GotoolsDim")

    vim.api.nvim_buf_set_lines(panel_buf, 0, -1, false, lines)
    for _, h in ipairs(hls) do
      vim.api.nvim_buf_add_highlight(panel_buf, ns, h.hl, h.line, h.col_start, h.col_end)
    end
    vim.bo[panel_buf].modifiable = false
  end

  local panel_win = win.open_float(panel_buf, {
    title   = " Tag Editor ",
    h_ratio = 0.65,
    w_ratio = 0.45,
  })

  render_panel(panel_win)

  -- Navigation: cursor on a tag line
  local TAG_LINE_OFFSET = 5  -- lines before first tag

  local function get_tag_at_cursor()
    local row = vim.api.nvim_win_get_cursor(panel_win)[1]
    local idx = row - TAG_LINE_OFFSET
    if idx >= 1 and idx <= #SUPPORTED_TAGS then
      return SUPPORTED_TAGS[idx]
    end
    return nil
  end

  local function cycle_tag(tag, direction)
    if not tag then return end
    local states = { "none", "add", "remove" }
    local cur = tag_states[tag]
    for i, s in ipairs(states) do
      if s == cur then
        local next = states[((i - 1 + (direction or 1)) % #states) + 1]
        tag_states[tag] = next
        return
      end
    end
  end

  local function apply_tags()
    local add_tags    = {}
    local remove_tags = {}
    for _, t in ipairs(SUPPORTED_TAGS) do
      if tag_states[t] == "add" then table.insert(add_tags, t) end
      if tag_states[t] == "remove" then table.insert(remove_tags, t) end
    end

    if #add_tags == 0 and #remove_tags == 0 then
      notify.warn("gomodifytags: no tags selected")
      return
    end

    local cmd = build_cmd(file, struct_line, {
      add       = #add_tags > 0 and add_tags or nil,
      remove    = #remove_tags > 0 and remove_tags or nil,
      transform = transform,
    })

    local stdout = {}
    job.run({
      cmd = cmd,
      on_stdout = function(l) table.insert(stdout, l) end,
      on_exit   = function(code, _, stderr)
        if code ~= 0 then
          notify.error("gomodifytags: " .. stderr)
          return
        end

        -- Show diff preview
        local orig = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        win.close(panel_win)

        diff_ui.show(
          orig,
          stdout,
          "gomodifytags preview",
          function(new_lines)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
            notify.info("gomodifytags: tags updated")
          end
        )
      end,
    })
  end

  win.buf_map(panel_buf, {
    ["<CR>"] = apply_tags,
    ["q"]    = function() win.close(panel_win) end,
    ["<Esc>"]= function() win.close(panel_win) end,
    ["a"]    = function()
      local t = get_tag_at_cursor()
      if t then tag_states[t] = "add"; render_panel(panel_win) end
    end,
    ["r"]    = function()
      local t = get_tag_at_cursor()
      if t then tag_states[t] = "remove"; render_panel(panel_win) end
    end,
    ["n"]    = function()
      local t = get_tag_at_cursor()
      if t then tag_states[t] = "none"; render_panel(panel_win) end
    end,
    ["<Space>"] = function()
      local t = get_tag_at_cursor()
      if t then cycle_tag(t); render_panel(panel_win) end
    end,
    ["<Right>"] = function()
      t_idx    = (t_idx % #transforms) + 1
      transform = transforms[t_idx]
      render_panel(panel_win)
    end,
    ["<Left>"] = function()
      t_idx    = ((t_idx - 2) % #transforms) + 1
      transform = transforms[t_idx]
      render_panel(panel_win)
    end,
  })
end

return M
