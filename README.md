# monorepo.nvim

![monorepo.nvim demo video. Shows opening a new monorepo and changing scopes using the plugin](demo.gif)

**_monorepo.nvim_** is a plugin to manage the scope of monorepos inside of neovim!

Its goal is to make juggling multiple projects inside of a monorepo a little easier, in combination with Telescope's `find_files`.

**Features:**
- 🚀 **Auto-detection**: Automatically detects projects from `pnpm-workspace.yaml`
- 📦 **Workspace-aware**: Understands pnpm workspace patterns and resolves them to actual packages
- 🔍 **Smart discovery**: Only includes directories with `package.json` files as valid packages

## Requirements

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for the project picker
- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for some helper functions used internally

## Installing

Install the plugin (This example uses [lazy.nvim](https://github.com/folke/lazy.nvim))

```lua
{
  "imNel/monorepo.nvim",
  config = function()
    require("monorepo").setup({
      -- Your config here!
    })
  end,
  dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim"},
},
```

### Config Defaults

```lua
{
  silent = false, -- Suppresses vim.notify messages
  autoload_telescope = true, -- Automatically loads the telescope extension at setup
}
```

The telescope extension needs to be loaded at any point AFTER `require("telescope").setup()` and `require("monorepo").setup()`.
By default, this is done automatically but you can undo this by setting `{ autoload_telescope = false }` in the config.

This is the snippet you'll need to run to load the extension if doing it manually:

```lua
require("telescope").load_extension("monorepo")
```

### Keybindings

Set up your own keybindings to use the plugin:

```lua
-- Open projects picker
vim.keymap.set("n", "<leader>m", function()
  require("telescope").extensions.monorepo.monorepo()
end)
```

## Usage

### Auto-Detection (pnpm workspaces)

The plugin automatically detects all projects from your `pnpm-workspace.yaml` file:

1. **Monorepo Root Detection**: The plugin walks up the directory tree to find `pnpm-workspace.yaml`
2. **Pattern Parsing**: Extracts workspace patterns from the file (e.g., `apps/*`, `packages/*`)
3. **Package Resolution**: Resolves patterns to actual directories that contain `package.json`

**Example `pnpm-workspace.yaml`:**

```yaml
packages:
  - 'apps/*'
  - 'packages/*'
  - 'tools/*'
```

All directories matching these patterns that contain a `package.json` will be automatically detected as projects.

### Telescope Picker

View and navigate to projects using the Telescope picker:

```lua
:Telescope monorepo
```

or programmatically:

```lua
require("telescope").extensions.monorepo.monorepo()
```

Select a project to change your working directory to that project. Projects are automatically sorted alphabetically.

### Changing Monorepos

Switch monorepos without having to close nvim and cd to a different directory:

```lua
:lua require("monorepo").change_monorepo("/path/to/monorepo")
```

When you change monorepos, the plugin will automatically detect the new monorepo root from `pnpm-workspace.yaml` and auto-detect projects.

This pairs well with something like [telescope-project.nvim](https://github.com/nvim-telescope/telescope-project.nvim), which offers a hook when changing projects.

## FAQ

### Does this persist between sessions?

No. The plugin does not save any data to disk. Projects are auto-detected fresh from `pnpm-workspace.yaml` every time the plugin is initialized or when you change monorepos.

### How does auto-detection work?

The plugin automatically detects projects from `pnpm-workspace.yaml`:

1. The plugin searches for `pnpm-workspace.yaml` by walking up from the current directory
2. It parses the workspace file to extract package patterns
3. It resolves wildcard patterns (e.g., `apps/*`) to actual directories
4. Only directories containing `package.json` are included as valid packages

Auto-detection runs automatically when:
- The plugin is initialized (`setup()`)
- You change monorepos (`change_monorepo()`)

## Future Features

- Support for other workspace formats (yarn, npm, lerna, etc.)
- Lualine support
- Integration with popular file tree plugins
