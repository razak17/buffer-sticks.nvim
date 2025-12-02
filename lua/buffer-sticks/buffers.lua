-- luacheck: globals vim
-- Buffer list and label management

local config = require("buffer-sticks.config")
local state = require("buffer-sticks.state")

local M = {}

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
---@return table<integer, string> labels Map of buffer ID to label
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
	end

	-- Phase 2: Assign labels based on collision detection
	for first_char, group in pairs(collision_groups) do
		if #group == 1 then
			local buffer = group[1]
			labels[buffer.id] = first_char
			used_labels[first_char] = true
		else
			for _, buffer in ipairs(group) do
				local filename = filename_map[buffer.id]
				local found_label = false

				if #filename >= 2 then
					local two_char = filename:sub(1, 2)
					if two_char:match("^%w%w$") and not used_labels[two_char] then
						labels[buffer.id] = two_char
						used_labels[two_char] = true
						found_label = true
					end
				end

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

---Get a list of all listed buffers with filtering applied
---@return BufferInfo[] buffers List of buffer information
function M.get_buffer_list()
	local buffers = {}
	local current_buf = vim.api.nvim_get_current_buf()
	local alternate_buf = vim.fn.bufnr("#")
	local buffer_ids = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			local buf_filetype = vim.bo[buf].filetype
			local should_include = true

			if config.filter and config.filter.filetypes then
				for _, ft in ipairs(config.filter.filetypes) do
					if buf_filetype == ft then
						should_include = false
						break
					end
				end
			end

			if should_include and config.filter and config.filter.buftypes then
				local buf_buftype = vim.bo[buf].buftype
				for _, bt in ipairs(config.filter.buftypes) do
					if buf_buftype == bt then
						should_include = false
						break
					end
					-- Fallback: detect terminal by name pattern (for unloaded session-restored buffers)
					if bt == "terminal" and buf_name:match("^term://") then
						should_include = false
						break
					end
				end
			end

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

	if has_buffer_list_changed(buffer_ids) then
		state.cached_labels = generate_unique_labels(buffers)
		state.cached_buffer_ids = buffer_ids
	end

	for _, buffer in ipairs(buffers) do
		buffer.label = state.cached_labels[buffer.id] or "?"
	end

	return buffers
end

---Get display paths for buffers with recursive expansion for duplicates
---@param buffers BufferInfo[] List of buffers
---@return table<integer, string> Map of buffer.id to display path
function M.get_display_paths(buffers)
	local display_paths = {}
	local path_components = {}

	for _, buffer in ipairs(buffers) do
		local full_path = buffer.name
		local components = {}

		local filename = vim.fn.fnamemodify(full_path, ":t")
		if filename ~= "" then
			table.insert(components, filename)

			local parent = vim.fn.fnamemodify(full_path, ":h")
			while parent ~= "" and parent ~= "." do
				local new_parent = vim.fn.fnamemodify(parent, ":h")
				if new_parent == parent then
					break
				end

				local dir = vim.fn.fnamemodify(parent, ":t")
				if dir ~= "" then
					table.insert(components, dir)
				end
				parent = new_parent
			end
		end

		path_components[buffer.id] = components
		display_paths[buffer.id] = components[1] or "?"
	end

	local max_iterations = 10
	for _ = 1, max_iterations do
		local path_groups = {}
		for buffer_id, display_path in pairs(display_paths) do
			if not path_groups[display_path] then
				path_groups[display_path] = {}
			end
			table.insert(path_groups[display_path], buffer_id)
		end

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

		for _, buffer_ids in pairs(path_groups) do
			if #buffer_ids > 1 then
				for _, buffer_id in ipairs(buffer_ids) do
					local components = path_components[buffer_id]
					local current_depth = 0

					for i = 1, #components do
						if display_paths[buffer_id]:find(components[i], 1, true) then
							current_depth = math.max(current_depth, i)
						end
					end

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

---Check if any buffer has a two-character label
---@param buffers BufferInfo[] List of buffers to check
---@return boolean has_two_char_label True if any buffer has a two-character label
function M.has_two_char_label(buffers)
	for _, buffer in ipairs(buffers) do
		if #buffer.label == 2 then
			return true
		end
	end
	return false
end

return M
