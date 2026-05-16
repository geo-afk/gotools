-- gotools.lua - Plugin entry point
if vim.g.loaded_gotools then return end
vim.g.loaded_gotools = true

if vim.fn.has("nvim-0.12") == 0 then
  vim.notify("gotools requires Neovim 0.12+", vim.log.levels.ERROR)
  return
end

require("gotools").setup()
