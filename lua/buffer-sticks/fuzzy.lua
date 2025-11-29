-- luacheck: globals vim
-- Fuzzy matching utilities (extracted from mini.fuzzy)
local M = {}

local function string_to_letters(s)
	return vim.tbl_map(vim.pesc, vim.split(s, ""))
end

local function score_positions(positions, cutoff)
	if positions == nil or #positions == 0 then
		return -1
	end
	local first, last = positions[1], positions[#positions]
	return cutoff * math.min(last - first + 1, cutoff) + math.min(first, cutoff)
end

local function find_best_positions(letters, candidate, cutoff)
	local n_candidate, n_letters = #candidate, #letters
	if n_letters == 0 then
		return {}
	end
	if n_candidate < n_letters then
		return nil
	end

	-- Search forward to find matching positions with left-most last letter match
	local pos_last = 0
	for let_i = 1, #letters do
		pos_last = candidate:find(letters[let_i], pos_last + 1)
		if not pos_last then
			break
		end
	end

	-- Candidate is matched only if word's last letter is found
	if not pos_last then
		return nil
	end

	-- If there is only one letter, it is already the best match
	if n_letters == 1 then
		return { pos_last }
	end

	-- Compute best match positions by iteratively checking all possible last
	-- letter matches. At end of each iteration best_pos_last holds best match
	-- for last letter among all previously checked such matches.
	local best_pos_last, best_width = pos_last, math.huge
	local rev_candidate = candidate:reverse()

	while pos_last do
		-- Simulate computing best match positions ending exactly at pos_last by
		-- going backwards from current last letter match.
		local rev_first = n_candidate - pos_last + 1
		for i = #letters - 1, 1, -1 do
			rev_first = rev_candidate:find(letters[i], rev_first + 1)
		end
		local first = n_candidate - rev_first + 1
		local width = math.min(pos_last - first + 1, cutoff)

		if width < best_width then
			best_pos_last, best_width = pos_last, width
		end

		-- Advance iteration
		pos_last = candidate:find(letters[n_letters], pos_last + 1)
	end

	-- Actually compute best matched positions from best last letter match
	local best_positions = { best_pos_last }
	local rev_pos = n_candidate - best_pos_last + 1
	for i = #letters - 1, 1, -1 do
		rev_pos = rev_candidate:find(letters[i], rev_pos + 1)
		table.insert(best_positions, 1, n_candidate - rev_pos + 1)
	end

	return best_positions
end

local function make_filter_indexes(word, candidate_array, cutoff)
	local res, letters = {}, string_to_letters(word)
	for i, cand in ipairs(candidate_array) do
		local positions = find_best_positions(letters, cand, cutoff)
		if positions ~= nil then
			table.insert(res, { index = i, score = score_positions(positions, cutoff) })
		end
	end
	return res
end

local function compare_filter_indexes(a, b)
	return a.score < b.score or (a.score == b.score and a.index < b.index)
end

local function filter_by_indexes(candidate_array, ids)
	local res, res_ids = {}, {}
	for _, id in pairs(ids) do
		table.insert(res, candidate_array[id.index])
		table.insert(res_ids, id.index)
	end
	return res, res_ids
end

---Filter and sort candidates by fuzzy match score
---@param word string The search word
---@param candidate_array string[] Array of candidates to filter
---@param cutoff? number Cutoff value for scoring (default: 100)
---@return string[] filtered Filtered candidates
---@return integer[] indices Original indices of filtered candidates
function M.filtersort(word, candidate_array, cutoff)
	cutoff = cutoff or 100
	-- Use 'smart case': case insensitive if word is lowercase
	local cand_array = word == word:lower() and vim.tbl_map(string.lower, candidate_array) or candidate_array
	local filter_ids = make_filter_indexes(word, cand_array, cutoff)
	table.sort(filter_ids, compare_filter_indexes)
	return filter_by_indexes(candidate_array, filter_ids)
end

return M
