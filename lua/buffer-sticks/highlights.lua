-- luacheck: globals vim
-- Highlight group setup

local config = require("buffer-sticks.config")

local M = {}

---Set up a single highlight group
---@param name string Highlight group name
---@param hl_config table Highlight configuration
---@param is_transparent boolean Whether transparent mode is enabled
local function set_highlight(name, hl_config, is_transparent)
	if not hl_config then
		return
	end

	if hl_config.link then
		vim.api.nvim_set_hl(0, name, { link = hl_config.link })
	else
		local hl = vim.deepcopy(hl_config)
		if is_transparent then
			hl.bg = nil
		end
		vim.api.nvim_set_hl(0, name, hl)
	end
end

---Set up all highlight groups
function M.setup()
	local is_transparent = config.transparent

	set_highlight("BufferSticksActive", config.highlights.active, is_transparent)
	set_highlight("BufferSticksAlternate", config.highlights.alternate, is_transparent)
	set_highlight("BufferSticksInactive", config.highlights.inactive, is_transparent)
	set_highlight("BufferSticksActiveModified", config.highlights.active_modified, is_transparent)
	set_highlight("BufferSticksAlternateModified", config.highlights.alternate_modified, is_transparent)
	set_highlight("BufferSticksInactiveModified", config.highlights.inactive_modified, is_transparent)
	set_highlight("BufferSticksLabel", config.highlights.label, is_transparent)
	set_highlight("BufferSticksFilterSelected", config.highlights.filter_selected, is_transparent)
	set_highlight("BufferSticksFilterTitle", config.highlights.filter_title, is_transparent)
	set_highlight("BufferSticksListSelected", config.highlights.list_selected, is_transparent)

	if not is_transparent then
		vim.api.nvim_set_hl(0, "BufferSticksBackground", { bg = "#1e1e1e" })
	end
end

return M
