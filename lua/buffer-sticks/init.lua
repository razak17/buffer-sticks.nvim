-- luacheck: globals vim

---@class BufferSticks
---@field setup function Setup the buffer sticks plugin
---@field toggle function Toggle the visibility of buffer sticks
---@field show function Show the buffer sticks
---@field hide function Hide the buffer sticks
local M = {}

---@class BufferSticksState
---@field win number Window handle for the floating window
---@field buf number Buffer handle for the display buffer
---@field visible boolean Whether the buffer sticks are currently visible
local state = {
	win = -1,
	buf = -1,
	visible = false,
}

---@class BufferSticksHighlights
---@field fg? string Foreground color (hex color or highlight group name)
---@field bg? string Background color (hex color or highlight group name)
---@field bold? boolean Bold text
---@field italic? boolean Italic text
---@field link? string Link to existing highlight group (alternative to defining colors)

---@class BufferSticksOffset
---@field x number Horizontal offset from default position
---@field y number Vertical offset from default position

---@class BufferSticksFilter
---@field filetypes? string[] List of filetypes to exclude from buffer sticks
---@field names? string[] List of buffer name patterns to exclude (supports lua patterns)

---@class BufferSticksConfig
---@field position "left"|"right" Position of the buffer sticks on screen
---@field width number Width of the floating window
---@field offset BufferSticksOffset Position offset for fine-tuning
---@field active_char string Character to display for the active buffer
---@field inactive_char string Character to display for inactive buffers
---@field transparent boolean Whether the background should be transparent
---@field winblend? number Window blend/transparency level (0-100, overrides transparent)
---@field filter? BufferSticksFilter Filter configuration for excluding buffers
---@field highlights table<string, BufferSticksHighlights> Highlight groups for active/inactive states
local config = {
	position = "right", -- "left" or "right"
	width = 3,
	offset = { x = 0, y = 0 },
	active_char = "──",
	inactive_char = " ─",
	transparent = true,
	highlights = {
		active = { fg = "#ffffff", bold = true },
		inactive = { fg = "#666666" },
	},
}

---@class BufferInfo
---@field id number Buffer ID
---@field name string Buffer name/path
---@field is_current boolean Whether this is the currently active buffer

---Get a list of all loaded and listed buffers with filtering applied
---@return BufferInfo[] buffers List of buffer information
local function get_buffer_list()
	local buffers = {}
	local current_buf = vim.api.nvim_get_current_buf()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			local buf_filetype = vim.bo[buf].filetype
			local should_include = true

			-- Filter by filetype
			if config.filter and config.filter.filetypes then
				for _, ft in ipairs(config.filter.filetypes) do
					if buf_filetype == ft then
						should_include = false
						break
					end
				end
			end

			-- Filter by buffer name patterns
			if should_include and config.filter and config.filter.names then
				for _, pattern in ipairs(config.filter.names) do
					if buf_name:match(pattern) then
						should_include = false
						break
					end
				end
			end

			if should_include then
				table.insert(buffers, {
					id = buf,
					name = buf_name,
					is_current = buf == current_buf,
				})
			end
		end
	end

	return buffers
end

---@class WindowInfo
---@field buf number Buffer handle
---@field win number Window handle

---Create and configure the floating window for buffer sticks
---@return WindowInfo window_info Information about the created window and buffer
local function create_floating_window()
	local buffers = get_buffer_list()
	local height = math.max(#buffers, 1)
	local width = config.width

	-- Position based on config
	local col = config.position == "right" and vim.o.columns - width + config.offset.x or 0 + config.offset.x
	local row = math.floor((vim.o.lines - height) / 2) + config.offset.y

	-- Create buffer if needed
	if not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].bufhidden = "wipe"
		vim.bo[state.buf].filetype = "buffersticks"
	end

	-- Create window
	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 10,
	}

	-- Set background based on transparency setting
	if not config.transparent then
		win_config.style = "minimal"
		-- Add a background highlight group if not transparent
	end

	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_config(state.win, win_config)
	else
		state.win = vim.api.nvim_open_win(state.buf, false, win_config)
	end

	-- Set transparency using winblend after window creation
	if config.winblend then
		vim.api.nvim_win_set_option(state.win, "winblend", config.winblend)
	elseif config.transparent then
		vim.api.nvim_win_set_option(state.win, "winblend", 100)
	else
		vim.api.nvim_win_set_option(state.win, "winblend", 0)
	end

	-- Set window background based on transparency
	if not config.winblend and not config.transparent then
		vim.api.nvim_win_set_option(state.win, "winhl", "Normal:BufferSticksBackground")
	else
		vim.api.nvim_win_set_option(state.win, "winhl", "Normal:NONE")
	end

	return { buf = state.buf, win = state.win }
