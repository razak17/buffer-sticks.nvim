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
---@field cached_buffer_ids number[] Cached list of buffer IDs for label generation
---@field cached_labels table<number, string> Map of buffer ID to generated label
local state = {
	win = -1,
	buf = -1,
	visible = false,
	jump_mode = false,
	jump_input = "",
	cached_buffer_ids = {},
	cached_labels = {},
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

---@class BufferSticksJump
---@field show string[] What to show in jump mode: "filename", "space", "label", "stick"

---@class BufferSticksLabel
---@field show "always"|"jump"|"never" When to show buffer name characters

---@class BufferSticksFilter
---@field filetypes? string[] List of filetypes to exclude from buffer sticks
---@field names? string[] List of buffer name patterns to exclude (supports lua patterns)

---@class BufferSticksConfig
---@field offset BufferSticksOffset Position offset for fine-tuning
---@field active_char string Character to display for the active buffer
---@field inactive_char string Character to display for inactive buffers
---@field transparent boolean Whether the background should be transparent
---@field winblend? number Window blend level (0-100)
---@field label? BufferSticksLabel Label display configuration
---@field jump? BufferSticksJump Jump mode configuration
---@field filter? BufferSticksFilter Filter configuration for excluding buffers
---@field highlights table<string, BufferSticksHighlights> Highlight groups for active/inactive/label states
local config = {
	offset = { x = 1, y = 0 },
	active_char = "──",
	inactive_char = " ─",
	transparent = true,
	label = { show = "jump" },
	jump = { show = { "filename", "space", "label" } },
	highlights = {
		active = { fg = "#ffffff", bold = true },
		inactive = { fg = "#666666" },
		label = { fg = "#ffff00" }, -- Highlight for buffer labels
	},
}

---@class BufferInfo
---@field id number Buffer ID
---@field name string Buffer name/path
---@field is_current boolean Whether this is the currently active buffer
---@field label string Generated unique label for this buffer

---Check if buffer list has changed compared to cached version
---@param current_buffer_ids number[] Current list of buffer IDs
---@return boolean changed Whether the buffer list has changed
local function has_buffer_list_changed(current_buffer_ids)
	if #current_buffer_ids ~= #state.cached_buffer_ids then
		return true
	end

	for i, buffer_id in ipairs(current_buffer_ids) do
		if buffer_id ~= state.cached_buffer_ids[i] then
			return true
		end
	end

	return false
end

---Generate unique labels for buffers using collision avoidance algorithm
---@param buffers BufferInfo[] List of buffers to generate labels for
---@return BufferInfo[] buffers List of buffers with unique labels assigned
local function generate_unique_labels(buffers)
	local labels = {}
	local used_labels = {}
	local filename_map = {}

	-- Phase 1: Extract filenames and prepare data
	for _, buffer in ipairs(buffers) do
		local filename = vim.fn.fnamemodify(buffer.name, ":t")
		if filename == "" then
			filename = "?"
		end
		filename_map[buffer.id] = filename:lower()
	end

	-- Phase 2: Assign single character labels where possible
	for _, buffer in ipairs(buffers) do
		local filename = filename_map[buffer.id]
		local first_char = filename:sub(1, 1)
		if first_char:match("%w") and not used_labels[first_char] then
			labels[buffer.id] = first_char
			used_labels[first_char] = true
		end
	end

	-- Phase 3: Resolve conflicts with two-character labels
	for _, buffer in ipairs(buffers) do
		if not labels[buffer.id] then -- Still needs a label
			local filename = filename_map[buffer.id]
			local found_label = false

			-- Try first two characters
			if #filename >= 2 then
				local two_char = filename:sub(1, 2)
				if two_char:match("^%w%w$") and not used_labels[two_char] then
					labels[buffer.id] = two_char
					used_labels[two_char] = true
					found_label = true
				else
					-- Try alternative combinations: first + other chars
					local first_char = filename:sub(1, 1)
					if first_char:match("%w") then
						for i = 2, math.min(#filename, 5) do
							local second_char = filename:sub(i, i)
							if second_char:match("%w") then
								local alt_label = first_char .. second_char
								if not used_labels[alt_label] then
									labels[buffer.id] = alt_label
									used_labels[alt_label] = true
									found_label = true
									break
								end
							end
						end
					end
				end
			end

			-- Phase 4: Fallback to sequential letters
			if not found_label then
				local base_char = string.byte("a")
				for i = 0, 25 do
					local fallback_char = string.char(base_char + i)
					if not used_labels[fallback_char] then
						labels[buffer.id] = fallback_char
						used_labels[fallback_char] = true
						break
					end
				end
			end
		end
	end

	return labels
end

---Get a list of all loaded and listed buffers with filtering applied
---@return BufferInfo[] buffers List of buffer information
local function get_buffer_list()
	local buffers = {}
	local current_buf = vim.api.nvim_get_current_buf()
	local buffer_ids = {}

	-- Collect filtered buffers
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
				table.insert(buffer_ids, buf)
			end
		end
	end

	-- Check if we need to regenerate labels
	if has_buffer_list_changed(buffer_ids) then
		-- Generate new labels and cache them
		state.cached_labels = generate_unique_labels(buffers)
		state.cached_buffer_ids = buffer_ids
	end

	-- Assign cached labels to buffers
	for _, buffer in ipairs(buffers) do
		buffer.label = state.cached_labels[buffer.id] or "?"
	end

	return buffers
end

---Right-align lines within a given width by padding with spaces
---@param lines string[] Lines to align
---@param width number Target width for alignment
---@return string[] aligned_lines Right-aligned lines
local function right_align_lines(lines, width)
	local aligned_lines = {}
	for _, line in ipairs(lines) do
		local content_width = vim.fn.strwidth(line)
		local padding = width - content_width
		local aligned_line = string.rep(" ", math.max(0, padding)) .. line
		table.insert(aligned_lines, aligned_line)
	end
	return aligned_lines
end

---Calculate the required width based on current display mode and content
---@return number width The calculated width needed for the floating window
local function calculate_required_width()
	local buffers = get_buffer_list()
	local max_width = 1

	-- Calculate based on current display mode
	if state.jump_mode and config.jump and config.jump.show then
		-- Jump mode: calculate based on jump.show config
		local show_filename = vim.tbl_contains(config.jump.show, "filename")
		local show_space = vim.tbl_contains(config.jump.show, "space")
		local show_label = vim.tbl_contains(config.jump.show, "label")
		local show_stick = vim.tbl_contains(config.jump.show, "stick")

		local total_width = 0

		if show_stick then
			total_width = total_width
				+ math.max(vim.fn.strwidth(config.active_char), vim.fn.strwidth(config.inactive_char))
		end

		if show_filename then
			-- Find the longest filename among all buffers
			local max_filename_width = 0
			for _, buffer in ipairs(buffers) do
				local filename = vim.fn.fnamemodify(buffer.name, ":t")
				max_filename_width = math.max(max_filename_width, vim.fn.strwidth(filename))
			end
			total_width = total_width + max_filename_width
		end

		if show_space and (show_stick or show_filename or show_label) then
			-- Count spaces needed between elements
			local element_count = 0
			if show_stick then
				element_count = element_count + 1
			end
			if show_filename then
				element_count = element_count + 1
			end
			if show_label then
				element_count = element_count + 1
			end
			if element_count > 1 then
				total_width = total_width + (element_count - 1) -- spaces between elements
			end
		end

		if show_label then
			-- Find the longest label among all buffers
			local max_label_width = 0
			for _, buffer in ipairs(buffers) do
				max_label_width = math.max(max_label_width, vim.fn.strwidth(buffer.label))
			end
			total_width = total_width + max_label_width
		end

		max_width = total_width
	else
		-- Normal mode: check if labels should be shown
		local should_show_labels = (config.label and config.label.show == "always")

		-- Use the longer of active_char or inactive_char (display width)
		max_width = math.max(vim.fn.strwidth(config.active_char), vim.fn.strwidth(config.inactive_char))

		if should_show_labels then
			-- Find the longest label among all buffers
			local max_label_width = 0
			for _, buffer in ipairs(buffers) do
				max_label_width = math.max(max_label_width, vim.fn.strwidth(buffer.label))
			end
			max_width = max_width + 1 + max_label_width -- space + label
		end
	end

	return max_width
end

---@class WindowInfo
---@field buf number Buffer handle
---@field win number Window handle

---Create or update the floating window for buffer sticks
---@return WindowInfo window_info Information about the window and buffer
local function create_or_update_floating_window()
	local buffers = get_buffer_list()
	local height = math.max(#buffers, 1)
	local width = calculate_required_width()

	-- Position on the right side of the screen
	local col = vim.o.columns - width - config.offset.x
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

	-- Set winblend if specified
	if config.winblend then
		vim.api.nvim_win_set_option(state.win, "winblend", config.winblend)
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
	if not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_win_is_valid(state.win) then
		return
	end

	local buffers = get_buffer_list()
	local lines = {}
	local window_width = vim.api.nvim_win_get_width(state.win)

	for _, buffer in ipairs(buffers) do
		local line_content
		local should_show_char = false

		-- Determine if we should show characters based on config and state
		if config.label and config.label.show == "always" then
			should_show_char = true
		elseif config.label and config.label.show == "jump" and state.jump_mode then
			should_show_char = true
		end

		-- In jump mode, use jump.show configuration
		if state.jump_mode and config.jump and config.jump.show then
			local show_filename = vim.tbl_contains(config.jump.show, "filename")
			local show_space = vim.tbl_contains(config.jump.show, "space")
			local show_label = vim.tbl_contains(config.jump.show, "label")
			local show_stick = vim.tbl_contains(config.jump.show, "stick")

			local parts = {}

			if show_stick then
				if buffer.is_current then
					table.insert(parts, config.active_char)
				else
					table.insert(parts, config.inactive_char)
				end
			end

			if show_filename then
				local filename = vim.fn.fnamemodify(buffer.name, ":t")
				table.insert(parts, filename)
			end

			if show_label then
				table.insert(parts, buffer.label)
			end

			if show_space and #parts > 1 then
				line_content = table.concat(parts, " ")
			else
				line_content = table.concat(parts, "")
			end
		elseif should_show_char then
			-- Use generated unique label
			if buffer.is_current then
				line_content = config.active_char .. " " .. buffer.label
			else
				line_content = config.inactive_char .. " " .. buffer.label
			end
		else
			if buffer.is_current then
				line_content = config.active_char
			else
				line_content = config.inactive_char
			end
		end
		table.insert(lines, line_content)
	end

	-- Right-align content within the window
	local aligned_lines = right_align_lines(lines, window_width)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, aligned_lines)

	-- Set highlights
	for i, buffer in ipairs(buffers) do
		local line_idx = i - 1
		local line_content = aligned_lines[i]

		-- In jump mode, apply specific highlighting for different parts
		if state.jump_mode and config.jump and config.jump.show then
			local show_filename = vim.tbl_contains(config.jump.show, "filename")
			local show_space = vim.tbl_contains(config.jump.show, "space")
			local show_label = vim.tbl_contains(config.jump.show, "label")
			local show_stick = vim.tbl_contains(config.jump.show, "stick")

			local col_offset = 0
			-- Find where content starts (after right-alignment padding)
			local padding_match = line_content:match("^( *)")
			if padding_match then
				col_offset = #padding_match
			end

			-- Highlight stick part
			if show_stick then
				local stick_width = vim.fn.strwidth(buffer.is_current and config.active_char or config.inactive_char)
				local hl_group = buffer.is_current and "BufferSticksActive" or "BufferSticksInactive"
				vim.api.nvim_buf_add_highlight(state.buf, -1, hl_group, line_idx, col_offset, col_offset + stick_width)
				col_offset = col_offset + stick_width
			end

			-- Highlight filename part (use same color as stick for now)
			if show_filename then
				local filename = vim.fn.fnamemodify(buffer.name, ":t")
				local filename_width = vim.fn.strwidth(filename)
				local hl_group = buffer.is_current and "BufferSticksActive" or "BufferSticksInactive"
				vim.api.nvim_buf_add_highlight(
					state.buf,
					-1,
					hl_group,
					line_idx,
					col_offset,
					col_offset + filename_width
				)
				col_offset = col_offset + filename_width

				-- Add space after filename if needed
				if show_space and show_label then
					col_offset = col_offset + 1
				end
			elseif show_stick and show_space and show_label then
				-- Add space after stick if needed
				col_offset = col_offset + 1
			end

			-- Highlight label part with special label highlight
			if show_label then
				-- Find the label in the line content to get exact byte positions
				local content_start = line_content:sub(col_offset + 1) -- Content after right-align padding and previous elements
				local label_start_pos = content_start:find(vim.pesc(buffer.label))

				if label_start_pos then
					local byte_start = col_offset + label_start_pos - 1 -- Convert to absolute byte position
					local byte_end = byte_start + #buffer.label -- Byte length, not display width
					vim.api.nvim_buf_add_highlight(state.buf, -1, "BufferSticksLabel", line_idx, byte_start, byte_end)
				end
			end
		else
			-- Normal mode: highlight entire line
			if buffer.is_current then
				vim.api.nvim_buf_add_highlight(state.buf, -1, "BufferSticksActive", line_idx, 0, -1)
			else
				vim.api.nvim_buf_add_highlight(state.buf, -1, "BufferSticksInactive", line_idx, 0, -1)
			end
		end
	end
end

---Show the buffer sticks floating window
---Creates the window and renders the current buffer state
local function show()
	create_or_update_floating_window()
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

---Enter jump mode to navigate buffers by typing characters
local function jump()
	if not state.visible then
		show()
	end

	state.jump_mode = true
	state.jump_input = ""

	-- Refresh display to show characters (resize window for jump mode content)
	create_or_update_floating_window()
	render_buffers()

	-- Start input loop
	local function handle_input()
		local char = vim.fn.getchar()
		local char_str = type(char) == "number" and vim.fn.nr2char(char) or char

		-- Handle escape or ctrl-c to exit jump mode
		if char == 27 or char_str == "\x03" or char_str == "\27" then
			state.jump_mode = false
			state.jump_input = ""
			create_or_update_floating_window() -- Resize back to normal mode
			render_buffers()
			return
		end

		-- Handle backspace
		if char == 8 or char == 127 then
			if #state.jump_input > 0 then
				state.jump_input = state.jump_input:sub(1, -2)
				if #state.jump_input == 0 then
					state.jump_mode = false
					create_or_update_floating_window() -- Resize back to normal mode
					render_buffers()
					return
				end
				render_buffers()
				vim.defer_fn(handle_input, 0)
			else
				state.jump_mode = false
				create_or_update_floating_window() -- Resize back to normal mode
				render_buffers()
			end
			return
		end

		-- Handle regular character input
		if char_str:match("%w") then
			state.jump_input = state.jump_input .. char_str:lower()

			-- Find matching buffers
			local buffers = get_buffer_list()
			local matches = {}
			for _, buffer in ipairs(buffers) do
				-- Match against the beginning of the generated label
				local label_prefix = buffer.label:sub(1, #state.jump_input)
				if label_prefix == state.jump_input then
					table.insert(matches, buffer)
				end
			end

			-- If exactly one match, jump to it
			if #matches == 1 then
				vim.api.nvim_set_current_buf(matches[1].id)
				state.jump_mode = false
				state.jump_input = ""
				create_or_update_floating_window() -- Resize back to normal mode
				render_buffers()
				return
			elseif #matches == 0 then
				-- No matches, exit jump mode
				state.jump_mode = false
				state.jump_input = ""
				create_or_update_floating_window() -- Resize back to normal mode
				render_buffers()
				return
			end

			-- Multiple matches, continue with timeout
			render_buffers()
			vim.defer_fn(function()
				if state.jump_mode then
					handle_input()
				end
			end, vim.o.timeoutlen)
		else
			-- Invalid character, exit jump mode
			state.jump_mode = false
			state.jump_input = ""
			create_or_update_floating_window() -- Resize back to normal mode
			render_buffers()
		end
	end

	-- Start input handling with a small delay
	vim.defer_fn(handle_input, 10)
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
		-- Check if we should remove background colors (transparent mode only)
		local is_transparent = config.transparent

		if config.highlights.active.link then
			vim.api.nvim_set_hl(0, "BufferSticksActive", { link = config.highlights.active.link })
		else
			local active_hl = vim.deepcopy(config.highlights.active)
			if is_transparent then
				active_hl.bg = nil -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksActive", active_hl)
		end

		if config.highlights.inactive.link then
			vim.api.nvim_set_hl(0, "BufferSticksInactive", { link = config.highlights.inactive.link })
		else
			local inactive_hl = vim.deepcopy(config.highlights.inactive)
			if is_transparent then
				inactive_hl.bg = nil -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksInactive", inactive_hl)
		end

		if config.highlights.label then
			if config.highlights.label.link then
				vim.api.nvim_set_hl(0, "BufferSticksLabel", { link = config.highlights.label.link })
			else
				local label_hl = vim.deepcopy(config.highlights.label)
				if is_transparent then
					label_hl.bg = nil -- Remove background for transparency
				end
				vim.api.nvim_set_hl(0, "BufferSticksLabel", label_hl)
			end
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
			-- Invalidate label cache when buffer list changes
			state.cached_buffer_ids = {}
			state.cached_labels = {}

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
		jump = jump,
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
M.jump = jump

return M
