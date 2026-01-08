local state = require('ipynb.state')

local M = {}

local function ensure_ns()
  if not state.ns_inline then
    state.ns_inline = vim.api.nvim_create_namespace("ipynb_inline_output")
  end
end

-- image.nvim support
local has_image_nvim = false
local image_nvim = nil

local function check_image_nvim()
  local ok, img = pcall(require, 'image')
  if ok then
    has_image_nvim = true
    image_nvim = img
  end
  return has_image_nvim
end

check_image_nvim()

local function detect_png_marker(lines)
  local last = nil
  for _, line in ipairs(lines) do
    local p = line:match("^__NVIM_PNG__:(.+)$")
    if p and p ~= "" then
      last = p
    end
  end
  if last then
    return true, last
  end
  return false, nil
end

local function ensure_buf_cleanup_autocmd(bufnr)
  if vim.b[bufnr]._ipynb_png_cleanup_set then return end
  vim.b[bufnr]._ipynb_png_cleanup_set = true

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      local st = require("ipynb.state")
      local o = st.outputs and st.outputs[bufnr]
      if not o then return end
      for _, cellout in pairs(o) do
        if cellout.image_tmp then
          pcall(vim.fn.delete, cellout.image_tmp)
          cellout.image_tmp = nil
        end
        cellout.image = nil
      end
      st.outputs[bufnr] = nil
    end,
  })
end

local function render_image_file_in_float(bufnr, cell, win, path)
  if not has_image_nvim or not image_nvim then return false end

  ensure_buf_cleanup_autocmd(bufnr)

  state.outputs[bufnr] = state.outputs[bufnr] or {}
  state.outputs[bufnr][cell.id] = state.outputs[bufnr][cell.id] or {}
  local slot = state.outputs[bufnr][cell.id]

  -- If we previously stored a different temp file for this cell, delete it now.
  if slot.image_tmp and slot.image_tmp ~= path then
    pcall(vim.fn.delete, slot.image_tmp)
  end
  slot.image_tmp = path

  -- Create image object; render on next tick to avoid "white first render" races.
  local ok, img = pcall(function()
    return image_nvim.from_file(path, { window = win, x = 0, y = 0 })
  end)
  if not ok or not img then
    vim.notify("Image render init failed: " .. tostring(img), vim.log.levels.WARN)
    return false
  end

  slot.image = img

  vim.schedule(function()
      local ok2, err = pcall(function()
          vim.defer_fn(function()
              if slot.image and slot.image.render then
                  slot.image:render()
              end
          end, 30)
      end
  )
  if not ok2 then
      vim.notify("Image render failed: " .. tostring(err), vim.log.levels.WARN)
    end
  end)

  return true
end

local function detect_image_output(lines)
  local last_png_path = nil
  local last_base64 = nil

  for _, line in ipairs(lines) do
    local p = line:match("^__NVIM_PNG__:(.+)$")
    if p and p ~= "" then
      last_png_path = p
    end

    if line:match("^data:image/png;base64,")
      or line:match("^data:image/jpeg;base64,")
      or line:match("^iVBORw0KGgo")
      or line:match("^/9j/") then
      last_base64 = line
    end
  end

  if last_png_path then return "file", last_png_path end
  if last_base64 then return "base64", last_base64 end
  return nil, nil
end

local function write_binary_file(path, bytes)
  local uv = vim.loop
  local fd = uv.fs_open(path, "w", 420) -- 0644
  if not fd then return false end
  uv.fs_write(fd, bytes, -1)
  uv.fs_close(fd)
  return true
end

local function decode_base64_to_bytes(b64)
  -- Prefer Neovim built-in if available
  if vim.base64 and vim.base64.decode then
    local ok, out = pcall(vim.base64.decode, b64)
    if ok and type(out) == "string" then
      return out
    end
  end

  -- Fallback: call base64 -d with stdin (avoids shell quoting)
  local out = vim.fn.system({ "base64", "-d" }, b64)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

