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

-- Helper function to create entry maker for projects list
local function create_entry_maker()
  return function(entry)
    return {
      value = entry,
      display = entry,
      ordinal = entry,
    }
  end
end

local function select_project(prompt_bufnr)
  actions.close(prompt_bufnr)
  local selection = action_state.get_selected_entry()
  vim.api.nvim_set_current_dir(require("monorepo").currentMonorepo .. "/" .. selection.value)
  utils.notify(messages.SWITCHED_PROJECT .. ": " .. selection.value)
end

local monorepo = function(opts)
  -- Default to a larger dropdown theme if no opts provided
  if not opts then
    opts = require("telescope.themes").get_dropdown({
      width = 0.9,  -- 90% of screen width (default is ~0.8)
      preview_height = 25,  -- Show more lines in preview (default is ~15)
    })
  end
  local monorepo_module = require("monorepo")
  
  pickers
    .new(opts, {
      prompt_title = "Projects - " .. monorepo_module.currentMonorepo,
      finder = finders.new_table({
        results = monorepo_module.currentProjects,
        entry_maker = create_entry_maker(),
      }),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(select_project)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    monorepo = monorepo,
  },
})
