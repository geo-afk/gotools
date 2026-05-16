# nvim-gotools

A production-quality Golang tooling suite for Neovim 0.12+ that unifies the Go development ecosystem into a single, modern, async-first plugin.

## Features

| Tool           | Integration                                    |
| -------------- | ---------------------------------------------- |
| `gotests`      | Generate tests with preview/diff UI            |
| `gotestsum`    | Live-streaming test runner with tree view      |
| `gomodifytags` | Interactive struct tag editor                  |
| `iferr`        | Smart `if err != nil` insertion                |
| `fillstruct`   | Fill struct literals with zero values          |
| `fillswitch`   | Fill switch statements with all cases          |
| `govulncheck`  | Vulnerability scanning panel                   |
| Go toolchain   | build, run, test, fmt, mod, doc, vet, generate |

## Requirements

- Neovim 0.12+
- Go toolchain (`go` in PATH)
- Optional external tools (auto-detected, install prompts provided)

## Installation

### lazy.nvim

```lua
{
  "https://github.com/geo-afk/gotooljjs",
  ft = "go",
  config = function()
    require("gotools").setup({
      -- all fields are optional
    })
  end,
}
```

## Configuration

```lua
require("gotools").setup({
  tools = {
    -- Override binary names or install commands per tool
    gotests = { bin = "gotests", install = "go install github.com/cweill/gotests/gotests@latest" },
  },
  ui = {
    border       = "rounded",   -- any nvim border style
    blend        = 10,          -- winblend 0-100
    width_ratio  = 0.8,
    height_ratio = 0.8,
    preview_ratio= 0.45,        -- right pane fraction in split views
  },
  gotests = {
    template_dir = nil,   -- custom gotests template directory
    named_return = false,
    parallel     = false,
    subtests     = true,
  },
  gotestsum = {
    format      = "testname",   -- gotestsum --format value
    rerun_fails = 1,
  },
  gomodifytags = {
    transform       = "snakecase",  -- tag naming transform
    skip_unexported = false,
  },
  keymaps = {
    enable = true,
    prefix = "<leader>g",
  },
  terminal = {
    direction = "float",   -- "float"|"split"|"vsplit"
    persist   = true,
  },
})
```

## Commands

### Status & Setup

| Command          | Description                      |
| ---------------- | -------------------------------- |
| `:GotoolsStatus` | Show tool availability dashboard |

### Test Generation (gotests)

| Command           | Description                              |
| ----------------- | ---------------------------------------- |
| `:GoTestGenFunc`  | Generate test for function under cursor  |
| `:GoTestGenFile`  | Generate tests for all functions in file |
| `:GoTestGenWrite` | Generate and write tests without preview |

### Test Running (gotestsum)

| Command          | Description                              |
| ---------------- | ---------------------------------------- |
| `:GoTest [pkg]`  | Run tests with live UI (default `./...`) |
| `:GoTestFunc`    | Run test function under cursor           |
| `:GoTestAll`     | Run all tests                            |
| `:GoTestHistory` | View past test run history               |

### Struct Tools

| Command         | Description                          |
| --------------- | ------------------------------------ |
| `:GoFillStruct` | Fill struct literal with zero values |
| `:GoFillSwitch` | Fill switch with all enum cases      |
| `:GoModifyTags` | Open interactive tag editor          |
| `:GoIfErr`      | Insert `if err != nil` at cursor     |

### Go Toolchain

| Command               | Description                           |
| --------------------- | ------------------------------------- |
| `:GoBuild [pkg]`      | `go build`                            |
| `:GoRun [args]`       | `go run` current file                 |
| `:GoRunPkg`           | `go run` current package              |
| `:GoTestNative [pkg]` | `go test` in terminal                 |
| `:GoTestFuncNative`   | `go test -run FuncName`               |
| `:GoModTidy`          | `go mod tidy`                         |
| `:GoModVendor`        | `go mod vendor`                       |
| `:GoGenerate [pkg]`   | `go generate`                         |
| `:GoFmt`              | `gofmt` current file                  |
| `:GoImports`          | Organize imports (gopls or goimports) |
| `:GoDoc [pkg]`        | `go doc`                              |
| `:GoVet [pkg]`        | `go vet`                              |

