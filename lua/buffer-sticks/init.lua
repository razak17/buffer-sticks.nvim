-- luacheck: globals vim

---@class BufferSticks
---@field setup function Setup the buffer sticks plugin
---@field toggle function Toggle the visibility of buffer sticks
---@field show function Show the buffer sticks
---@field hide function Hide the buffer sticks
local M = {}

---@class BufferSticksState
---@field win integer Window handle for the floating window
---@field buf integer Buffer handle for the display buffer
---@field visible boolean Whether the buffer sticks are currently visible
---@field cached_buffer_ids integer[] Cached list of buffer IDs for label generation
---@field cached_labels table<integer, string> Map of buffer ID to generated label
local state = {
	win = -1,
	buf = -1,
	visible = false,
	jump_mode = false,
	jump_input = "",
	cached_buffer_ids = {},
	cached_labels = {},
	auto_hidden = false,
	win_pos = { col = 0, row = 0, width = 0, height = 0 },
}

---@alias BufferSticksHighlights vim.api.keyset.highlight

---@class BufferSticksOffset
---@field x integer Horizontal offset from default position
---@field y integer Vertical offset from default position

---@class BufferSticksPadding
---@field top integer Top padding inside the window
---@field right integer Right padding inside the window
---@field bottom integer Bottom padding inside the window
---@field left integer Left padding inside the window

---@class BufferSticksJump
---@field show string[] What to show in jump mode: "filename", "space", "label", "stick"

---@class BufferSticksLabel
---@field show "always"|"jump"|"never" When to show buffer name characters

---@class BufferSticksFilter
---@field filetypes? string[] List of filetypes to exclude from buffer sticks
---@field buftypes? string[] List of buftypes to exclude from buffer sticks (e.g., "terminal", "help", "quickfix")
---@field names? string[] List of buffer name patterns to exclude (supports lua patterns)

---@class BufferSticksConfig
---@field offset BufferSticksOffset Position offset for fine-tuning
---@field padding BufferSticksPadding Padding inside the window
---@field active_char string Character to display for the active buffer
---@field inactive_char string Character to display for inactive buffers
---@field alternate_char string Character to display for the alternate buffer
---@field alternate_modified_char string Character to display for the alternate modified buffer
---@field active_modified_char string Character to display for the active modified buffer
---@field inactive_modified_char string Character to display for inactive modified buffers
---@field transparent boolean Whether the background should be transparent
---@field winblend? number Window blend level (0-100)
---@field auto_hide boolean Auto-hide when cursor is over float
---@field label? BufferSticksLabel Label display configuration
---@field jump? BufferSticksJump Jump mode configuration
---@field filter? BufferSticksFilter Filter configuration for excluding buffers
---@field highlights table<string, BufferSticksHighlights> Highlight groups for active/inactive/label states
local config = {
	offset = { x = 0, y = 0 },
	padding = { top = 0, right = 1, bottom = 0, left = 1 },
	active_char = "──",
	inactive_char = " ─",
	alternate_char = " ─",
	active_modified_char = "──",
	inactive_modified_char = " ─",
	alternate_modified_char = "*─",
	transparent = true,
	auto_hide = true,
	label = { show = "jump" },
	jump = { show = { "filename", "space", "label" } },
	highlights = {
		active = { fg = "#bbbbbb" },
		alternate = { fg = "#888888" },
		inactive = { fg = "#333333" },
		active_modified = { fg = "#ffffff" },
		alternate_modified = { fg = "#dddddd" },
		inactive_modified = { fg = "#999999" },
		label = { fg = "#aaaaaa", italic = true },
	},
}

---@class BufferInfo
---@field id integer Buffer ID
---@field name string Buffer name/path
---@field is_current boolean Whether this is the currently active buffer
---@field is_alternate boolean Whether this is the alternate buffer
---@field is_modified boolean Whether this buffer has unsaved changes
---@field label string Generated unique label for this buffer

