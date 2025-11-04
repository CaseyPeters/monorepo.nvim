local utils = require("monorepo.utils")
local messages = require("monorepo.messages")

local M = {}

M.monorepoVars = {}
M.monorepoFavorites = {}
M.currentMonorepo = vim.fn.getcwd()

M.config = {
  silent = false,
  autoload_telescope = true,
  data_path = vim.fn.stdpath("data"),
  auto_detect = true, -- Auto-detect projects from pnpm-workspace.yaml
  default_keybindings = false, -- Set up default keybindings automatically
  keybindings = {
    -- Telescope pickers
    open_projects = "<leader>mm", -- Open projects picker (shows favorites at top)
    -- Project management
    toggle_project = "<leader>mn", -- Toggle current project
    -- Navigation (optional, can be disabled by setting to nil)
    next_project = "<leader>m]", -- Navigate to next project
    prev_project = "<leader>m[", -- Navigate to previous project
  },
}

---@class pluginConfig
---@field silent boolean
---@field autoload_telescope boolean
---@field data_path string
---@field auto_detect boolean
---@field default_keybindings boolean
---@field keybindings table|nil
---@param config? pluginConfig
M.setup = function(config)
  -- Overwrite default config with user config
  if config then
    for k, v in pairs(config) do
      if k == "keybindings" and type(v) == "table" then
        -- Deep merge keybindings table
        M.config.keybindings = vim.tbl_deep_extend("force", M.config.keybindings, v)
      else
        M.config[k] = v
      end
    end
  end

  vim.opt.autochdir = false
  
  -- Auto-detect monorepo root from pnpm-workspace.yaml
  M.currentMonorepo = M.detect_monorepo_root()
  
  utils.load() -- Load monorepo.json

  -- I don't know if this is bad practice but I had weird issues where
  -- sometimes telescope would load before my setup function
  -- and cause the picker to bug out
  if M.config.autoload_telescope then
    local has_telescope, telescope = pcall(require, "telescope")
    if has_telescope then
      telescope.load_extension("monorepo")
    end
  end

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      M.change_monorepo(vim.fn.getcwd())
    end,
  })

  -- Set up default keybindings if enabled
  if M.config.default_keybindings then
    M.setup_keybindings()
  end
end

-- Set up default keybindings
M.setup_keybindings = function()
  local kb = M.config.keybindings

  -- Open projects picker
  if kb.open_projects then
    vim.keymap.set("n", kb.open_projects, function()
      local has_telescope, telescope = pcall(require, "telescope")
      if has_telescope then
        telescope.extensions.monorepo.monorepo()
      else
        utils.notify("Telescope is required for the projects picker")
      end
    end, { desc = "Monorepo: Open projects picker" })
  end

  -- Toggle project
  if kb.toggle_project then
    vim.keymap.set("n", kb.toggle_project, function()
      M.toggle_project()
    end, { desc = "Monorepo: Toggle current project" })
  end

  -- Navigate to next project
  if kb.next_project then
    vim.keymap.set("n", kb.next_project, function()
      M.next_project()
    end, { desc = "Monorepo: Go to next project" })
  end

  -- Navigate to previous project
  if kb.prev_project then
    vim.keymap.set("n", kb.prev_project, function()
      M.previous_project()
    end, { desc = "Monorepo: Go to previous project" })
  end
end

-- If no dir is passed, it will use the current buffer's directory
---@param dir string|nil
M.add_project = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  local projects = M.monorepoVars[M.currentMonorepo]
  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end
  if vim.tbl_contains(projects, dir) then
    utils.notify(messages.DUPLICATE_PROJECT)
    return
  end
  projects = table.insert(projects or {}, dir)
  utils.notify(messages.ADDED_PROJECT .. ": " .. dir)
  utils.save()
end

-- If no dir is passed, it will use the current buffer's directory
---@param dir string|nil
M.remove_project = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  local projects = M.monorepoVars[M.currentMonorepo]
  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end
  if not vim.tbl_contains(projects, dir) then
    utils.notify(messages.CANT_REMOVE_PROJECT)
    return
  end
  projects = table.remove(projects, utils.index_of(projects, dir))
  utils.notify(messages.REMOVED_PROJECT .. ": " .. dir)
  utils.save()
end

-- If no dir is passed, it will use the current buffer's directory
---@param dir string|nil
M.toggle_project = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  -- if starts with /
  local projects = M.monorepoVars[M.currentMonorepo]

  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end

  if vim.tbl_contains(projects, dir) then
    projects = table.remove(projects, utils.index_of(projects, dir))
    utils.notify(messages.REMOVED_PROJECT .. ": " .. dir)
    utils.save()
    return
  else
    projects = table.insert(projects or {}, dir)
    utils.notify(messages.ADDED_PROJECT .. ": " .. dir)
    utils.save()
    return
  end
end

