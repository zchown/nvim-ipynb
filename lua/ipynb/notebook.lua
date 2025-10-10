local M = {}

function M.load(path)
  local tmp = vim.fn.tempname() .. ".py"
  local res = vim.fn.system({
    "jupytext",
    "--to", "py:percent",
    "--output", tmp,
    path
  })
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to load: " .. res, vim.log.levels.ERROR)
    return nil
  end
  
  local content = vim.fn.readfile(tmp)
  vim.fn.delete(tmp)
  return content
end

function M.save(bufnr, path)
  local tmp = vim.fn.tempname() .. ".py"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.writefile(lines, tmp)
  
  local res = vim.fn.system({
    "jupytext",
    "--to", "ipynb",
    "--output", path,
    tmp
  })
  
  vim.fn.delete(tmp)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to save: " .. res, vim.log.levels.ERROR)
    return false
  end
  
  vim.bo[bufnr].modified = false
  vim.notify("Saved notebook", vim.log.levels.INFO)
  return true
end

return M
