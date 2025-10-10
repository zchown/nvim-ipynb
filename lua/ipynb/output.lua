local state = require('ipynb.state')

local M = {}

local function create_float_window(bufnr, cell)
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[out_buf].bufhidden = "wipe"
  vim.bo[out_buf].modifiable = false
  vim.bo[out_buf].filetype = "jupyter-output"
  
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.3)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local win = vim.api.nvim_open_win(out_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Cell Output ",
    title_pos = "center",
  })
  
  vim.wo[win].cursorline = true
  
  -- Close keymaps
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = out_buf, silent = true })
  
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = out_buf, silent = true })
  
  state.outputs[bufnr] = state.outputs[bufnr] or {}
  state.outputs[bufnr][cell.id] = {
    bufnr = out_buf,
    win_id = win,
    type = "float"
  }
  
  return out_buf, win
end

local function create_inline_window(bufnr, cell)
  -- Find the window showing the buffer
  local main_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      main_win = win
      break
    end
  end
  
  if not main_win then return nil, nil end
  
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[out_buf].bufhidden = "wipe"
  vim.bo[out_buf].modifiable = false
  vim.bo[out_buf].filetype = "jupyter-output"
  
  local width = vim.api.nvim_win_get_width(main_win)
  local height = 10
  
  local win = vim.api.nvim_open_win(out_buf, false, {
    relative = "win",
    win = main_win,
    width = width - 2,
    height = height,
    row = cell.end_line,
    col = 0,
    style = "minimal",
    border = "single",
    title = " Output ",
    title_pos = "left",
  })
  
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winhighlight = "Normal:JupyterInlineOutput"
  
  state.outputs[bufnr] = state.outputs[bufnr] or {}
  state.outputs[bufnr][cell.id] = {
    bufnr = out_buf,
    win_id = win,
    type = "inline"
  }
  
  return out_buf, win
end

function M.display(bufnr, cell, lines, inline)
  -- Save output for later retrieval
  state.cell_outputs[bufnr] = state.cell_outputs[bufnr] or {}
  state.cell_outputs[bufnr][cell.id] = lines
  
  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  local out_buf, win
  
  if oinfo then
    out_buf = oinfo.bufnr
    win = oinfo.win_id
    
    -- Recreate window if invalid
    if not vim.api.nvim_win_is_valid(win) then
      if inline then
        out_buf, win = create_inline_window(bufnr, cell)
      else
        out_buf, win = create_float_window(bufnr, cell)
      end
    end
  else
    if inline then
      out_buf, win = create_inline_window(bufnr, cell)
    else
      out_buf, win = create_float_window(bufnr, cell)
    end
  end
  
  if not out_buf then return end
  
  vim.bo[out_buf].modifiable = true
  vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, lines)
  vim.bo[out_buf].modifiable = false
end

function M.close(bufnr, cell)
  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  if oinfo and vim.api.nvim_win_is_valid(oinfo.win_id) then
    vim.api.nvim_win_close(oinfo.win_id, true)
  end
end

function M.toggle(bufnr, cell)
  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  
  if oinfo and vim.api.nvim_win_is_valid(oinfo.win_id) then
    vim.api.nvim_win_close(oinfo.win_id, true)
  else
    -- Show last output if available
    local saved = state.cell_outputs[bufnr]
      and state.cell_outputs[bufnr][cell.id]
    
    if saved then
      M.display(bufnr, cell, saved, false)
    else
      vim.notify("No output to show", vim.log.levels.INFO)
    end
  end
end

function M.show_inline(bufnr, cell)
  local saved = state.cell_outputs[bufnr]
    and state.cell_outputs[bufnr][cell.id]
  
  if not saved then return end
  
  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  
  -- Already showing inline
  if oinfo and oinfo.type == "inline"
    and vim.api.nvim_win_is_valid(oinfo.win_id) then
    return
  end
  
  -- Close any existing output
  if oinfo and vim.api.nvim_win_is_valid(oinfo.win_id) then
    vim.api.nvim_win_close(oinfo.win_id, true)
  end
  
  M.display(bufnr, cell, saved, true)
end

function M.hide_inline(bufnr, cell)
  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  
  if oinfo and oinfo.type == "inline"
    and vim.api.nvim_win_is_valid(oinfo.win_id) then
    vim.api.nvim_win_close(oinfo.win_id, true)
  end
end

function M.hide_all_inline(bufnr)
  if not state.outputs[bufnr] then return end
  
  for _, oinfo in pairs(state.outputs[bufnr]) do
    if oinfo.type == "inline" and vim.api.nvim_win_is_valid(oinfo.win_id) then
      vim.api.nvim_win_close(oinfo.win_id, true)
    end
  end
end

return M