---Check if buffer list has changed compared to cached version
---@param current_buffer_ids integer[] Current list of buffer IDs
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
	local collision_groups = {}

	-- Phase 1: Extract filenames and group by first word character (skip leading symbols)
	for _, buffer in ipairs(buffers) do
		local filename = vim.fn.fnamemodify(buffer.name, ":t")
		if filename == "" then
			filename = "?"
		end
		filename_map[buffer.id] = filename:lower()

		-- Find first word character (skip leading symbols like . _ -)
		local first_word_char = filename:match("%w")
		if first_word_char then
			first_word_char = first_word_char:lower()
			if not collision_groups[first_word_char] then
				collision_groups[first_word_char] = {}
			end
			table.insert(collision_groups[first_word_char], buffer)
		end
		-- Buffers with no word characters will be handled in Phase 3
	end

	-- Phase 2: Assign labels based on collision detection
	for first_char, group in pairs(collision_groups) do
		if #group == 1 then
			-- No collision: use single character
			local buffer = group[1]
			labels[buffer.id] = first_char
			used_labels[first_char] = true
		else
			-- Collision detected: ALL buffers in this group get two-character labels
			for _, buffer in ipairs(group) do
				local filename = filename_map[buffer.id]
				local found_label = false

				-- Try first two characters
				if #filename >= 2 then
					local two_char = filename:sub(1, 2)
					if two_char:match("^%w%w$") and not used_labels[two_char] then
						labels[buffer.id] = two_char
						used_labels[two_char] = true
						found_label = true
					end
				end

				-- If first two chars didn't work, try first char + other chars
				if not found_label and first_char:match("%w") then
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

				-- Fallback: use sequential two-character combinations
				if not found_label then
					local base_char = string.byte("a")
					for i = 0, 25 do
						for j = 0, 25 do
							local fallback_label = string.char(base_char + i) .. string.char(base_char + j)
							if not used_labels[fallback_label] then
								labels[buffer.id] = fallback_label
								used_labels[fallback_label] = true
								found_label = true
								break
							end
						end
						if found_label then
							break
						end
					end
				end
			end
		end
	end

	-- Phase 3: Handle buffers with no word characters (use numeric labels)
	for _, buffer in ipairs(buffers) do
		if not labels[buffer.id] then
			-- Use numeric labels for files with no word characters
			-- This prevents collision with letter-based labels
			for i = 0, 9 do
				local numeric_label = tostring(i)
				if not used_labels[numeric_label] then
					labels[buffer.id] = numeric_label
					used_labels[numeric_label] = true
					break
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
	local alternate_buf = vim.fn.bufnr("#")
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

			-- Filter by buftype
			if should_include and config.filter and config.filter.buftypes then
				local buf_buftype = vim.bo[buf].buftype
				for _, bt in ipairs(config.filter.buftypes) do
					if buf_buftype == bt then
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
					is_modified = vim.bo[buf].modified,
					is_alternate = buf == alternate_buf,
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
		local aligned_line = string.rep(" ", math.max(0, config.padding.left + padding))
			.. line
			.. string.rep(" ", math.max(0, config.padding.right))
		table.insert(aligned_lines, aligned_line)
	end
	return aligned_lines
end

---Apply vertical padding (top and bottom) to lines
---@param lines string[] Lines to add vertical padding to
---@return string[] padded_lines Lines with top and bottom padding applied
local function vertical_align_lines(lines)
	local padded_lines = {}

	-- Add top padding (empty lines)
	for _ = 1, config.padding.top do
		table.insert(padded_lines, lines[1] and string.rep(" ", vim.fn.strwidth(lines[1])) or "")
	end

	-- Add original content lines
	for _, line in ipairs(lines) do
		table.insert(padded_lines, line)
	end

	-- Add bottom padding (empty lines)
	for _ = 1, config.padding.bottom do
		table.insert(padded_lines, lines[1] and string.rep(" ", vim.fn.strwidth(lines[1])) or "")
	end

	return padded_lines
end

