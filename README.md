# monorepo.nvim

![monorepo.nvim demo video. Shows opening a new monorepo and changing scopes using the plugin](demo.gif)

**_monorepo.nvim_** is a plugin to manage the scope of monorepos inside of neovim!

Its goal is to make juggling multiple projects inside of a monorepo a little easier, in combination with Telescope's `find_files`.

**Features:**
- 🚀 **Auto-detection**: Automatically detects projects from `pnpm-workspace.yaml`
- 📦 **Workspace-aware**: Understands pnpm workspace patterns and resolves them to actual packages
- 🔍 **Smart discovery**: Only includes directories with `package.json` files as valid packages
- ⭐ **Favorites**: Star your favorite projects for quick access

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
  silent = false, -- Supresses vim.notify messages
  autoload_telescope = true, -- Automatically loads the telescope extension at setup
  data_path = vim.fn.stdpath("data"), -- Path that monorepo.json gets saved to
  auto_detect = true, -- Auto-detect projects from pnpm-workspace.yaml
}
```

The telescope extension needs to be loaded at any point AFTER `require("telescope").setup()` and `require("monorepo").setup()`.
By default, this is done automatically but you can undo this by setting `{ autoload_telescope = false }` in the config.

This is the snippet you'll need to run to load the extension if doing it manually

```lua
require("telescope").load_extension("monorepo")
```

Set up your keybinds!

```lua
vim.keymap.set("n", "<leader>m", function()
  require("telescope").extensions.monorepo.monorepo()
end)
vim.keymap.set("n", "<leader>f", function()
  require("telescope").extensions.monorepo.favorites()
end)
vim.keymap.set("n", "<leader>n", function()
  require("monorepo").toggle_project()
end)
```

## Usage (These can be mapped to keybinds)

### Auto-Detection (pnpm workspaces)

By default, the plugin automatically detects all projects from your `pnpm-workspace.yaml` file:

1. **Monorepo Root Detection**: The plugin walks up the directory tree to find `pnpm-workspace.yaml`
2. **Pattern Parsing**: Extracts workspace patterns from the file (e.g., `apps/*`, `packages/*`)
3. **Package Resolution**: Resolves patterns to actual directories that contain `package.json`
4. **Auto-Merge**: Detected projects are merged with any manually added projects

**Example `pnpm-workspace.yaml`:**
```yaml
packages:
  - 'apps/*'
  - 'packages/*'
  - 'tools/*'
```

When auto-detection is enabled (default), all directories matching these patterns that contain a `package.json` will be automatically added to your project list.

To disable auto-detection and use manual project management only:

```lua
require("monorepo").setup({
  auto_detect = false,
})
```

### Managing Projects

You can add the current file's directory to the project list (works in netrw and files)

```lua
:lua require("monorepo").add_project()
```

You can also remove it if you don't want it in the project list

```lua
:lua require("monorepo").remove_project()
```

You can also toggle these with a single command

```lua
:lua require("monorepo").toggle_project()
```

You can also use a prompt to manage your projects

```lua
-- You can use "add", "remove" or "toggle" here.
-- If you don't specify any, it defaults to add
:lua require("monorepo").prompt_project("add")
```

### Changing Projects

You can jump to a specific sub-project using its index (they're ordered in the order you added them)

```lua
:lua require("monorepo").go_to_project(index)
```

_I use a for loop here to quickly jump to different indexes_

```lua
for i = 1, 9 do
  set("n", "<leader>" .. i, function()
    require("monorepo").go_to_project(i)
  end)
end
```

There are also functions to jump to the next or previous project

```lua
:lua require("monorepo").next_project()
:lua require("monorepo").previous_project()
```

### Telescope

You can view the project list like this

```lua
:Telescope monorepo
```

or this

```lua
:lua require("telescope").extensions.monorepo.monorepo()
```

You can also manage your projects using keybinds inside of telescope.

```lua
-- Normal Mode
dd -> delete_entry
s  -> toggle_favorite (star/unstar project)

-- Insert Mode
<ctrl-d> -> delete_entry
<ctrl-a> -> add_entry
<ctrl-s> -> toggle_favorite (star/unstar project)
```

The main project picker shows all projects. Use the favorites picker to see only your starred projects.

### Favorites

You can star your favorite projects for quick access! The favorites picker shows only your starred projects with a ⭐ indicator.

**View your favorites:**
```lua
:Telescope monorepo favorites
```

or

```lua
:lua require("telescope").extensions.monorepo.favorites()
```

**Manage favorites programmatically:**
```lua
-- Add current project to favorites
:lua require("monorepo").add_favorite()

-- Remove current project from favorites
:lua require("monorepo").remove_favorite()

-- Toggle favorite status
:lua require("monorepo").toggle_favorite()

-- Check if project is favorited
:lua require("monorepo").is_favorite("/path/to/project")

-- Get all favorites
:lua require("monorepo").get_favorites()
```

**In Telescope:**
- Press `s` (normal mode) or `<c-s>` (insert mode) in the project picker to star/unstar a project
- Press `dd` in the favorites picker to remove a project from favorites

_These are very basic for now and can't be changed in the config, feel free to create an issue to suggest ideas._

### Changing Monorepos

Using this, you can switch monorepos without having to close nvim and cd to a different directory

```lua
:lua require("monorepo").change_monorepo(path)
```

When you change monorepos, the plugin will automatically detect the new monorepo root from `pnpm-workspace.yaml` and auto-detect projects if `auto_detect` is enabled.

This pairs well with something like [telescope-project.nvim](https://github.com/nvim-telescope/telescope-project.nvim), which offers a hook when changing projects.
See an example from my own config below:

```lua
require("telescope").setup({
  extensions = {
    project = {
      on_project_selected = function(prompt_bufnr)
        -- Change dir to the selected project
        project_actions.change_working_directory(prompt_bufnr, false)

        -- Change monorepo directory to the selected project
        local selected_entry = action_state.get_selected_entry(prompt_bufnr)
        require("monorepo").change_monorepo(selected_entry.value)

        require("telescope.builtin").find_files()
      end,
    }
  }
}
```

## FAQ

### Does this persist between sessions? Where does this save?

I use `vim.fn.stdpath("data")` to find the data path and then write a file called `monorepo.json`.
This defaults to `$HOME/.local/share/nvim/` but can be changed in the config with `{ data_path = '/path/to/directory' }`

### How does auto-detection work?

When `auto_detect` is enabled (default):
1. The plugin searches for `pnpm-workspace.yaml` by walking up from the current directory
2. It parses the workspace file to extract package patterns
3. It resolves wildcard patterns (e.g., `apps/*`) to actual directories
4. Only directories containing `package.json` are included as valid packages
5. Detected projects are merged with any manually added projects (no duplicates)

Auto-detection runs automatically when:
- The plugin is initialized (`setup()`)
- You change monorepos (`change_monorepo()`)
- The monorepo data is loaded (`load()`)

## Extras features I wanna add in the future

- Lualine support??
- NerdTree support? what are popular trees/fs plugins?
- Give projects a "nickname"?
- Include info on projects?
- When opening a known subproject, it detects it
- Remove repeated code with add, remove and toggle
- Support for other workspace formats (yarn, npm, lerna, etc.)
