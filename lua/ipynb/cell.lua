local state = require('ipynb.state')

local M = {}

local Cell = {}
Cell.__index = Cell

function Cell.new(start_line, end_line, bufnr)
  local self = setmetatable({}, Cell)
  self.start_line = start_line
  self.end_line = end_line
  self.bufnr = bufnr
  self.id = string.format("%d-%d-%d", bufnr, start_line, end_line)
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
    -- Skip the cell marker line
    if not (i == 1 and line:match("^# %%")) then
      table.insert(content, line)
    end
  end
  
  return table.concat(content, "\n")
end


function M.parse_cells(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cells = {}
  local starts = {}
  
  -- Find all cell markers
  for i, line in ipairs(lines) do
    if line:match("^# %%") then
      table.insert(starts, i)
    end
  end
  
  -- Create cells
  if #starts == 0 then
    -- No markers, treat entire buffer as one cell
    table.insert(cells, Cell.new(1, #lines, bufnr))
  else
    for i, start_line in ipairs(starts) do
      local end_line = starts[i + 1] and (starts[i + 1] - 1) or #lines
      table.insert(cells, Cell.new(start_line, end_line, bufnr))
    end
  end
  
  state.cells[bufnr] = cells
  return cells
end

function M.get_current_cell(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cells = state.cells[bufnr] or M.parse_cells(bufnr)
  local line = vim.fn.line(".")
  
  for _, cell in ipairs(cells) do
    if line >= cell.start_line and line <= cell.end_line then
      return cell
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