---Get display paths for buffers with recursive expansion for duplicates
---@param buffers BufferInfo[] List of buffers
---@return table<integer, string> Map of buffer.id to display path
local function get_display_paths(buffers)
	local display_paths = {}
	local path_components = {}

	-- Initialize with full paths split into components
	for _, buffer in ipairs(buffers) do
		local full_path = buffer.name
		local components = {}

		-- Split path into components (reverse order, filename first)
		local filename = vim.fn.fnamemodify(full_path, ":t")
		if filename ~= "" then
			table.insert(components, filename)

			-- Get parent directories
			local parent = vim.fn.fnamemodify(full_path, ":h")
			while parent ~= "" and parent ~= "." and parent ~= "/" do
				local dir = vim.fn.fnamemodify(parent, ":t")
				if dir ~= "" then
					table.insert(components, dir)
				end
				parent = vim.fn.fnamemodify(parent, ":h")
			end
		end

		path_components[buffer.id] = components
		-- Start with just the filename
		display_paths[buffer.id] = components[1] or "?"
	end

	-- Recursively expand duplicates
	local max_iterations = 10 -- Safety limit
	for _ = 1, max_iterations do
		-- Group by current display path
		local path_groups = {}
		for buffer_id, display_path in pairs(display_paths) do
			if not path_groups[display_path] then
				path_groups[display_path] = {}
			end
			table.insert(path_groups[display_path], buffer_id)
		end

		-- Check if we still have duplicates
		local has_duplicates = false
		for _, group in pairs(path_groups) do
			if #group > 1 then
				has_duplicates = true
				break
			end
		end

		if not has_duplicates then
			break
		end

		-- Expand duplicates by one level
		for display_path, buffer_ids in pairs(path_groups) do
			if #buffer_ids > 1 then
				-- This path is duplicated, expand all buffers in this group
				for _, buffer_id in ipairs(buffer_ids) do
					local components = path_components[buffer_id]
					local current_depth = 0

					-- Count current depth
					for i = 1, #components do
						if display_paths[buffer_id]:find(components[i], 1, true) then
							current_depth = math.max(current_depth, i)
						end
					end

					-- Add one more parent level if available
					if current_depth < #components then
						local new_depth = current_depth + 1
						local path_parts = {}
						for i = new_depth, 1, -1 do
							table.insert(path_parts, components[i])
						end
						display_paths[buffer_id] = table.concat(path_parts, "/")
					end
				end
			end
		end
	end

	return display_paths
end

---Calculate the required width based on current display mode and content
---@return number width The calculated width needed for the floating window
local function calculate_required_width()
	local buffers = get_buffer_list()
	local max_width = 1

	-- Calculate based on current display mode
	if state.jump_mode and config.jump and config.jump.show then
		-- Jump mode: calculate based on jump.show config
		local show_filename = vim.list_contains(config.jump.show, "filename")
		local show_space = vim.list_contains(config.jump.show, "space")
		local show_label = vim.list_contains(config.jump.show, "label")
		local show_stick = vim.list_contains(config.jump.show, "stick")

		local total_width = 0

		if show_stick then
			total_width = total_width
				+ math.max(
					vim.fn.strwidth(config.active_char),
					vim.fn.strwidth(config.inactive_char),
					vim.fn.strwidth(config.alternate_char),
					vim.fn.strwidth(config.alternate_modified_char),
					vim.fn.strwidth(config.active_modified_char),
					vim.fn.strwidth(config.inactive_modified_char)
				)
		end

		if show_filename then
			-- Get recursively-expanded display paths
			local display_paths = get_display_paths(buffers)

			-- Find the longest display path among all buffers
			local max_filename_width = 0
			for _, buffer in ipairs(buffers) do
				local display_path = display_paths[buffer.id] or vim.fn.fnamemodify(buffer.name, ":t")
				max_filename_width = math.max(max_filename_width, vim.fn.strwidth(display_path))
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

		-- Use the longest of all character options (display width)
		max_width = math.max(
			vim.fn.strwidth(config.active_char),
			vim.fn.strwidth(config.inactive_char),
			vim.fn.strwidth(config.alternate_char),
			vim.fn.strwidth(config.alternate_modified_char),
			vim.fn.strwidth(config.active_modified_char),
			vim.fn.strwidth(config.inactive_modified_char)
		)

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

