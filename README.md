# buffer-sticks.nvim

A neovim plugin that displays a vertical indicator showing open buffers and doubles as a customizable buffer picker.

![Demo](assets/demo.png)

Jump mode for quick buffer navigation:

![Jump Demo](assets/jump-demo.png)

## Features

- Visual representation of open buffers
- Highlights for active, alternate, inactive, and modified buffers
- List mode for quick buffer navigation or closing by typing characters
- Filter mode with fuzzy search for finding buffers quickly
- Custom action functions for building buffer pickers
- Configurable positioning and appearance
- Transparent background support
- Persists highlight configuration across colorscheme changes

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ahkohd/buffer-sticks.nvim",
  config = function()
    require("buffer-sticks").setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "ahkohd/buffer-sticks.nvim",
  config = function()
    require("buffer-sticks").setup()
  end
}
```

### Quick Setup

```lua
return {
	"ahkohd/buffer-sticks.nvim",
	event = "VeryLazy",
	keys = {
		{
			"<leader>j",
			function()
				BufferSticks.jump()
			end,
			desc = "Jump to buffer",
		},
		{
			"<leader>q",
			function()
				BufferSticks.close()
			end,
			desc = "Close buffer",
		},
		{
			"<leader>p",
			function()
				BufferSticks.list({
					action = function(buffer, leave)
						print("Selected: " .. buffer.name)
						leave()
					end
				})
			end,
			desc = "Buffer picker",
		},
	},
	config = function()
		local sticks = require("buffer-sticks")
		sticks.setup({
			filter = { buftypes = { "terminal" } },
			highlights = {
                active = { link = "Statement" },
                alternate = { link = "StorageClass" },
                inactive = { link = "Whitespace" },
                active_modified = { link = "Constant" },
                alternate_modified = { link = "Constant" },
                inactive_modified = { link = "Constant" },
                label = { link = "Comment" },
                filter_selected = { link = "Statement" },
                filter_title = { link = "Comment" },
			},
		})
		sticks.show()
	end,
}
```

## Configuration

```lua
require("buffer-sticks").setup({
  offset = { x = 0, y = 0 },    -- Position offset (positive moves inward from right edge)
  padding = { top = 0, right = 1, bottom = 0, left = 1 }, -- Padding inside the float
  active_char = "──",           -- Character for active buffer
  inactive_char = " ─",         -- Character for inactive buffers
  alternate_char = " ─",        -- Character for alternate buffer
  active_modified_char = "──",  -- Character for active modified buffer (unsaved changes)
  inactive_modified_char = " ─", -- Character for inactive modified buffers (unsaved changes)
  alternate_modified_char = " ─", -- Character for alternate modified buffer (unsaved changes)
  transparent = true,           -- Remove background color (shows terminal/editor background)
  auto_hide = true,                -- Auto-hide when cursor is over float (default: true)
  label = { show = "list" },       -- Label display: "always", "list", or "never"
  list = {
    show = { "filename", "space", "label" }, -- List mode display options
    keys = {
      close_buffer = "<C-q>",      -- Key to close buffer in list mode
    },
    filter = {
      title = "➜ ",                -- Filter prompt title when input is not empty
      title_empty = "Filter",       -- Filter prompt title when input is empty
      active_indicator = "•",       -- Symbol for selected item in filter mode
      fuzzy_cutoff = 100,           -- Cutoff value for fuzzy matching algorithm (default: 100)
      keys = {
        enter = "/",                -- Key to enter filter mode
        confirm = "<CR>",           -- Key to confirm selection
        exit = "<Esc>",             -- Key to exit filter mode
        move_up = "<Up>",           -- Key to move selection up
        move_down = "<Down>",       -- Key to move selection down
      },
    },
  }
  -- winblend = 100,                    -- Window blend level (0-100, 0=opaque, 100=fully blended)
  -- filter = {
  --   filetypes = { "help", "qf" },    -- Exclude by filetype (also: "NvimTree", "neo-tree", "Trouble")
  --   buftypes = { "terminal" },       -- Exclude by buftype (also: "help", "quickfix", "nofile")
  --   names = { ".*%.git/.*", "^/tmp/.*" },  -- Exclude buffers matching lua patterns
  -- },
  highlights = {
    active = { fg = "#bbbbbb" },
    alternate = { fg = "#888888" },
    inactive = { fg = "#333333" },
    active_modified = { fg = "#ffffff" },
    alternate_modified = { fg = "#dddddd" },
    inactive_modified = { fg = "#999999" },
    label = { fg = "#aaaaaa", italic = true },
    filter_selected = { fg = "#bbbbbb", italic = true },
    filter_title = { fg = "#aaaaaa", italic = true },
  }
})
```

## Usage

```lua
-- Toggle visibility
BufferSticks.toggle()

