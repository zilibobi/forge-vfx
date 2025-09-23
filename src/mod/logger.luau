local function msg(...: string)
  return `[Forge Emit API]: {table.concat({ ... }, " ")}`
end

local logger = {}

function logger.error(...)
  error(msg(..., "\n"))
end

function logger.warn(...)
  warn(msg(...))
  warn(msg(debug.traceback("stack trace:")))
end

function logger.info(...)
  print(msg(...))
end

return logger