local function render_image_in_float(bufnr, cell, win, image_data)
  if not has_image_nvim or not image_nvim then
    return false
  end

  local base64_data = image_data
  if image_data:match("^data:image/[^;]+;base64,") then
    base64_data = image_data:match("^data:image/[^;]+;base64,(.+)$")
  end

  local bytes = decode_base64_to_bytes(base64_data)
  if not bytes then
    vim.notify("Failed to decode image", vim.log.levels.WARN)
    return false
  end

  local tmp_file = vim.fn.tempname() .. ".png"
  if not write_binary_file(tmp_file, bytes) then
    vim.notify("Failed to write image temp file", vim.log.levels.WARN)
    return false
  end

  -- Create image object and render it.
  local ok, img_or_err = pcall(function()
    local img = image_nvim.from_file(tmp_file, {
      window = win,
      x = 0,
      y = 0,
    })
    -- IMPORTANT: render explicitly
    if img and img.render then
      img:render()
    end
    return img
  end)

  if not ok or not img_or_err then
    vim.notify("Image rendering failed: " .. tostring(img_or_err), vim.log.levels.WARN)
    -- cleanup temp file if we failed
    vim.fn.delete(tmp_file)
    return false
  end

  -- Keep reference so it doesn't get GC'd, and keep tmp file until window closes
  state.outputs[bufnr] = state.outputs[bufnr] or {}
  state.outputs[bufnr][cell.id] = state.outputs[bufnr][cell.id] or {}
  state.outputs[bufnr][cell.id].image = img_or_err
  state.outputs[bufnr][cell.id].image_tmp = tmp_file

  -- Cleanup when the window closes
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    callback = function(ev)
      -- ev.match is the winid as a string
      local closed = tonumber(ev.match)
      if closed == win then
        local o = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
        if o then
          -- clear image ref
          o.image = nil
          if o.image_tmp then
            vim.fn.delete(o.image_tmp)
            o.image_tmp = nil
          end
        end
      end
    end,
  })

  return true
end

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
    type = "float",
  }

  return out_buf, win
end

local function clear_inline(bufnr)
  ensure_ns()
  vim.api.nvim_buf_clear_namespace(bufnr, state.ns_inline, 0, -1)
end

function M.display(bufnr, cell, lines, inline)
  state.cell_outputs[bufnr] = state.cell_outputs[bufnr] or {}
  state.cell_outputs[bufnr][cell.id] = lines

  if inline then
    ensure_ns()
    clear_inline(bufnr)

    local row = math.max(0, cell.end_line - 1)

    local virt = {}
    table.insert(virt, { { "────────────────────────────────────────", "Comment" } })
    for _, l in ipairs(lines) do
      table.insert(virt, { { l, "Normal" } })
    end

    vim.api.nvim_buf_set_extmark(bufnr, state.ns_inline, row, 0, {
      virt_lines = virt,
      virt_lines_above = false,
    })

    state.last_inline_cell[bufnr] = cell.id
    return
  end

  local oinfo = state.outputs[bufnr] and state.outputs[bufnr][cell.id]
  local out_buf, win

  if oinfo and vim.api.nvim_win_is_valid(oinfo.win_id) then
      out_buf = oinfo.bufnr
      win = oinfo.win_id
  else
      out_buf, win = create_float_window(bufnr, cell)
  end

  if not out_buf then return end

  local kind, data = detect_image_output(lines)

  if kind == "file" then
      -- render from file
      render_image_file_in_float(bufnr, cell, win, data)
      return
  elseif kind == "base64" then
      -- legacy path
      render_image_in_float(bufnr, cell, win, data)
      return
  end

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
    return
  end

  local saved = state.cell_outputs[bufnr] and state.cell_outputs[bufnr][cell.id]
  if saved then
    M.display(bufnr, cell, saved, false)
  else
    vim.notify("No output to show", vim.log.levels.INFO)
  end
end

function M.show_inline(bufnr, cell)
  local saved = state.cell_outputs[bufnr] and state.cell_outputs[bufnr][cell.id]
  if not saved then return end

  if state.last_inline_cell[bufnr] == cell.id then
    return
  end

  M.display(bufnr, cell, saved, true)
end

function M.hide_inline(bufnr, _cell)
  clear_inline(bufnr)
  state.last_inline_cell[bufnr] = nil
end

function M.hide_all_inline(bufnr)
  clear_inline(bufnr)
  state.last_inline_cell[bufnr] = nil
end

function M.has_image_support()
  return has_image_nvim
end

return M

