local Path = require("plenary.path")
local scan_dir = require("plenary.scandir")

local M = {}

-- Get the relative directory of path param,
---@param file string
---@param netrw boolean
---@return string|nil
M.get_project_directory = function(file, netrw)
  local currentMonorepo = require("monorepo").currentMonorepo
  local idx = string.find(file, currentMonorepo, 1, true)
  if idx then
    local relative_path = string.sub(file, idx + #currentMonorepo + 0)
    -- If netrw then string is already a diretory
    if netrw then
      return relative_path
    end
    -- If not netrw then remove filename from string
    local project_directory = string.match(relative_path, "(.-)[^/]+$") -- remove filename
    project_directory = project_directory:sub(1, -2) -- remove trailing slash
    return project_directory
  else
    return nil
  end
end

-- Save monorepoVars and favorites to data_path/monorepo.json
M.save = function()
  local module = require("monorepo")
  local data_path = module.config.data_path
  local persistent_json = data_path .. "/monorepo.json"
  -- Save both projects and favorites
  local save_data = {
    projects = module.monorepoVars,
    favorites = module.monorepoFavorites,
  }
  Path:new(persistent_json):write(vim.fn.json_encode(save_data), "w")
end

-- Load json file from data_path/monorepo.json into init module.
---@return boolean, table|nil
M.load = function()
  local module = require("monorepo")
  local data_path = module.config.data_path
  local persistent_json = data_path .. "/monorepo.json"
  local status, load = pcall(function()
    return vim.json.decode(Path:new(persistent_json):read())
  end, persistent_json)

  if status and load then
    -- Handle old format (just projects) and new format (projects + favorites)
    if load.projects then
      -- New format
      module.monorepoVars = load.projects
      module.monorepoFavorites = load.favorites or {}
    else
      -- Old format - migrate
      module.monorepoVars = load
      module.monorepoFavorites = {}
    end
    
    if not module.monorepoVars[module.currentMonorepo] then
      module.monorepoVars[module.currentMonorepo] = { "/" }
    end
    -- Initialize favorites if not present
    if not module.monorepoFavorites[module.currentMonorepo] then
      module.monorepoFavorites[module.currentMonorepo] = {}
    end
  else
    module.monorepoVars = {}
    module.monorepoVars[module.currentMonorepo] = { "/" }
    module.monorepoFavorites = {}
    module.monorepoFavorites[module.currentMonorepo] = {}
  end

  -- Auto-detect projects from pnpm-workspace.yaml if enabled
  if module.config.auto_detect then
    local detected_projects = M.auto_detect_projects(module.currentMonorepo)
    if detected_projects and #detected_projects > 0 then
      -- Merge detected projects with existing ones (avoid duplicates)
      local existing_projects = module.monorepoVars[module.currentMonorepo] or { "/" }
      local seen = {}
      
      -- Mark existing projects
      for _, proj in ipairs(existing_projects) do
        seen[proj] = true
      end
      
      -- Add detected projects that aren't already in the list
      for _, proj in ipairs(detected_projects) do
        if not seen[proj] then
          table.insert(existing_projects, proj)
          seen[proj] = true
        end
      end
      
      module.monorepoVars[module.currentMonorepo] = existing_projects
    end
  end

  module.currentProjects = module.monorepoVars[module.currentMonorepo]
  module.currentFavorites = module.monorepoFavorites[module.currentMonorepo] or {}
end

-- Extend vim.notify to include silent option
M.notify = function(message)
  if require("monorepo").config.silent then
    return
  end
  vim.notify(message)
end

M.index_of = function(array, value)
  for i, v in ipairs(array) do
    if v == value then
      return i
    end
  end
  return nil
end

M.format_path = function(path)
  -- Remove leading ./ and add leading /
  if path:sub(1, 2) == "./" then
    path = path:sub(2)
  end
  -- Add leading /
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return path
end

-- Find pnpm-workspace.yaml by walking up the directory tree
---@param start_path string|nil
---@return string|nil
M.find_pnpm_workspace = function(start_path)
  start_path = start_path or vim.fn.getcwd()
  local current = Path:new(start_path)
  
  while current:exists() do
    local workspace_file = current:joinpath("pnpm-workspace.yaml")
    if workspace_file:exists() then
      return workspace_file:absolute()
    end
    
    local parent = current:parent()
    if not parent or parent.filename == current.filename then
      break
    end
    current = parent
  end
  
  return nil
end

-- Parse pnpm-workspace.yaml file
-- Simple YAML parser for the specific structure of pnpm-workspace.yaml
---@param file_path string
---@return string[]|nil
M.parse_pnpm_workspace = function(file_path)
  local content = Path:new(file_path):read()
  if not content then
    return nil
  end
  
  local patterns = {}
  local in_packages = false
  
  for line in content:gmatch("[^\r\n]+") do
    -- Remove leading/trailing whitespace
    line = line:match("^%s*(.-)%s*$")
    
    -- Check if we're in the packages section
    if line:match("^packages:") then
      in_packages = true
    elseif line:match("^[^%s-]") and in_packages then
      -- If we hit a non-indented line, we're out of packages section
      break
    elseif in_packages and line:match("^%s*-") then
      -- Extract the pattern (remove leading -, whitespace, and quotes)
      local pattern = line:match("^%s*-%s*['\"](.+)['\"]")
      if not pattern then
        pattern = line:match("^%s*-%s*(.+)")
        pattern = pattern:match("^%s*(.-)%s*$")
      end
      if pattern and pattern ~= "" then
        table.insert(patterns, pattern)
      end
    end
  end
  
  return #patterns > 0 and patterns or nil
end

-- Resolve workspace patterns to actual directory paths
-- Patterns like 'apps/*' or 'packages/*' are resolved to actual directories
---@param monorepo_root string
---@param patterns string[]
---@return string[]
M.resolve_workspace_patterns = function(monorepo_root, patterns)
  local resolved_paths = {}
  local seen = {}
  
  -- Helper function to escape special characters for lua pattern matching
  local function escape_pattern(str)
    return str:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
  end
  
  -- Helper function to convert glob pattern to lua pattern
  local function glob_to_lua_pattern(glob)
    -- Escape all special characters first, then replace * with .*
    local escaped = escape_pattern(glob)
    -- Replace escaped \* with .*
    escaped = escaped:gsub("%%%*", ".*")
    return "^" .. escaped .. "$"
  end
  
  for _, pattern in ipairs(patterns) do
    -- Remove quotes if present
    pattern = pattern:gsub("^['\"](.+)['\"]$", "%1")
    
    -- Check if pattern contains wildcard
    local has_wildcard = pattern:match("%*")
    
    if has_wildcard then
      -- Pattern with wildcard: e.g., 'apps/*'
      local base_dir = pattern:match("^(.+)/%*$")
      if base_dir then
        local base_path = Path:new(monorepo_root):joinpath(base_dir)
        
        if base_path:exists() and base_path:is_dir() then
          -- Scan directory for subdirectories
          local entries = scan_dir.scan_dir(base_path.filename, {
            only_dirs = true,
            depth = 1,
          })
          
          local lua_pattern = glob_to_lua_pattern(pattern)
          
          for _, entry in ipairs(entries) do
            local entry_path = Path:new(entry)
            local relative_path = entry_path:make_relative(monorepo_root)
            
            -- Check if it matches the pattern
            if relative_path:match(lua_pattern) then
              -- Check if it has a package.json (indicating it's a package)
              local package_json = entry_path:joinpath("package.json")
              if package_json:exists() then
                local formatted_path = M.format_path(relative_path)
                if not seen[formatted_path] then
                  table.insert(resolved_paths, formatted_path)
                  seen[formatted_path] = true
                end
              end
            end
          end
        end
      end
    else
      -- Exact path pattern (no wildcard)
      local exact_path = Path:new(monorepo_root):joinpath(pattern)
      
      if exact_path:exists() then
        if exact_path:is_dir() then
          -- Check if it has a package.json (indicating it's a package)
          local package_json = exact_path:joinpath("package.json")
          if package_json:exists() then
            local relative_path = exact_path:make_relative(monorepo_root)
            local formatted_path = M.format_path(relative_path)
            if not seen[formatted_path] then
              table.insert(resolved_paths, formatted_path)
              seen[formatted_path] = true
            end
          end
        elseif exact_path:is_file() then
          -- Single file path (less common but possible)
          local relative_path = exact_path:make_relative(monorepo_root)
          local formatted_path = M.format_path(relative_path)
          if not seen[formatted_path] then
            table.insert(resolved_paths, formatted_path)
            seen[formatted_path] = true
          end
        end
      end
    end
  end
  
  -- Sort paths for consistency
  table.sort(resolved_paths)
  
  return resolved_paths
end

-- Auto-detect projects from pnpm-workspace.yaml
---@param monorepo_root string
---@return string[]|nil
M.auto_detect_projects = function(monorepo_root)
  local workspace_file = M.find_pnpm_workspace(monorepo_root)
  if not workspace_file then
    return nil
  end
  
  local patterns = M.parse_pnpm_workspace(workspace_file)
  if not patterns then
    return nil
  end
  
  local projects = M.resolve_workspace_patterns(monorepo_root, patterns)
  return #projects > 0 and projects or nil
end

return M
