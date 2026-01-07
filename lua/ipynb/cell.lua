local state = require('ipynb.state')

local M = {}

local function ensure_namespaces()
  if not state.ns_cells then
    state.ns_cells = vim.api.nvim_create_namespace("ipynb_cells")
  end
end

local Cell = {}
Cell.__index = Cell

function Cell.new(start_line, end_line, bufnr, mark_id)
  local self = setmetatable({}, Cell)
  self.start_line = start_line
  self.end_line = end_line
  self.bufnr = bufnr
  self.mark_id = mark_id
  self.id = string.format("%d:%d", bufnr, mark_id) 
  return self
end

function Cell:get_content()
  local lines = vim.api.nvim_buf_get_lines(
    self.bufnr,
    self.start_line - 1,
    self.end_line,
    false
  )

  local content = {}
  for i, line in ipairs(lines) do
    if not (i == 1 and line:match("^# %%")) then
      table.insert(content, line)
    end
  end

  return table.concat(content, "\n")
end

local function get_or_create_marker_extmark(bufnr, marker_lnum_1based)
  local row = marker_lnum_1based - 1

  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    state.ns_cells,
    { row, 0 },
    { row, -1 },
    { details = true }
  )

  if #marks > 0 then
    -- marks are {id, row, col, details}
    return marks[1][1]
  end

  -- Create a new extmark anchored at the marker line
  local id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_cells, row, 0, {
    right_gravity = false,
  })
  return id
end

function M.parse_cells(bufnr)
  ensure_namespaces()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cells = {}
  local starts = {}

  for i, line in ipairs(lines) do
    if line:match("^# %%") then
      table.insert(starts, i) -- 1-based
    end
  end

  if #starts == 0 then
    -- No markers: treat entire buffer as one cell.
    -- Anchor a marker extmark at row 0 to get a stable ID.
    local mark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_cells, 0, 0, {
      right_gravity = false,
    })
    table.insert(cells, Cell.new(1, #lines, bufnr, mark_id))
  else
    for i, start_line in ipairs(starts) do
      local end_line = starts[i + 1] and (starts[i + 1] - 1) or #lines
      local mark_id = get_or_create_marker_extmark(bufnr, start_line)
      table.insert(cells, Cell.new(start_line, end_line, bufnr, mark_id))
    end
  end

  -- Ensure sorted (they should be already)
  table.sort(cells, function(a, b) return a.start_line < b.start_line end)

  state.cells[bufnr] = cells
  return cells
end

-- Binary search by current cursor line (1-based)
function M.get_current_cell(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cells = state.cells[bufnr] or M.parse_cells(bufnr)
  local line = vim.fn.line(".")

  local lo, hi = 1, #cells
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local c = cells[mid]
    if line < c.start_line then
      hi = mid - 1
    elseif line > c.end_line then
      lo = mid + 1
    else
      return c
    end
  end

  return nil
end

function M.jump_to_next()
  local bufnr = vim.api.nvim_get_current_buf()
  local cells = state.cells[bufnr] or M.parse_cells(bufnr)
  local line = vim.fn.line(".")

  for _, c in ipairs(cells) do
    if c.start_line > line then
      vim.api.nvim_win_set_cursor(0, { c.start_line, 0 })
      return
    end
  end

  vim.notify("No next cell", vim.log.levels.INFO)
end

function M.jump_to_prev()
  local bufnr = vim.api.nvim_get_current_buf()
  local cells = state.cells[bufnr] or M.parse_cells(bufnr)
  local line = vim.fn.line(".")

  for i = #cells, 1, -1 do
    if cells[i].start_line < line then
      vim.api.nvim_win_set_cursor(0, { cells[i].start_line, 0 })
      return
    end
  end

  vim.notify("No previous cell", vim.log.levels.INFO)
end

function M.update_signs(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.fn.sign_unplace("jupyter", { buffer = bufnr })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^# %%") then
      vim.fn.sign_place(0, "jupyter", "jupyter_cell", bufnr, { lnum = i })
    end
  end
end

return M