-- Text box prompt for editing project list.
-- Defaults to add.
---@param action "add"|"remove"|"toggle"|nil
M.prompt_project = function(action)
  if not action then
    action = "add"
  end

  if action ~= "add" and action ~= "remove" and action ~= "toggle" then
    utils.notify(messages.INVALID_ACTION)
    return
  end

  if action == "add" then
    local dir = vim.fn.input(messages.ADD_PROJECT)
    dir = utils.format_path(dir)
    M.add_project(dir)
    return
  end

  if action == "remove" then
    local dir = vim.fn.input(messages.REMOVE_PROJECT)
    dir = utils.format_path(dir)
    M.remove_project(dir)
    return
  end

  if action == "toggle" then
    local dir = vim.fn.input(messages.TOGGLE_PROJECT)
    dir = utils.format_path(dir)
    M.toggle_project(dir)
    return
  end
end

M.go_to_project = function(index)
  local project = M.monorepoVars[M.currentMonorepo][index]
  if not project then
    return
  end
  vim.api.nvim_set_current_dir(M.currentMonorepo .. "/" .. project)
  utils.notify(messages.SWITCHED_PROJECT .. ": " .. project)
end

M.next_project = function()
  local projects = M.monorepoVars[M.currentMonorepo]
  local current_project = "/"
  if vim.fn.getcwd() ~= M.currentMonorepo then
    current_project = vim.fn.getcwd():sub(#M.currentMonorepo + 1)
  end

  local index = utils.index_of(projects, current_project)
  if not index then
    return
  end
  if index == #projects then
    index = 1
  else
    index = index + 1
  end
  M.go_to_project(index)
end

M.previous_project = function()
  local projects = M.monorepoVars[M.currentMonorepo]
  local current_project = "/"
  if vim.fn.getcwd() ~= M.currentMonorepo then
    current_project = vim.fn.getcwd():sub(#M.currentMonorepo + 1)
  end

  local index = utils.index_of(projects, current_project)
  if not index then
    return
  end
  if index == 1 then
    index = #projects
  else
    index = index - 1
  end
  M.go_to_project(index)
end

M.change_monorepo = function(path)
  -- Auto-detect monorepo root from the provided path
  M.currentMonorepo = M.detect_monorepo_root(path)
  utils.load()
end

-- Detect monorepo root from pnpm-workspace.yaml location
M.detect_monorepo_root = function(start_path)
  start_path = start_path or vim.fn.getcwd()
  local workspace_file = utils.find_pnpm_workspace(start_path)
  if workspace_file then
    local Path = require("plenary.path")
    return Path:new(workspace_file):parent().filename
  end
  return start_path
end

-- Favorite management functions
M.add_favorite = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end

  -- Ensure favorites structure exists
  if not M.monorepoFavorites[M.currentMonorepo] then
    M.monorepoFavorites[M.currentMonorepo] = {}
  end

  local favorites = M.monorepoFavorites[M.currentMonorepo]
  if vim.tbl_contains(favorites, dir) then
    utils.notify(messages.DUPLICATE_FAVORITE)
    return
  end

  table.insert(favorites, dir)
  utils.notify(messages.ADDED_FAVORITE .. ": " .. dir)
  utils.save()
end

M.remove_favorite = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end

  local favorites = M.monorepoFavorites[M.currentMonorepo] or {}
  if not vim.tbl_contains(favorites, dir) then
    utils.notify(messages.CANT_REMOVE_FAVORITE)
    return
  end

  table.remove(favorites, utils.index_of(favorites, dir))
  utils.notify(messages.REMOVED_FAVORITE .. ": " .. dir)
  utils.save()
end

M.toggle_favorite = function(dir)
  if dir and dir:sub(1, 1) ~= "/" then
    utils.notify(messages.INVALID_PATH)
    return
  end

  dir = dir or utils.get_project_directory(vim.api.nvim_buf_get_name(0), vim.bo.filetype == "netrw")
  if not dir or dir == "" then
    utils.notify(messages.NOT_IN_SUBPROJECT)
    return
  end

  -- Ensure favorites structure exists
  if not M.monorepoFavorites[M.currentMonorepo] then
    M.monorepoFavorites[M.currentMonorepo] = {}
  end

  local favorites = M.monorepoFavorites[M.currentMonorepo]
  if vim.tbl_contains(favorites, dir) then
    table.remove(favorites, utils.index_of(favorites, dir))
    utils.notify(messages.REMOVED_FAVORITE .. ": " .. dir)
    utils.save()
    return
  else
    table.insert(favorites, dir)
    utils.notify(messages.ADDED_FAVORITE .. ": " .. dir)
    utils.save()
    return
  end
end

M.is_favorite = function(dir)
  local favorites = M.monorepoFavorites[M.currentMonorepo] or {}
  return vim.tbl_contains(favorites, dir)
end

M.get_favorites = function()
  return M.monorepoFavorites[M.currentMonorepo] or {}
end

return M
