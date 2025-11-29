-- luacheck: globals vim
-- Plugin state management

---@class BufferSticksState
---@field wins table<integer, integer> Map of tabpage to window handle
---@field buf integer Buffer handle for the display buffer
---@field visible boolean Whether the buffer sticks are currently visible
---@field cached_buffer_ids integer[] Cached list of buffer IDs for label generation
---@field cached_labels table<integer, string> Map of buffer ID to generated label
---@field list_mode boolean Whether list mode is active
---@field list_input string Current input in list mode
---@field list_action "open"|"close"|function Current action in list mode
---@field list_mode_selected_index integer|nil Currently selected buffer index in list mode (non-filter)
---@field last_selected_buffer_id integer|nil Last selected buffer ID (persists across sessions)
---@field filter_mode boolean Whether filter mode is active
---@field filter_input string Current filter input string
---@field filter_selected_index integer Currently selected buffer index in filtered results
---@field auto_hidden boolean Whether the window is currently auto-hidden
---@field win_pos table Window position data for collision detection
---@field preview_origin_win integer|nil Original window before preview
---@field preview_origin_buf integer|nil Original buffer before preview
---@field preview_float_win integer|nil Preview float window handle
---@field preview_float_buf integer|nil Preview float buffer handle
local M = {
	wins = {},
	buf = -1,
	visible = false,
	list_mode = false,
	list_input = "",
	list_action = "open",
	list_mode_selected_index = nil,
	last_selected_buffer_id = nil,
	filter_mode = false,
	filter_input = "",
	filter_selected_index = 1,
	cached_buffer_ids = {},
	cached_labels = {},
	auto_hidden = false,
	win_pos = { col = 0, row = 0, width = 0, height = 0 },
	preview_origin_win = nil,
	preview_origin_buf = nil,
	preview_float_win = nil,
	preview_float_buf = nil,
}

---Reset state to initial values
function M.reset()
	M.wins = {}
	M.buf = -1
	M.visible = false
	M.list_mode = false
	M.list_input = ""
	M.list_action = "open"
	M.list_mode_selected_index = nil
	M.last_selected_buffer_id = nil
	M.filter_mode = false
	M.filter_input = ""
	M.filter_selected_index = 1
	M.cached_buffer_ids = {}
	M.cached_labels = {}
	M.auto_hidden = false
	M.win_pos = { col = 0, row = 0, width = 0, height = 0 }
	M.preview_origin_win = nil
	M.preview_origin_buf = nil
	M.preview_float_win = nil
	M.preview_float_buf = nil
end

---Invalidate label cache
function M.invalidate_cache()
	M.cached_buffer_ids = {}
	M.cached_labels = {}
end

return M
