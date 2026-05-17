-- lua/gotools/keymaps.lua
local M = {}

function M.setup(cfg)
	local p = cfg.keymaps.prefix or "<leader>h"
	local opts = { silent = true, noremap = true }

	-- Go-filetype only maps
	local group = vim.api.nvim_create_augroup("GotoolsKeymaps", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "go",
		callback = function(ev)
			local buf_opts = vim.tbl_extend("force", opts, { buffer = ev.buf })

			local function bmap(suffix, cmd_name, desc)
				vim.keymap.set(
					"n",
					p .. suffix,
					"<cmd>" .. cmd_name .. "<CR>",
					vim.tbl_extend("force", buf_opts, { desc = desc })
				)
			end

			-- Tests
			bmap("tf", "GoTestGenFunc", "Generate test for func under cursor")
			bmap("ta", "GoTestGenFile", "Generate tests for whole file")
			bmap("tw", "GoTestGenWrite", "Generate & write tests directly")
			bmap("tr", "GoTest", "Run tests (gotestsum UI)")
			bmap("tF", "GoTestFunc", "Run test under cursor")
			bmap("tA", "GoTestAll", "Run all tests")
			bmap("th", "GoTestHistory", "Test history")

			-- Struct tools
			bmap("ms", "GoFillStruct", "Fill struct")
			bmap("mw", "GoFillSwitch", "Fill switch")
			bmap("mt", "GoModifyTags", "Edit struct tags")
			bmap("me", "GoIfErr", "Insert if err check")

			-- Toolchain
			bmap("b", "GoBuild", "go build")
			bmap("r", "GoRun", "go run file")
			bmap("R", "GoRunPkg", "go run package")
			bmap("f", "GoFmt", "gofmt")
			bmap("i", "GoImports", "Organize imports")
			bmap("d", "GoDoc", "go doc under cursor")
			bmap("v", "GoVet", "go vet")
			bmap("G", "GoGenerate", "go generate")
			bmap("M", "GoModTidy", "go mod tidy")

			-- Security
			bmap("V", "GoVulnCheck", "govulncheck")

			-- Terminal
			bmap("T", "GoTerminal", "Open Go terminal")

			-- Status
			bmap("s", "GotoolsStatus", "Tool status")
		end,
	})
end

return M
