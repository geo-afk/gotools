-- lua/gotools/adapters/gotests.lua
local job     = require("gotools.async.job")
local detect  = require("gotools.utils.detect")
local diff_ui = require("gotools.ui.diff")
local win     = require("gotools.ui.window")
local spinner = require("gotools.ui.spinner")
local notify  = require("gotools.ui.notify")
local M = {}

---@class GotestsOpts
---@field funcs?      string[]  function names to generate tests for
---@field all?        boolean   generate tests for all exported functions
---@field parallel?   boolean
---@field named?      boolean
---@field template_dir? string
---@field subtests?   boolean
---@field write?      boolean   write directly without preview

local function build_cmd(file, opts)
  local cfg = require("gotools.state").get("config").gotests
  local cmd = { "gotests" }

  if opts.all then
    table.insert(cmd, "-all")
  elseif opts.funcs and #opts.funcs > 0 then
    table.insert(cmd, "-run")
    table.insert(cmd, table.concat(opts.funcs, ","))
  else
    table.insert(cmd, "-all")
  end

  if opts.parallel or cfg.parallel then
    table.insert(cmd, "-parallel")
  end

  if opts.named or cfg.named_return then
    table.insert(cmd, "-named")
  end

  local tdir = opts.template_dir or cfg.template_dir
  if tdir then
    table.insert(cmd, "-template_dir")
    table.insert(cmd, tdir)
  end

  table.insert(cmd, file)
  return cmd
end

---Generate test file and show diff preview.
---@param bufnr? integer
---@param opts? GotestsOpts
function M.run(bufnr, opts)
  if not detect.require_tool("gotests") then return end

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts  = opts or {}

  local file    = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or not file:match("%.go$") then
    notify.error("gotools: current buffer is not a Go file")
    return
  end
  if file:match("_test%.go$") then
    notify.warn("gotools: already in a test file")
    return
  end

  -- Determine target test file path
  local test_file = file:gsub("%.go$", "_test.go")

  local cmd = build_cmd(file, opts)
  local sid = spinner.start("gotests: generating…")

  local stdout_lines = {}
  job.run({
    cmd        = cmd,
    on_stdout  = function(line) table.insert(stdout_lines, line) end,
    on_exit    = function(code, stdout, stderr)
      spinner.stop(sid)
      if code ~= 0 then
        notify.error("gotests failed: " .. stderr)
        return
      end

      if #stdout_lines == 0 then
        notify.warn("gotests: no output (functions may already have tests)")
        return
      end

      if opts.write then
        -- Write directly
        local f = io.open(test_file, "a")
        if f then
          f:write(table.concat(stdout_lines, "\n"))
          f:close()
          notify.info("gotests: tests appended to " .. vim.fn.fnamemodify(test_file, ":t"))
          vim.cmd("edit " .. vim.fn.fnameescape(test_file))
        end
        return
      end

      -- Show diff/preview
      local existing = {}
      local ef = io.open(test_file, "r")
      if ef then
        for line in ef:lines() do table.insert(existing, line) end
        ef:close()
      end

      diff_ui.show(
        existing,
        stdout_lines,
        "gotests — " .. vim.fn.fnamemodify(test_file, ":t"),
        function(lines)
          -- Apply: append or create file
          local wf = io.open(test_file, #existing > 0 and "a" or "w")
          if wf then
            if #existing > 0 then
              -- Skip package declaration if appending
              local start = 1
              while start <= #lines and lines[start]:match("^package ") do
                start = start + 1
              end
              for i = start, #lines do wf:write(lines[i] .. "\n") end
            else
              for _, l in ipairs(lines) do wf:write(l .. "\n") end
            end
            wf:close()
          end
          notify.info("gotests: written to " .. vim.fn.fnamemodify(test_file, ":t"))
          vim.cmd("edit " .. vim.fn.fnameescape(test_file))
        end
      )
    end,
  })
end

---Interactive: pick function under cursor.
function M.run_for_func()
  local bufnr = vim.api.nvim_get_current_buf()
  local row   = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Walk upward to find func declaration
  local func_name
  for i = row, 1, -1 do
    local m = lines[i]:match("^func%s+[%(]?[^%)]*[%)%s]*(%w+)")
    if m then
      func_name = m
      break
    end
  end

  if not func_name then
    notify.warn("gotests: could not detect function at cursor")
    return
  end

  M.run(bufnr, { funcs = { func_name } })
end

---Generate for whole package
function M.run_for_package()
  local bufnr = vim.api.nvim_get_current_buf()
  M.run(bufnr, { all = true })
end

return M
