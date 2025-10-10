local state = require('ipynb.state')

local M = {}

local Kernel = {}
Kernel.__index = Kernel

function Kernel.new(bufnr, kernel_type)
  return setmetatable({
    bufnr = bufnr,
    kernel_type = kernel_type or "python3",
    job_id = nil,
    running = false,
    output_buffer = {},
    raw_buffer = "",
    collecting = false,
    current_callback = nil,
    executed_code = "",
  }, Kernel)
end

function Kernel:start()
  if self.running then
    vim.notify("Kernel already running", vim.log.levels.WARN)
    return true
  end
  
  local cmd = {
    "jupyter",
    "console",
    "--kernel=" .. self.kernel_type,
    "--simple-prompt"
  }
  
  self.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _) self:on_output(data) end,
    on_stderr = function(_, data, _) self:on_error(data) end,
    on_exit = function(_, code, _) self:on_exit(code) end,
    pty = true,
  })
  
  if self.job_id <= 0 then
    vim.notify("Failed to start kernel", vim.log.levels.ERROR)
    return false
  end
  
  self.running = true
  state.kernels[self.bufnr] = self
  vim.notify("Kernel started (" .. self.kernel_type .. ")", vim.log.levels.INFO)
  return true
end

function Kernel:execute(code, callback)
  if not self.running then
    vim.notify("Kernel not running", vim.log.levels.ERROR)
    return
  end
  
  -- Reset state for new execution
  self.output_buffer = {}
  self.raw_buffer = ""
  self.current_callback = callback
  self.collecting = true
  self.executed_code = code
  
  vim.fn.chansend(self.job_id, code .. "\n")
  
  -- Stop collecting after timeout
  vim.defer_fn(function()
    self.collecting = false
    if not self.current_callback then return end
    
    local clean_buffer = self:process_output(self.raw_buffer)
    local lines = vim.split(clean_buffer, "\n", { plain = true })
    
    if #lines > 0 then
      self.current_callback(lines)
    end
    self.current_callback = nil
  end, 2000)
end

function Kernel:process_output(raw)
  local clean = raw or ""
  
  -- Unescape if stringified
  if clean:match('^".*"$') then
    local ok, unescaped = pcall(load, "return " .. clean)
    if ok and type(unescaped) == "string" then
      clean = unescaped
    end
  end
  
  -- Strip ANSI escape codes
  clean = clean:gsub("\27%[[0-9;]*m", "")
  
  -- Normalize line endings
  clean = clean:gsub("\r\n", "\n"):gsub("\r", "\n")
  
  -- Ensure error separators are isolated
  clean = clean
    :gsub("([^\n%-])(%-{5,})", "%1\n%2")
    :gsub("(%-{5,})([^\n%-])", "%1\n%2")
    :gsub("(%-{5,})(ModuleNotFoundError)", "%1\n%2")
    :gsub("(%-{5,})(Traceback)", "%1\n%2")
    :gsub("(%-{5,})(Exception)", "%1\n%2")
    :gsub("\n+", "\n")
  
  return clean
end

function Kernel:on_output(data)
  if not data or #data == 0 or not self.collecting then return end
  
  for _, chunk in ipairs(data) do
    self.raw_buffer = self.raw_buffer .. chunk
  end
end

function Kernel:on_error(data)
  if not data or #data == 0 then return end
  vim.notify(
    "Kernel error: " .. table.concat(data, "\n"),
    vim.log.levels.ERROR
  )
end

function Kernel:on_exit(code)
  self.running = false
  state.kernels[self.bufnr] = nil
  vim.notify("Kernel exited (" .. code .. ")", vim.log.levels.WARN)
end

function Kernel:stop()
  if self.running and self.job_id then
    vim.fn.jobstop(self.job_id)
    self.running = false
    state.kernels[self.bufnr] = nil
    vim.notify("Kernel stopped", vim.log.levels.INFO)
  end
end

function M.get_or_create(bufnr)
  local k = state.kernels[bufnr]
  
  if not k or not k.running then
    k = Kernel.new(bufnr, "python3")
    if not k:start() then
      return nil
    end
    -- Wait for kernel to initialize
    vim.defer_fn(function()
      vim.notify("Kernel ready", vim.log.levels.INFO)
    end, 1000)
  end
  
  return k
end

function M.start(bufnr)
  local k = Kernel.new(bufnr, "python3")
  k:start()
end

function M.stop(bufnr)
  local k = state.kernels[bufnr]
  if k then
    k:stop()
  else
    vim.notify("No kernel running", vim.log.levels.WARN)
  end
end

return M