### Security

| Command              | Description              |
| -------------------- | ------------------------ |
| `:GoVulnCheck [pkg]` | Vulnerability scan panel |

### Terminal

| Command       | Description              |
| ------------- | ------------------------ |
| `:GoTerminal` | Open persistent Go shell |

## Default Keymaps

All keymaps are buffer-local (Go files only) and use `<leader>g` prefix by default.

| Keymap        | Command        |
| ------------- | -------------- |
| `<leader>gtf` | GoTestGenFunc  |
| `<leader>gta` | GoTestGenFile  |
| `<leader>gtw` | GoTestGenWrite |
| `<leader>gtr` | GoTest         |
| `<leader>gtF` | GoTestFunc     |
| `<leader>gtA` | GoTestAll      |
| `<leader>gth` | GoTestHistory  |
| `<leader>gms` | GoFillStruct   |
| `<leader>gmw` | GoFillSwitch   |
| `<leader>gmt` | GoModifyTags   |
| `<leader>gme` | GoIfErr        |
| `<leader>gb`  | GoBuild        |
| `<leader>gr`  | GoRun          |
| `<leader>gR`  | GoRunPkg       |
| `<leader>gf`  | GoFmt          |
| `<leader>gi`  | GoImports      |
| `<leader>gd`  | GoDoc          |
| `<leader>gv`  | GoVet          |
| `<leader>gG`  | GoGenerate     |
| `<leader>gM`  | GoModTidy      |
| `<leader>gV`  | GoVulnCheck    |
| `<leader>gT`  | GoTerminal     |
| `<leader>gs`  | GotoolsStatus  |

## UI Navigation

Most panels share these keys:

| Key           | Action                          |
| ------------- | ------------------------------- |
| `q` / `<Esc>` | Close panel                     |
| `<CR>`        | Confirm / show details          |
| `<Tab>`       | Switch pane (in split views)    |
| `a` / `r`     | Accept / Reject (in diff views) |
| `R`           | Re-run / Re-scan                |

### Test Panel

| Key    | Action                  |
| ------ | ----------------------- |
| `f`    | Rerun only failed tests |
| `<CR>` | Show test output        |

### Tag Editor

| Key       | Action                     |
| --------- | -------------------------- |
| `a`       | Mark tag as "add"          |
| `r`       | Mark tag as "remove"       |
| `n`       | Clear tag selection        |
| `<Space>` | Cycle: none → add → remove |
| `←` / `→` | Change transform style     |

### Install Panel

| Key    | Action                    |
| ------ | ------------------------- |
| `<CR>` | Install selected tool     |
| `I`    | Install all missing tools |

## Architecture

```
lua/gotools/
├── init.lua              # Setup & public API
├── state.lua             # Centralized state store
├── commands.lua          # User command registration
├── keymaps.lua           # Buffer-local keymap setup
├── async/
│   └── job.lua           # vim.system wrapper (non-blocking)
├── adapters/
│   ├── gotests.lua       # gotests integration
│   ├── gotestsum.lua     # gotestsum streaming runner
│   ├── gomodifytags.lua  # Interactive tag editor
│   ├── iferr.lua         # Error handling insertion
│   ├── fillstruct.lua    # Struct literal filler
│   ├── fillswitch.lua    # Switch case filler
│   ├── govulncheck.lua   # Vulnerability scanner
│   └── toolchain.lua     # Standard go commands
└── ui/
    ├── window.lua        # Float/split window factory
    ├── highlights.lua    # Highlight group definitions
    ├── notify.lua        # Notifications & install prompts
    ├── terminal.lua      # Dedicated terminal manager
    ├── diff.lua          # Diff preview UI
    └── spinner.lua       # Async progress indicators
```

## License

MIT
