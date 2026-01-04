local batch = require("@mod/tween_batch")
local logger = require("@mod/logger")
local utility = require("@mod/utility")

local Bezier = require("@obj/Bezier")

local tween = {}

local bezierCache: { [string]: Bezier.Bezier } = {}

function tween.fromParams(
  params: string,
  duration: number,
  animator: (alpha: number, deltaTime: number, elapsed: number) -> number?,
  awaitTween: RBXScriptConnection?,
  onFinish: ((organic: boolean) -> ())?,
  startAtZero: boolean?,
  stepAtPriority: number?
)
  local bezier = bezierCache[params]

  if not bezier then
    local success, points = pcall(function()
      return utility.deserializePath(params)
    end)

    if not success then
      logger.error(`failed to decode bezier path data with error: {points}`)
    end

    bezier = Bezier.new(points, 0)
    bezierCache[params] = bezier
  end

  local elapsed = 0
  local finished = false

  local unregister

  local function step(deltaTime): boolean
    if finished then
      return true
    end

    if not startAtZero and elapsed == 0 then
      elapsed = math.clamp(elapsed + deltaTime, 0, math.max(duration, 0))
    end

    local t = math.clamp(elapsed / duration, 0, 1)
    local alpha = 1 - bezier:getEase(t).y

    local result = animator(alpha, deltaTime, elapsed)

    if
      (result == nil or (if duration ~= 0 then elapsed >= duration else elapsed > duration))
      and (not awaitTween or not awaitTween.Connected)
    then
      finished = true

      if onFinish then
        onFinish(true)
      end

      return true
    end

    if result then
      elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
    end

    return false
  end

  -- connection-like interface for compatibility
  local handler = {}
  handler.Connected = true

  function handler:Disconnect()
    if not handler.Connected then
      return
    end

    finished = true
    handler.Connected = false

    if unregister then
      unregister()
    end
  end

  unregister = batch.register(stepAtPriority, {
    step = function(deltaTime): boolean
      local done = step(deltaTime)

      if done then
        handler.Connected = false
      end

      return done
    end,
  })

  return handler
end

function tween.timer(
  duration: number,
  counter: (deltaTime: number, elapsed: number) -> number,
  awaitTween: RBXScriptConnection?,
  scope: {}?,
  stepAtPriority: number?
)
  local main = coroutine.running()

  local elapsed = 0
  local finished = false

  local unregister: (() -> ())?

  local function step(deltaTime): boolean
    if finished then
      return true
    end

    local result = counter(deltaTime, elapsed)

    if
      (result == nil or (if duration ~= 0 then elapsed >= duration else elapsed > duration))
      and (not awaitTween or not awaitTween.Connected)
    then
      finished = true
      task.spawn(main)

      return true
    end

    if result then
      elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
    end

    return false
  end

  unregister = batch.register(stepAtPriority, {
    step = step,
  })

  local cleanup = function()
    if finished then
      return
    end

    finished = true

    if unregister then
      unregister()
    end
  end

  if scope then
    table.insert(scope, cleanup)
  end

  coroutine.yield()
end

return tween
