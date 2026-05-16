-- lua/gotools/ui/highlights.lua
local M = {}

local groups = {
  GotoolsTitle         = { link = "Title" },
  GotoolsBorder        = { link = "FloatBorder" },
  GotoolsHeader        = { bold = true, fg = "#7DCFFF" },
  GotoolsSubHeader     = { fg = "#73DACA" },
  GotoolsOk            = { fg = "#9ECE6A" },
  GotoolsWarn          = { fg = "#E0AF68" },
  GotoolsError         = { fg = "#F7768E" },
  GotoolsInfo          = { fg = "#7AA2F7" },
  GotoolsDim           = { link = "Comment" },
  GotoolsSelected      = { link = "Visual" },
  GotoolsTestPass      = { fg = "#9ECE6A", bold = true },
  GotoolsTestFail      = { fg = "#F7768E", bold = true },
  GotoolsTestSkip      = { fg = "#E0AF68" },
  GotoolsTestRun       = { fg = "#7AA2F7" },
  GotoolsVulnCritical  = { fg = "#FF0000", bold = true },
  GotoolsVulnHigh      = { fg = "#F7768E", bold = true },
  GotoolsVulnMedium    = { fg = "#E0AF68" },
  GotoolsVulnLow       = { fg = "#9ECE6A" },
  GotoolsDiffAdd       = { link = "DiffAdd" },
  GotoolsDiffDel       = { link = "DiffDelete" },
  GotoolsDiffChange    = { link = "DiffChange" },
  GotoolsStatusOk      = { fg = "#9ECE6A" },
  GotoolsStatusMissing = { fg = "#F7768E" },
  GotoolsKey           = { fg = "#BB9AF7" },
  GotoolsValue         = { fg = "#E0AF68" },
  GotoolsPrefix        = { fg = "#7DCFFF", bold = true },
  GotoolsSpinner       = { fg = "#7AA2F7", bold = true },
}

function M.setup()
  for name, opts in pairs(groups) do
    -- Don't override if already defined by colorscheme/user
    if not pcall(vim.api.nvim_get_hl, 0, { name = name }) then
      vim.api.nvim_set_hl(0, name, opts)
    else
      -- Always re-apply to handle colorscheme changes
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  -- Re-apply on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("GotoolsHL", { clear = true }),
    callback = M.setup,
  })
end

return M
