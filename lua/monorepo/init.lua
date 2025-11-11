local utils = require("monorepo.utils")
local messages = require("monorepo.messages")

local M = {}

M.monorepoVars = {}
M.currentMonorepo = vim.fn.getcwd()
M.currentProjects = {}

M.config = {
  silent = false,
  autoload_telescope = true,
  auto_detect = true, -- Auto-detect projects from pnpm-workspace.yaml
}

---@class pluginConfig
---@field silent boolean
---@field autoload_telescope boolean
---@field auto_detect boolean
---@param config? pluginConfig
M.setup = function(config)
  -- Overwrite default config with user config
  if config then
    for k, v in pairs(config) do
      M.config[k] = v
    end
  end

  vim.opt.autochdir = false

  -- Auto-detect monorepo root from pnpm-workspace.yaml
  M.currentMonorepo = M.detect_monorepo_root()

  -- Auto-detect projects from pnpm-workspace.yaml
  M.load_pnpm_projects()

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
end

-- Load projects list by auto-detecting from pnpm-workspace.yaml
M.load_pnpm_projects = function()
  if M.config.auto_detect then
    local detected_projects = utils.auto_detect_projects(M.currentMonorepo)
    if detected_projects and #detected_projects > 0 then
      M.monorepoVars[M.currentMonorepo] = detected_projects
    else
      -- If no projects detected, default to root
      M.monorepoVars[M.currentMonorepo] = { "/" }
    end
  else
    -- If auto-detect is disabled, default to root
    M.monorepoVars[M.currentMonorepo] = { "/" }
  end

  M.currentProjects = M.monorepoVars[M.currentMonorepo] or { "/" }
end

M.go_to_project = function(index)
  local project = M.monorepoVars[M.currentMonorepo][index]
  if not project then
    return
  end
  vim.api.nvim_set_current_dir(M.currentMonorepo .. "/" .. project)
  utils.notify(messages.SWITCHED_PROJECT .. ": " .. project)
end

M.change_monorepo = function(path)
  -- Auto-detect monorepo root from the provided path
  M.currentMonorepo = M.detect_monorepo_root(path)
  -- Load projects for the new monorepo
  M.load_pnpm_projects()
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

return M
