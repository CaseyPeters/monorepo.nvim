local Path = require("plenary.path")
local scan_dir = require("plenary.scandir")

local M = {}

-- Extend vim.notify to include silent option
M.notify = function(message)
  if require("monorepo").config.silent then
    return
  end
  vim.notify(message)
end

-- Format a path to ensure it starts with '/' and is normalized
---@param path string
---@return string
M.format_path = function(path)
  if not path or path == "" then
    return "/"
  end
  
  -- Remove trailing slashes
  path = path:gsub("/+$", "")
  if path == "" then
    return "/"
  end
  
  -- Ensure it starts with /
  if not path:match("^/") then
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
  
  -- Helper: Check if directory is a valid package (has package.json)
  local function is_valid_package(dir_path)
    return dir_path:joinpath("package.json"):exists()
  end
  
  -- Helper: Add path to results if valid
  local function add_if_valid(dir_path)
    if not is_valid_package(dir_path) then
      return
    end
    
    local relative_path = dir_path:make_relative(monorepo_root)
    if not relative_path or relative_path == "" then
      return
    end
    
    local formatted_path = M.format_path(relative_path)
    if not seen[formatted_path] then
      table.insert(resolved_paths, formatted_path)
      seen[formatted_path] = true
    end
  end
  
  -- Helper: Convert glob pattern to lua pattern
  local function glob_to_lua_pattern(glob)
    return "^" .. glob:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0"):gsub("%%%*", ".*") .. "$"
  end
  
  for _, pattern in ipairs(patterns) do
    -- Remove quotes if present
    pattern = pattern:gsub("^['\"](.+)['\"]$", "%1")
    
    if pattern:match("%*") then
      -- Wildcard pattern: e.g., 'apps/*'
      local base_dir = pattern:match("^(.+)/%*$")
      if base_dir then
        local base_path = Path:new(monorepo_root):joinpath(base_dir)
        if base_path:exists() and base_path:is_dir() then
          local success, entries = pcall(function()
            return scan_dir.scan_dir(base_path.filename, { only_dirs = true, depth = 1 })
          end)
          
          if success and entries then
            local lua_pattern = glob_to_lua_pattern(pattern)
            for _, entry in ipairs(entries) do
              local entry_path = Path:new(entry)
              local relative_path = entry_path:make_relative(monorepo_root)
              if relative_path and relative_path:match(lua_pattern) then
                add_if_valid(entry_path)
              end
            end
          end
        end
      end
    else
      -- Exact path pattern
      local exact_path = Path:new(monorepo_root):joinpath(pattern)
      if exact_path:exists() and exact_path:is_dir() then
        add_if_valid(exact_path)
      end
    end
  end
  
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