---Check if cursor position is within the floating window bounds
---@return boolean collision True if cursor is within the window area
local function check_cursor_collision()
	-- If auto_hide is disabled, no collision detection needed
	if not config.auto_hide then
		return false
	end

	-- If we don't have valid window position data, no collision
	if state.win_pos.width == 0 or state.win_pos.height == 0 then
		return false
	end

	-- Get screen cursor position
	-- Convert to 0-based like window coordinates
	local cursor_row = vim.fn.screenrow() - 1
	local cursor_col = vim.fn.screencol() - 1

	-- Use a small consistent offset for collision detection
	local offset = 1

	-- Check if cursor is within floating window bounds (regardless of window validity)
	return cursor_col >= state.win_pos.col - offset
		and cursor_col < state.win_pos.col + state.win_pos.width + offset
		and cursor_row >= state.win_pos.row - offset
		and cursor_row < state.win_pos.row + state.win_pos.height + offset
end

---Handle cursor movement for auto-hide behavior
local function handle_cursor_move()
	-- Only handle auto-hide if auto_hide is enabled and we're visible (or auto-hidden)
	if not config.auto_hide or state.jump_mode then
		return
	end

	-- If we're not visible and not auto-hidden, nothing to do
	if not state.visible and not state.auto_hidden then
		return
	end

	local collision = check_cursor_collision()
	local cursor_row = vim.fn.screenrow() - 1
	local cursor_col = vim.fn.screencol() - 1

	if collision and state.visible and not state.auto_hidden then
		-- Cursor entered float area, hide it immediately
		state.auto_hidden = true
		if vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_hide(state.win)
		end
	elseif not collision and state.auto_hidden then
		-- Cursor left float area, show it immediately
		state.auto_hidden = false
		M.show()
	end
end

