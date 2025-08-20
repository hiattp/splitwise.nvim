local M = {}

local default_config = {
  max_columns = 2,
  max_rows = 2,
  resize_step_cols = 5,
  resize_step_rows = 3,
  create_default_keymaps = true,
  wrap_navigation = false,
  ignore_filetypes = { "help", "qf" },
  ignore_buftypes = { "nofile", "terminal", "prompt" },
  new_split_opens_blank_buffer = false,
  -- If true, allow horizontal resize even when current window has 'winfixwidth'
  -- Vertical resize still respects 'winfixheight'.
  ignore_winfixwidth = false,
}

local user_config = {}

local function get_config()
  return vim.tbl_deep_extend("force", default_config, user_config or {})
end

local function get_current_tabpage()
  return vim.api.nvim_get_current_tabpage()
end

local function get_windows_in_tab(tabpage)
  return vim.api.nvim_tabpage_list_wins(tabpage)
end

local function is_floating(win)
  local cfg = vim.api.nvim_win_get_config(win)
  return cfg and cfg.relative ~= "" and cfg.relative ~= nil
end

local function should_ignore_window(win, cfg)
  if is_floating(win) then
    return true
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local bt = vim.api.nvim_get_option_value("buftype", { buf = buf })
  for _, ignored in ipairs(cfg.ignore_buftypes or {}) do
    if bt == ignored then
      return true
    end
  end
  local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
  for _, ignored in ipairs(cfg.ignore_filetypes or {}) do
    if ft == ignored then
      return true
    end
  end
  return false
end

local function get_win_bounds(win)
  -- returns top, left, height, width in screen cells
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return 0, 0, 0, 0
  end
  return info.topline or info.top, info.leftcol or info.left, info.height, info.width
end

local function get_edge_windows(cfg)
  local tab = get_current_tabpage()
  local wins = get_windows_in_tab(tab)
  local candidates = {}
  for _, w in ipairs(wins) do
    if not should_ignore_window(w, cfg) then
      table.insert(candidates, w)
    end
  end
  if #candidates == 0 then
    return {}
  end

  local leftmost, rightmost, topmost, bottommost
  local min_left, max_right, min_top, max_bottom

  for _, w in ipairs(candidates) do
    local top, left, height, width = get_win_bounds(w)
    local right = left + width - 1
    local bottom = top + height - 1

    if not min_left or left < min_left then
      min_left = left
      leftmost = w
    end
    if not max_right or right > max_right then
      max_right = right
      rightmost = w
    end
    if not min_top or top < min_top then
      min_top = top
      topmost = w
    end
    if not max_bottom or bottom > max_bottom then
      max_bottom = bottom
      bottommost = w
    end
  end

  return {
    left = leftmost,
    right = rightmost,
    top = topmost,
    bottom = bottommost,
  }
end

local function get_neighbor_window(direction, cfg)
  -- Try to use builtin wincmd to move; if cursor moves, we have a neighbor
  local current = vim.api.nvim_get_current_win()
  local before = current
  local cmd = ({
    left = "h",
    right = "l",
    up = "k",
    down = "j",
  })[direction]
  if not cmd then
    return nil
  end

  -- Try to move; if movement fails, Neovim keeps the same window
  vim.cmd("wincmd " .. cmd)
  local after = vim.api.nvim_get_current_win()
  if after ~= before then
    -- moved; move back to original and return the neighbor id
    vim.api.nvim_set_current_win(before)
    return after
  end
  return nil
end

-- Layout helpers based on winlayout():
--  node = { 'leaf', winid } | { 'row', { child... } } | { 'col', { child... } }
local function layout_contains_win(node, winid)
  local node_type = node[1]
  if node_type == 'leaf' then
    return node[2] == winid
  end
  local children = node[2]
  for _, child in ipairs(children) do
    if layout_contains_win(child, winid) then
      return true
    end
  end
  return false
end

local function count_top_level_columns_via_layout(layout)
  if layout[1] == 'row' then
    return #layout[2]
  end
  return 1
end

local function get_branch_for_current_column(layout, current_win)
  -- A "column" corresponds to one child of a top-level 'row'. If there is no
  -- top-level 'row', the whole layout is a single column.
  if layout[1] == 'row' then
    for _, child in ipairs(layout[2]) do
      if layout_contains_win(child, current_win) then
        return child
      end
    end
    return nil
  else
    return layout
  end
end

local function count_rows_in_branch(node)
  local node_type = node[1]
  if node_type == 'leaf' then
    return 1
  end
  local children = node[2]
  if node_type == 'col' then
    -- Stacked vertically: sum rows of children
    local sum = 0
    for _, child in ipairs(children) do
      sum = sum + count_rows_in_branch(child)
    end
    return sum
  else -- 'row' - side-by-side: take the max rows among children
    local max_rows = 1
    for _, child in ipairs(children) do
      local r = count_rows_in_branch(child)
      if r > max_rows then
        max_rows = r
      end
    end
    return max_rows
  end
end

local function count_rows_in_current_column(cfg)
  local layout = vim.fn.winlayout()
  local current = vim.api.nvim_get_current_win()
  local column_branch = get_branch_for_current_column(layout, current)
  if not column_branch then
    return 1
  end
  return count_rows_in_branch(column_branch)
end

local function get_branch_for_current_row(layout, current_win)
  -- A "row" corresponds to one child of a top-level 'col'. If there is no
  -- top-level 'col', the whole layout is a single row.
  if layout[1] == 'col' then
    for _, child in ipairs(layout[2]) do
      if layout_contains_win(child, current_win) then
        return child
      end
    end
    return nil
  else
    return layout
  end