-- Show
BufferSticks.show()

-- Hide
BufferSticks.hide()

-- Enter list mode to navigate buffers
BufferSticks.list({ action = "open" })

-- Enter list mode to close buffers
BufferSticks.list({ action = "close" })

-- Alias for jumping to buffers (same as list with action="open")
BufferSticks.jump()

-- Alias for closing buffers (same as list with action="close")
BufferSticks.close()

-- Custom action function (buffer picker)
BufferSticks.list({
  action = function(buffer, leave)
    -- Do something with buffer.id, buffer.name, etc.
    print("Selected buffer: " .. buffer.name)
    leave() -- Call this to leave list mode
  end
})
```

## List mode

List mode allows you to quickly navigate to or close buffers by typing their first character(s):

**Navigate to buffers:**
1. Call `BufferSticks.list({ action = "open" })` or `BufferSticks.jump()`
2. Type the first character of the buffer you want to jump to
3. If multiple buffers match, continue typing more characters
4. Press `/` (configurable) to enter filter mode for fuzzy search
5. Press `Ctrl-Q` (configurable) to close the current active buffer
6. Press `Esc` or `Ctrl-C` to cancel

**Close buffers:**
1. Call `BufferSticks.list({ action = "close" })` or `BufferSticks.close()`
2. Type the first character of the buffer you want to close
3. If multiple buffers match, continue typing more characters
4. Press `/` (configurable) to enter filter mode for fuzzy search
5. Press `Ctrl-Q` (configurable) to close the current active buffer
6. Press `Esc` or `Ctrl-C` to cancel

**Filter mode:**
1. While in list mode, press `/` (configurable) to enter filter mode
2. Type to fuzzy search through buffers in real-time
3. Use `Up`/`Down` arrows (configurable) to navigate filtered results
4. Press `Enter` to select the highlighted buffer
5. Press `Esc` to exit filter mode back to list mode

**Custom action function (buffer picker):**
1. Call `BufferSticks.list({ action = function(buffer, leave) ... end })`
2. Type the first character to select a buffer
3. If multiple buffers match, continue typing more characters
4. When a match is found, your function is called with:
   - `buffer`: The selected buffer info (with `id`, `name`, `label`, etc.)
   - `leave`: Function to call when you're done to exit list mode
5. You control when to exit by calling `leave()`

**Label Display Options:**
- `label = { show = "always" }` - Always show buffer name labels
- `label = { show = "list" }` - Only show labels when in list mode (default)
- `label = { show = "never" }` - Never show labels

**List Mode Display Options:**
- **Default**: `list = { show = { "filename", "space", "label" } }`

**Available elements:**
- `"filename"` - Full filename
- `"space"` - Spaces between elements
- `"label"` - Unique character
- `"stick"` - Active/inactive character

### Highlight Options

You can use hex colors:

```lua
highlights = {
  active = { fg = "#bbbbbb" },
  alternate = { fg = "#888888" },
  inactive = { fg = "#333333" },
  active_modified = { fg = "#ffffff" },
  alternate_modified = { fg = "#dddddd" },
  inactive_modified = { fg = "#999999" },
  label = { fg = "#aaaaaa", italic = true },
  filter_selected = { fg = "#bbbbbb", italic = true },
  filter_title = { fg = "#aaaaaa", italic = true },
}
```

Or link to existing highlight groups:

```lua
highlights = {
  active = { link = "Statement" },
  alternate = { link = "StorageClass" },
  inactive = { link = "Whitespace" },
  active_modified = { link = "Constant" },
  alternate_modified = { link = "Constant" },
  inactive_modified = { link = "Constant" },
  label = { link = "Comment" },
  filter_selected = { link = "Statement" },
  filter_title = { link = "Comment" },
}
```

## API

- `setup(opts)` - Initialize the plugin with configuration
- `toggle()` - Toggle buffer sticks visibility
- `show()` - Show buffer sticks
- `hide()` - Hide buffer sticks
- `list(opts)` - Enter list mode with action ("open", "close", or custom function)
- `jump()` - Enter list mode for quick buffer navigation (alias for `list({ action = "open" })`)
- `close()` - Enter list mode to close buffers (alias for `list({ action = "close" })`)