---Create or update the floating window for buffer sticks
---@return WindowInfo window_info Information about the window and buffer
local function create_or_update_floating_window()
	local buffers = get_buffer_list()
	local content_height = math.max(#buffers, 1)
	local content_width = calculate_required_width()

	-- Add padding to window dimensions
	local height = content_height + config.padding.top + config.padding.bottom
	local width = content_width + config.padding.left + config.padding.right

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

	-- Store window position for collision detection
	state.win_pos = { col = col, row = row, width = width, height = height }

	---@type vim.api.keyset.option
	local win_opts = { win = state.win }

	-- Set winblend if specified
	if config.winblend then
		vim.api.nvim_set_option_value("winblend", config.winblend, win_opts)
	end

	-- Set window background based on transparency
	if not config.winblend and not config.transparent then
		vim.api.nvim_set_option_value("winhl", "Normal:BufferSticksBackground", win_opts)
	else
		vim.api.nvim_set_option_value("winhl", "Normal:NONE", win_opts)
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

	-- Get display paths with recursive expansion for duplicates
	local display_paths = get_display_paths(buffers)

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
			local show_filename = vim.list_contains(config.jump.show, "filename")
			local show_space = vim.list_contains(config.jump.show, "space")
			local show_label = vim.list_contains(config.jump.show, "label")
			local show_stick = vim.list_contains(config.jump.show, "stick")

			local parts = {}

			if show_stick then
				if buffer.is_modified then
					if buffer.is_current then
						table.insert(parts, config.active_modified_char)
					elseif buffer.is_alternate then
						table.insert(parts, config.alternate_modified_char)
					else
						table.insert(parts, config.inactive_modified_char)
					end
				else
					if buffer.is_current then
						table.insert(parts, config.active_char)
					elseif buffer.is_alternate then
						table.insert(parts, config.alternate_char)
					else
						table.insert(parts, config.inactive_char)
					end
				end
			end

			if show_filename then
				-- Use the recursively-expanded display path
				local filename = display_paths[buffer.id] or vim.fn.fnamemodify(buffer.name, ":t")
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
			if buffer.is_modified then
				if buffer.is_current then
					line_content = config.active_modified_char .. " " .. buffer.label
				elseif buffer.is_alternate then
					line_content = config.alternate_modified_char .. " " .. buffer.label
				else
					line_content = config.inactive_modified_char .. " " .. buffer.label
				end
			else
				if buffer.is_current then
					line_content = config.active_char .. " " .. buffer.label
				elseif buffer.is_alternate then
					line_content = config.alternate_char .. " " .. buffer.label
				else
					line_content = config.inactive_char .. " " .. buffer.label
				end
			end
		else
			if buffer.is_modified then
				if buffer.is_current then
					line_content = config.active_modified_char
				elseif buffer.is_alternate then
					line_content = config.alternate_modified_char
				else
					line_content = config.inactive_modified_char
				end
			else
				if buffer.is_current then
					line_content = config.active_char
				elseif buffer.is_alternate then
					line_content = config.alternate_char
				else
					line_content = config.inactive_char
				end
			end
		end
		table.insert(lines, line_content)
	end

	-- Right-align content within the window
	window_width = calculate_required_width()
	local aligned_lines = right_align_lines(lines, window_width)

	-- Apply vertical padding
	local final_lines = vertical_align_lines(aligned_lines)

	local ns_id = vim.api.nvim_create_namespace("BufferSticks")
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, final_lines)

	-- Set highlights
	for i, buffer in ipairs(buffers) do
		local line_idx = i - 1 + config.padding.top -- Account for top padding
		local line_content = final_lines[i + config.padding.top] -- Access content from final padded lines

		-- In jump mode, apply specific highlighting for different parts
		if state.jump_mode and config.jump and config.jump.show then
			local show_filename = vim.list_contains(config.jump.show, "filename")
			local show_space = vim.list_contains(config.jump.show, "space")
			local show_label = vim.list_contains(config.jump.show, "label")
			local show_stick = vim.list_contains(config.jump.show, "stick")

			local col_offset = 0
			-- Find where content starts (after right-alignment padding)
			local padding_match = line_content:match("^( *)")
			if padding_match then
				col_offset = #padding_match
			end

			-- Highlight stick part
			if show_stick then
				local stick_char
				local hl_group
				if buffer.is_modified then
					if buffer.is_current then
						stick_char = config.active_modified_char
						hl_group = "BufferSticksActiveModified"
					elseif buffer.is_alternate then
						stick_char = config.alternate_modified_char
						hl_group = "BufferSticksAlternateModified"
					else
						stick_char = config.inactive_modified_char
						hl_group = "BufferSticksInactiveModified"
					end
				else
					if buffer.is_current then
						stick_char = config.active_char
						hl_group = "BufferSticksActive"
					elseif buffer.is_alternate then
						stick_char = config.alternate_char
						hl_group = "BufferSticksAlternate"
					else
						stick_char = config.inactive_char
						hl_group = "BufferSticksInactive"
					end
				end
				local stick_width = vim.fn.strwidth(stick_char)
				vim.hl.range(
					state.buf,
					ns_id,
					hl_group,
					{ line_idx, col_offset },
					{ line_idx, col_offset + stick_width }
				)
				col_offset = col_offset + stick_width
			end

			-- Highlight filename part (use same color as stick for now)
			if show_filename then
				-- Use the recursively-expanded display path
				local filename = display_paths[buffer.id] or vim.fn.fnamemodify(buffer.name, ":t")
				local filename_width = vim.fn.strwidth(filename)
				local hl_group
				if buffer.is_modified then
					if buffer.is_current then
						hl_group = "BufferSticksActiveModified"
					elseif buffer.is_alternate then
						hl_group = "BufferSticksAlternateModified"
					else
						hl_group = "BufferSticksInactiveModified"
					end
				else
					if buffer.is_current then
						hl_group = "BufferSticksActive"
					elseif buffer.is_alternate then
						hl_group = "BufferSticksAlternate"
					else
						hl_group = "BufferSticksInactive"
					end
				end
				vim.hl.range(
					state.buf,
					ns_id,
					hl_group,
					{ line_idx, col_offset },
					{ line_idx, col_offset + filename_width }
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
					vim.hl.range(
						state.buf,
						ns_id,
						"BufferSticksLabel",
						{ line_idx, byte_start },
						{ line_idx, byte_end }
					)
				end
			end
		else
			-- Normal mode: highlight entire line
			local hl_group
			if buffer.is_modified then
				if buffer.is_current then
					hl_group = "BufferSticksActiveModified"
				elseif buffer.is_alternate then
					hl_group = "BufferSticksAlternateModified"
				else
					hl_group = "BufferSticksInactiveModified"
				end
			else
				if buffer.is_current then
					hl_group = "BufferSticksActive"
				elseif buffer.is_alternate then
					hl_group = "BufferSticksAlternate"
				else
					hl_group = "BufferSticksInactive"
				end
			end
			vim.hl.range(state.buf, ns_id, hl_group, { line_idx, 0 }, { line_idx, -1 })
		end
	end
end

---Show the buffer sticks floating window
---Creates the window and renders the current buffer state
function M.show()
	create_or_update_floating_window()
	render_buffers()
	state.visible = true
	state.auto_hidden = false -- Reset auto-hide state when manually shown
end

---Hide the buffer sticks floating window
---Closes the window and updates the visibility state
function M.hide()
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
		state.win = -1
	end
	state.visible = false
	state.auto_hidden = false -- Reset auto-hide state when manually hidden
end

---Enter jump mode to navigate buffers by typing characters
function M.jump()
	if not state.visible then
		M.show()
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

			-- Multiple matches, continue immediately
			render_buffers()
			vim.schedule(handle_input)
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
function M.toggle()
	if state.visible then
		M.hide()
	else
		M.show()
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

		if config.highlights.alternate.link then
			vim.api.nvim_set_hl(0, "BufferSticksAlternate", { link = config.highlights.alternate.link })
		else
			local alternate_hl = vim.deepcopy(config.highlights.alternate)
			if is_transparent then
				alternate_hl.bg = nil -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksAlternate", alternate_hl)
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

		if config.highlights.active_modified then
			if config.highlights.active_modified.link then
				vim.api.nvim_set_hl(0, "BufferSticksActiveModified", { link = config.highlights.active_modified.link })
			else
				local active_modified_hl = vim.deepcopy(config.highlights.active_modified)
				if is_transparent then
					active_modified_hl.bg = nil -- Remove background for transparency
				end
				vim.api.nvim_set_hl(0, "BufferSticksActiveModified", active_modified_hl)
			end
		end

		if config.highlights.alternate_modified then
			if config.highlights.alternate_modified.link then
				vim.api.nvim_set_hl(
					0,
					"BufferSticksAlternateModified",
					{ link = config.highlights.alternate_modified.link }
				)
			else
				local alternate_modified_hl = vim.deepcopy(config.highlights.alternate_modified)
				if is_transparent then
					alternate_modified_hl.bg = nil -- Remove background for transparency
				end
				vim.api.nvim_set_hl(0, "BufferSticksAlternateModified", alternate_modified_hl)
			end
		end

		if config.highlights.inactive_modified then
			if config.highlights.inactive_modified.link then
				vim.api.nvim_set_hl(
					0,
					"BufferSticksInactiveModified",
					{ link = config.highlights.inactive_modified.link }
				)
			else
				local inactive_modified_hl = vim.deepcopy(config.highlights.inactive_modified)
				if is_transparent then
					inactive_modified_hl.bg = nil -- Remove background for transparency
				end
				vim.api.nvim_set_hl(0, "BufferSticksInactiveModified", inactive_modified_hl)
			end
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
				vim.schedule(M.show) -- Refresh the display
			end
		end,
	})

	-- Update display when buffer modified status changes
	vim.api.nvim_create_autocmd({ "BufModifiedSet", "TextChanged", "TextChangedI", "BufWritePost" }, {
		group = augroup,
		callback = function()
			if state.visible then
				-- Just re-render, don't need to recreate window
				vim.schedule(render_buffers)
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
				vim.schedule(M.show) -- Refresh the display and position
			end
		end,
	})

	-- Handle cursor movement for auto-hide behavior
	vim.api.nvim_create_autocmd({
		"CursorMoved",
		"CursorMovedI",
		"CursorHold",
		"CursorHoldI",
		"WinScrolled",
		"ModeChanged",
		"SafeState",
	}, {
		group = augroup,
		callback = function()
			if config.auto_hide then
				handle_cursor_move()
			end
		end,
	})

	-- Store globally for access
	_G.BufferSticks = {
		toggle = M.toggle,
		show = M.show,
		hide = M.hide,
		jump = M.jump,
	}
end

return M
-- vim:noet:ts=4:sts=4:sw=4:
