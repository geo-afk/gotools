-- lua/gotools/init.lua
local M = {}

M.config = {
	tools = {
		gotests = { bin = "gotests", install = "go install github.com/cweill/gotests/gotests@latest" },
		gomodifytags = { bin = "gomodifytags", install = "go install github.com/fatih/gomodifytags@latest" },
		iferr = { bin = "iferr", install = "go install github.com/koron/iferr@latest" },
		gotestsum = { bin = "gotestsum", install = "go install gotest.tools/gotestsum@latest" },
		fillstruct = {
			bin = "fillstruct",
			install = "go install github.com/davidrjenni/reftools/cmd/fillstruct@latest",
		},
		fillswitch = {
			bin = "fillswitch",
			install = "go install github.com/davidrjenni/reftools/cmd/fillswitch@latest",
		},
		govulncheck = { bin = "govulncheck", install = "go install golang.org/x/vuln/cmd/govulncheck@latest" },
	},
	ui = {
		border = "rounded",
		blend = 10,
		width_ratio = 0.6,
		height_ratio = 0.6,
		preview_ratio = 0.45,
	},
	gotests = {
		template_dir = nil,
		named_return = false,
		parallel = false,
		subtests = true,
	},
	gotestsum = {
		format = "testname",
		rerun_fails = 1,
		watch = false,
	},
	gomodifytags = {
		transform = "snakecase",
		skip_unexported = false,
	},
	terminal = {
		direction = "float",
		persist = true,
	},
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Bootstrap submodules
	require("gotools.state").init(M.config)
	require("gotools.ui.highlights").setup()
	require("gotools.commands").setup()

	-- Periodic window cleanup
	local cleanup_timer = vim.uv.new_timer()
	cleanup_timer:start(
		60000,
		60000,
		vim.schedule_wrap(function()
			require("gotools.state").cleanup_wins()
		end)
	)

	-- Lazy tool detection on first Go buffer
	local group = vim.api.nvim_create_augroup("GotoolsDetect", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "go",
		once = true,
		callback = function()
			require("gotools.utils.detect").validate_all(M.config.tools)
		end,
	})
end

-- Public API passthrough
function M.run(tool, ...)
	return require("gotools.adapters." .. tool).run(...)
end

return M