end

---Render buffer indicators in the floating window
---Updates the buffer content and applies appropriate highlighting
local function render_buffers()
	if not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local buffers = get_buffer_list()
	local lines = {}

	for _, buffer in ipairs(buffers) do
		if buffer.is_current then
			table.insert(lines, config.active_char)
		else
			table.insert(lines, config.inactive_char)
		end
	end

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

	-- Set highlights
	for i, buffer in ipairs(buffers) do
		if buffer.is_current then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "BufferSticksActive", i - 1, 0, -1)
		else
			vim.api.nvim_buf_add_highlight(state.buf, -1, "BufferSticksInactive", i - 1, 0, -1)
		end
	end
end

---Show the buffer sticks floating window
---Creates the window and renders the current buffer state
local function show()
	create_floating_window()
	render_buffers()
	state.visible = true
end

---Hide the buffer sticks floating window
---Closes the window and updates the visibility state
local function hide()
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
		state.win = -1
	end
	state.visible = false
end

---Toggle the visibility of buffer sticks
---Shows if hidden, hides if visible
local function toggle()
	if state.visible then
		hide()
	else
		show()
	end
end

---Setup the buffer sticks plugin with user configuration
---@param opts? BufferSticksConfig User configuration options to override defaults
function M.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", config, opts)

	-- Helper function to set up highlights
	local function setup_highlights()
		-- Check if we're using transparency (either winblend or transparent flag)
		local is_transparent = config.winblend or config.transparent

		if config.highlights.active.link then
			vim.api.nvim_set_hl(0, "BufferSticksActive", { link = config.highlights.active.link })
		else
			local active_hl = vim.deepcopy(config.highlights.active)
			if is_transparent then
				active_hl.bg = nil  -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksActive", active_hl)
		end

		if config.highlights.inactive.link then
			vim.api.nvim_set_hl(0, "BufferSticksInactive", { link = config.highlights.inactive.link })
		else
			local inactive_hl = vim.deepcopy(config.highlights.inactive)
			if is_transparent then
				inactive_hl.bg = nil  -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksInactive", inactive_hl)
		end

		-- Set up background highlight for non-transparent mode
		if not is_transparent then
			vim.api.nvim_set_hl(0, "BufferSticksBackground", { bg = "#1e1e1e" })
		end
	end

	-- Set up highlights initially
	setup_highlights()

	-- Auto-update on buffer changes and colorscheme changes
	local augroup = vim.api.nvim_create_augroup("BufferSticks", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function()
			if state.visible then
				vim.schedule(function()
					show() -- Refresh the display
				end)
			end
		end,
	})

	-- Reapply highlights when colorscheme changes
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			vim.schedule(setup_highlights)
		end,
	})

	-- Reposition window when terminal is resized
	vim.api.nvim_create_autocmd("VimResized", {
		group = augroup,
		callback = function()
			if state.visible then
				vim.schedule(function()
					show() -- Refresh the display and position
				end)
			end
		end,
	})

	-- Store globally for access
	_G.BufferSticks = {
		toggle = toggle,
		show = show,
		hide = hide,
	}

	-- Create user command
	vim.api.nvim_create_user_command("BufferSticks", function()
		toggle()
	end, { desc = "Toggle buffer stick visualization" })
end

-- Expose functions for direct access
M.toggle = toggle
M.show = show
M.hide = hide

return M
