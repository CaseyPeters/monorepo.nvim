local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
  return
end

local finders = require("telescope.finders")
local conf = require("telescope.config").values
local pickers = require("telescope.pickers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local messages = require("monorepo.messages")
local utils = require("monorepo.utils")

-- Helper function to build the combined projects list (favorites at top)
local function build_projects_list()
  local monorepo_module = require("monorepo")
  local all_projects = {}
  local favorites = monorepo_module.get_favorites()
  local seen = {}
  
  -- Sort favorites alphabetically
  local sorted_favorites = {}
  for _, fav in ipairs(favorites) do
    table.insert(sorted_favorites, fav)
    seen[fav] = true
  end
  table.sort(sorted_favorites)
  
  -- Add sorted favorites with star indicator
  for _, fav in ipairs(sorted_favorites) do
    table.insert(all_projects, "⭐ " .. fav)
  end
  
  -- Add separator if there are favorites
  if #favorites > 0 then
    table.insert(all_projects, "─────────────────────────")
  end
  
  -- Collect and sort non-favorite projects
  local non_favorites = {}
  for _, project in ipairs(monorepo_module.currentProjects) do
    if not seen[project] then
      table.insert(non_favorites, project)
    end
  end
  table.sort(non_favorites)
  
  -- Add sorted non-favorite projects
  for _, project in ipairs(non_favorites) do
    table.insert(all_projects, "  " .. project)
  end
  
  return all_projects
end

-- Helper function to create entry maker for projects list
local function create_entry_maker()
  return function(entry)
    -- Skip separator line
    if entry:match("^─+$") then
      return nil
    end
    
    -- Extract the actual project path (remove star/space prefix)
    -- Handle star emoji properly (it's a multi-byte character)
    local project_path = entry:match("^%s*(.+)")
    -- Check if it starts with star emoji (using pattern matching instead of substring)
    if project_path:match("^⭐%s*") then
      -- Remove star emoji and any following spaces
      project_path = project_path:gsub("^⭐%s*", "")
    else
      -- Remove leading spaces
      project_path = project_path:match("^%s*(.+)")
    end
    
    return {
      value = project_path,
      display = entry,
      ordinal = project_path,
    }
  end
end

local function select_project(prompt_bufnr)
  actions.close(prompt_bufnr)
  local selection = action_state.get_selected_entry()
  vim.api.nvim_set_current_dir(require("monorepo").currentMonorepo .. "/" .. selection.value)
  utils.notify(messages.SWITCHED_PROJECT .. ": " .. selection.value)
end

local function delete_entry(prompt_bufnr)
  local selected_entry = action_state.get_selected_entry(prompt_bufnr)
  if not selected_entry then
    return
  end
  if selected_entry.value == "/" then
    utils.notify(messages.CANT_REMOVE_MONOREPO)
    return
  end
  require("monorepo").remove_project(selected_entry.value)
  
  -- Refresh the picker with updated list
  action_state.get_current_picker(prompt_bufnr):refresh(
    finders.new_table({
      results = build_projects_list(),
      entry_maker = create_entry_maker(),
    }),
    { reset_prompt = true }
  )
end

local function add_entry(prompt_bufnr)
  require("monorepo").prompt_project()
  
  -- Refresh the picker with updated list
  action_state.get_current_picker(prompt_bufnr):refresh(
    finders.new_table({
      results = build_projects_list(),
      entry_maker = create_entry_maker(),
    }),
    { reset_prompt = true }
  )
end

local function toggle_favorite_entry(prompt_bufnr)
  local selected_entry = action_state.get_selected_entry(prompt_bufnr)
  if not selected_entry then
    return
  end
  
  if selected_entry.value == "/" then
    utils.notify("Cannot favorite root monorepo")
    return
  end
  
  require("monorepo").toggle_favorite(selected_entry.value)
  utils.notify(
    require("monorepo").is_favorite(selected_entry.value) 
      and messages.ADDED_FAVORITE .. ": " .. selected_entry.value
      or messages.REMOVED_FAVORITE .. ": " .. selected_entry.value
  )
  
  -- Refresh the picker to update the list
  action_state.get_current_picker(prompt_bufnr):refresh(
    finders.new_table({
      results = build_projects_list(),
      entry_maker = create_entry_maker(),
    }),
    { reset_prompt = true }
  )
end

local monorepo = function(opts)
  opts = opts or require("telescope.themes").get_dropdown()
  local monorepo_module = require("monorepo")
  
  pickers
    .new(opts, {
      prompt_title = "Projects - " .. monorepo_module.currentMonorepo,
      finder = finders.new_table({
        results = build_projects_list(),
        entry_maker = create_entry_maker(),
      }),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        map("n", "dd", delete_entry)
        map("i", "<c-d>", delete_entry)
        map("i", "<c-a>", add_entry)
        map("n", "s", toggle_favorite_entry)
        map("i", "<c-s>", toggle_favorite_entry)
        actions.select_default:replace(select_project)
        return true
      end,
    })
    :find()
end

local favorites = function(opts)
  opts = opts or require("telescope.themes").get_dropdown()
  local monorepo_module = require("monorepo")
  local favs = monorepo_module.get_favorites()
  
  if #favs == 0 then
    utils.notify("No favorites yet. Press 's' in the project picker to favorite a project.")
    return
  end
  
  -- Sort favorites alphabetically
  local sorted_favs = {}
  for _, fav in ipairs(favs) do
    table.insert(sorted_favs, fav)
  end
  table.sort(sorted_favs)
  
  -- Format favorites with star indicator
  local formatted_favorites = {}
  for _, fav in ipairs(sorted_favs) do
    table.insert(formatted_favorites, "⭐ " .. fav)
  end
  
  pickers
    .new(opts, {
      prompt_title = "⭐ Favorites - " .. monorepo_module.currentMonorepo,
      finder = finders.new_table({
        results = formatted_favorites,
        entry_maker = function(entry)
          -- Extract the actual project path (remove star prefix)
          local project_path = entry:sub(3):match("^%s*(.+)")
          return {
            value = project_path,
            display = entry,
            ordinal = project_path,
          }
        end,
      }),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        map("n", "dd", function()
          local selected_entry = action_state.get_selected_entry(prompt_bufnr)
          if selected_entry then
            require("monorepo").remove_favorite(selected_entry.value)
            
            -- Reload favorites and refresh
            local monorepo_module = require("monorepo")
            local favs = monorepo_module.get_favorites()
            
            if #favs == 0 then
              actions.close(prompt_bufnr)
              utils.notify("No favorites remaining")
              return
            end
            
            -- Sort favorites alphabetically
            local sorted_favs = {}
            for _, fav in ipairs(favs) do
              table.insert(sorted_favs, fav)
            end
            table.sort(sorted_favs)
            
            local updated_favorites = {}
            for _, fav in ipairs(sorted_favs) do
              table.insert(updated_favorites, "⭐ " .. fav)
            end
            
            action_state.get_current_picker(prompt_bufnr):refresh(
              finders.new_table({
                results = updated_favorites,
                entry_maker = function(entry)
                  local project_path = entry:sub(3):match("^%s*(.+)")
                  return {
                    value = project_path,
                    display = entry,
                    ordinal = project_path,
                  }
                end,
              }),
              { reset_prompt = true }
            )
          end
        end)
        actions.select_default:replace(select_project)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    monorepo = monorepo,
    favorites = favorites,
  },
})
