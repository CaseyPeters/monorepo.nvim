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
  local monorepo_module = require("monorepo")
  action_state.get_current_picker(prompt_bufnr):refresh(
    finders.new_table({
      results = monorepo_module.currentProjects,
    }),
    { reset_prompt = true }
  )
end

local function add_entry(prompt_bufnr)
  require("monorepo").prompt_project()
  local monorepo_module = require("monorepo")
  action_state.get_current_picker(prompt_bufnr):refresh(
    finders.new_table({
      results = monorepo_module.currentProjects,
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
end

local monorepo = function(opts)
  opts = opts or require("telescope.themes").get_dropdown()
  local monorepo_module = require("monorepo")
  
  -- Show all projects (no star indicators in main picker)
  pickers
    .new(opts, {
      prompt_title = "Projects - " .. monorepo_module.currentMonorepo,
      finder = finders.new_table({
        results = monorepo_module.currentProjects,
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
  
  -- Format favorites with star indicator
  local formatted_favorites = {}
  for _, fav in ipairs(favs) do
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
            
            local updated_favorites = {}
            for _, fav in ipairs(favs) do
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
