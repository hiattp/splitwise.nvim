# splitwise.nvim

Smart split navigation for Neovim with optional auto-creation and resizing.

Splitwise lets you move between windows using a single set of directional keys. When you hit an edge, it can (1) create a new split in your direction within configurable limits, (2) resize the current window toward that edge, or (optionally) (3) wrap focus to the opposite side.

## Demo

https://github.com/user-attachments/assets/95dce3f0-2261-448b-90d8-62b64bb8aa39

## Features

- Directional navigation that feels natural: `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>`
- Auto-create splits when moving into an edge
  - Columns limited per current row (`max_columns`)
  - Rows limited per current column (`max_rows`)
  - New split is created on the side you moved toward and focus moves into it
- Resize at edges when creation is disallowed (or max reached)
- **Auto-resize focused windows** to golden ratio (~65%) on navigation
  - Resizes in the same plane of movement (horizontal for left/right, vertical for up/down)
  - Only resizes if it makes the focused window larger, never smaller
  - Configurable ratio and can be disabled
- Optional wrap-around navigation
- Ignores floating windows and configurable filetypes/buftypes

## Requirements

- Neovim 0.8+ (uses `winlayout()` and modern APIs)

## Known Conflicts

Note that `<C-l>` is mapped to "refresh" in Neovim by default. If you want to use this
plugin but also need to refresh regularly, map that to something else or set your own
"right" movement for this plugin.

#### Other plugins with conflicting keymaps:

- [Oil](https://github.com/stevearc/oil.nvim): In the Oil buffer `<C-h>` and `<C-l>` are
  used for select and refresh respectively. Personally I don't use those so I set them
  to false in the keymaps options in the Oil config.

## Installation

### lazy.nvim

```lua
{
  "hiattp/splitwise.nvim",
  opts = {
    max_columns = 2, -- Default
    max_rows = 2, -- Default
  },
}
```

### packer.nvim

```lua
use {
  "hiattp/splitwise.nvim",
  config = function()
    require("splitwise").setup({})
  end,
}
```

### vim-plug

```vim
Plug 'hiattp/splitwise.nvim'
```

Then in Lua config:

```lua
require("splitwise").setup({})
```

## Quick start

After installation, the plugin registers default keymaps in normal mode:

- `<C-h>`: move left
- `<C-j>`: move down
- `<C-k>`: move up
- `<C-l>`: move right

Hit an edge and splitwise.nvim will either create a split in that direction (within limits), resize toward that edge, or wrap focus (if enabled).

## Configuration

All options with defaults:

```lua
require("splitwise").setup({
  max_columns = 2,                 -- per current row
  max_rows = 2,                    -- per current column
  resize_step_cols = 5,            -- :vertical resize +N at left/right edge
  resize_step_rows = 3,            -- :resize +N at top/bottom edge
  create_default_keymaps = true,   -- install <C-h/j/k/l>
  wrap_navigation = false,         -- wrap to opposite edge when blocked
  ignore_filetypes = { "help", "qf" },
  ignore_buftypes = { "nofile", "terminal", "prompt" },
  new_split_opens_blank_buffer = false, -- duplicate current buffer by default
  ignore_winfixwidth = false,      -- allow resize even if window has 'winfixwidth'
  auto_resize_enabled = true,      -- automatically resize focused window
  auto_resize_ratio = 0.65,        -- target ratio for focused window (~65% golden ratio)
})
```

### Notes on behavior

- New splits are always created on the side you travel toward:
  - Right: `rightbelow vsplit`
  - Left: `leftabove vsplit`
  - Up: `aboveleft split`
  - Down: `belowright split`
- After auto-creating, focus moves into the new window.
- **Auto-resize behavior** (when `auto_resize_enabled = true`):
  - When navigating to a window, it automatically resizes to the configured ratio (default 65%)
  - Resizing only happens in the movement plane: horizontal movement triggers horizontal resize, vertical movement triggers vertical resize
  - Only resizes if it would make the focused window larger, never smaller
  - Respects `winfixwidth` and `winfixheight` options (unless `ignore_winfixwidth = true`)
  - Works with regular navigation, split creation, and wrap-around navigation
- Column limits are enforced within your current row; row limits are enforced within your current column. This matches how most users think about adding space where they currently are.
- When at/over limits, splitwise.nvim resizes the current window toward the edge using the steps above. If a window has `winfixheight`, resize is skipped vertically. If a window has `winfixwidth`, horizontal resize is skipped unless `ignore_winfixwidth = true`.
- Floating windows and windows with ignored filetypes/buftypes are excluded from navigation/creation decisions.

## Examples

- From a single window, press `<C-l>` (move right): creates a right split and focuses it. Press `<C-j>` (move down) to create a bottom split in that right column, if below `max_rows`.
- With two rows and one column in each, pressing `<C-l>` within the top row creates additional columns only up to `max_columns` for that row; further presses resize instead.

## Disable default keymaps

If you prefer your own mappings:

```lua
require("splitwise").setup({ create_default_keymaps = false })

vim.keymap.set("n", "<A-h>", require("splitwise").move_left,  { desc = "Splitwise left" })
vim.keymap.set("n", "<A-j>", require("splitwise").move_down,  { desc = "Splitwise down" })
vim.keymap.set("n", "<A-k>", require("splitwise").move_up,    { desc = "Splitwise up" })
vim.keymap.set("n", "<A-l>", require("splitwise").move_right, { desc = "Splitwise right" })
```

## FAQ

- Q: Does it work with floating terminals or popups?
  - A: Floating windows are ignored; navigation targets only regular windows.
- Q: What happens if I disable auto-creation by setting `max_columns = 1` and `max_rows = 1`?
  - A: Navigation still works. At edges, the plugin resizes toward the edge. If resize is not possible, it does nothing unless `wrap_navigation = true`.
- Q: Will it interfere with my `splitright`/`splitbelow` settings?
  - A: No. The plugin uses explicit `leftabove/rightbelow/aboveleft/belowright` so new windows always appear on the travel side.

## Alternatives

Check out [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) for a different
take on the same idea, particularly if you want Tmux integration. Splitwise (this plugin) is focused
purely on Neovim windows, and combines splitting and resizing in the same motions/keys
for simplicity and fewer total keybindings.

I also recently discovered [focus.nvim](https://github.com/nvim-focus/focus.nvim), which I haven't
tried but it looks like a very similar concept.

## Tips

- Consider mapping the functions in terminal-mode or visual-mode to taste if you frequently move around while in those modes.
- Combine with a window-equalizer plugin if you want automatic balancing after creations/resizes.

## Commands / API

Programmatic API:

```lua
local splitwise = require("splitwise")
splitwise.move_left()
splitwise.move_right()
splitwise.move_up()
splitwise.move_down()
```

## Development

- Issues and PRs welcome.
- Style: idiomatic Lua, clear naming, avoid deep nesting, handle edge cases first.
- Please include a concise description and reproduction steps for any bug report.

## Acknowledgements

Thanks to GPT-5 for the bulk of the implementation via the [Cursor CLI](https://cursor.com/cli).