end

local function count_columns_in_branch(node)
  local node_type = node[1]
  if node_type == 'leaf' then
    return 1
  end
  local children = node[2]
  if node_type == 'row' then
    -- Side-by-side horizontally: sum columns of children
    local sum = 0
    for _, child in ipairs(children) do
      sum = sum + count_columns_in_branch(child)
    end
    return sum
  else -- 'col' - stacked vertically: take the max columns among children
    local max_cols = 1
    for _, child in ipairs(children) do
      local c = count_columns_in_branch(child)
      if c > max_cols then
        max_cols = c
      end
    end
    return max_cols
  end
end

local function count_columns_in_current_row(cfg)
  local layout = vim.fn.winlayout()
  local current = vim.api.nvim_get_current_win()
  local row_branch = get_branch_for_current_row(layout, current)
  if not row_branch then
    return 1
  end
  return count_columns_in_branch(row_branch)
end

local function open_split(direction, cfg)
  -- Capture existing wins to identify the newly created window reliably
  local tab = get_current_tabpage()
  local before = {}
  for _, w in ipairs(get_windows_in_tab(tab)) do
    before[w] = true
  end

  if direction == "right" then
    vim.cmd("rightbelow vsplit")
  elseif direction == "left" then
    vim.cmd("leftabove vsplit")
  elseif direction == "up" then
    vim.cmd("aboveleft split")
  elseif direction == "down" then
    vim.cmd("belowright split")
  end
  if cfg.new_split_opens_blank_buffer then
    vim.cmd("enew")
  end

  -- Focus the new window explicitly
  local new_win
  for _, w in ipairs(get_windows_in_tab(tab)) do
    if not before[w] and not should_ignore_window(w, cfg) then
      new_win = w
      break
    end
  end
  if new_win then
    pcall(vim.api.nvim_set_current_win, new_win)
  end
end

local function can_resize_current(direction, cfg)
  local win = vim.api.nvim_get_current_win()
  local fixwidth = vim.api.nvim_win_get_option(win, "winfixwidth")
  local fixheight = vim.api.nvim_win_get_option(win, "winfixheight")
  if (direction == "left" or direction == "right") and fixwidth and not (cfg and cfg.ignore_winfixwidth) then
    return false
  end
  if (direction == "up" or direction == "down") and fixheight then
    return false
  end
  return true
end

local function resize_towards(direction, cfg)
  if not can_resize_current(direction, cfg) then
    return false
  end
  if direction == "left" or direction == "right" then
    local win = vim.api.nvim_get_current_win()
    local disabled_fixwidth = false
    if cfg and cfg.ignore_winfixwidth then
      local ok_get, fixwidth = pcall(vim.api.nvim_win_get_option, win, "winfixwidth")
      if ok_get and fixwidth then
        local ok_set = pcall(vim.api.nvim_win_set_option, win, "winfixwidth", false)
        if ok_set then
          disabled_fixwidth = true
        end
      end
    end
    local ok_cmd, _ = pcall(vim.cmd, "vertical resize +" .. tonumber(cfg.resize_step_cols or 5))
    if disabled_fixwidth then
      pcall(vim.api.nvim_win_set_option, win, "winfixwidth", true)
    end
    return ok_cmd
  else
    vim.cmd("resize +" .. tonumber(cfg.resize_step_rows or 3))
    return true
  end
end

local function wrap_to_opposite_edge(direction, cfg)
  local edges = get_edge_windows(cfg)
  local target
  if direction == "left" then
    target = edges.right
  elseif direction == "right" then
    target = edges.left
  elseif direction == "up" then
    target = edges.bottom
  elseif direction == "down" then
    target = edges.top
  end
  if target and target ~= 0 then
    pcall(vim.api.nvim_set_current_win, target)
    return true
  end
  return false
end

local function move(direction)
  local cfg = get_config()

  -- If neighbor exists, just move
  local neighbor = get_neighbor_window(direction, cfg)
  if neighbor then
    pcall(vim.api.nvim_set_current_win, neighbor)
    return
  end

  -- We are at the edge in that direction
  local can_create = false
  if direction == "left" or direction == "right" then
    local num_columns = count_columns_in_current_row(cfg)
    can_create = num_columns < (cfg.max_columns or 1)
  else
    local num_rows = count_rows_in_current_column(cfg)
    can_create = num_rows < (cfg.max_rows or 1)
  end

  if can_create then
    open_split(direction, cfg)
    return
  end

  -- If cannot create, try resizing
  local resized = resize_towards(direction, cfg)
  if resized then
    return
  end

  -- If cannot resize, optionally wrap
  if cfg.wrap_navigation then
    wrap_to_opposite_edge(direction, cfg)
  end
end

function M.move_left()
  move("left")
end

function M.move_right()
  move("right")
end

function M.move_up()
  move("up")
end

function M.move_down()
  move("down")
end

function M.setup(opts)
  user_config = opts or {}
  local cfg = get_config()
  if cfg.create_default_keymaps then
    vim.keymap.set("n", "<C-h>", M.move_left, { noremap = true, silent = true, desc = "Splitwise: move left" })
    vim.keymap.set("n", "<C-l>", M.move_right, { noremap = true, silent = true, desc = "Splitwise: move right" })
    vim.keymap.set("n", "<C-k>", M.move_up, { noremap = true, silent = true, desc = "Splitwise: move up" })
    vim.keymap.set("n", "<C-j>", M.move_down, { noremap = true, silent = true, desc = "Splitwise: move down" })
  end
end

return M
