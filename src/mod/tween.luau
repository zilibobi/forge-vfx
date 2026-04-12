local RunService = game:GetService("RunService")

local logger = require("@mod/logger")
local utility = require("@mod/utility")

local Bezier = require("@obj/Bezier")

local tween = {}

tween.bezier_cache = {} :: { [string]: Bezier.Bezier }

function tween.fromParams(
  params: string,
  duration: number,
  animator: (alpha: number, deltaTime: number, elapsed: number) -> number?,
  awaitTween: RBXScriptConnection?,
  onFinish: ((organic: boolean) -> ())?,
  startAtZero: boolean?,
  stepAtPriority: number?,
  contextOverride: any?
)
  local bezier = tween.bezier_cache[params]

  if not bezier then
    local success, points = pcall(function()
      return utility.deserializePath(params)
    end)

    if not success then
      logger.error(`failed to decode bezier path data with error: {points}`)
    end

    -- use 0 accuracy as it saves performance because there is no need to calculate the length
    bezier = Bezier.new(points, 0)
    tween.bezier_cache[params] = bezier
  end

  local elapsed = 0

  local cleanupStepper

  -- use an explicit context when provided; otherwise fall back to the
  -- thread-local lookup.  the explicit path is more reliable because it
  -- doesn't depend on which coroutine happens to be running at call time.
  local context = contextOverride or utility.getCurrentContext()

  local function step(deltaTime)
    -- when paused, freeze the tween in place: skip the elapsed update and
    -- skip the animator entirely so it doesn't write stale property values
    if context and context._paused then
      return
    end

    -- roblox tweens apparently don't start from alpha=0
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
      cleanupStepper()

      if onFinish then
        onFinish(true)
      end

      return
    end

    if result then
      elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
    end
  end

  if not stepAtPriority then
    local connection: RBXScriptConnection
    connection = RunService.RenderStepped:Connect(step)

    cleanupStepper = function()
      connection:Disconnect()
    end

    return connection
  else
    local id = utility.getRandomId()

    RunService:BindToRenderStep(id, stepAtPriority, step)

    local bound = true

    cleanupStepper = function()
      if not bound then
        return
      end

      bound = false

      RunService:UnbindFromRenderStep(id)
    end

    return cleanupStepper
  end
end

function tween.timer(
  duration: number,
  counter: (deltaTime: number, elapsed: number) -> number,
  awaitTween: RBXScriptConnection?,
  scope: {}?,
  stepAtPriority: number?,
  contextOverride: any?
)
  local main = coroutine.running()

  local elapsed = 0

  local cleanupStepper

  local context = contextOverride or utility.getCurrentContext()

  local function step(deltaTime)
    if context and context._paused then
      return
    end

    local result = counter(deltaTime, elapsed)

    if
      (result == nil or (if duration ~= 0 then elapsed >= duration else elapsed > duration))
      and (not awaitTween or not awaitTween.Connected)
    then
      cleanupStepper()
      task.spawn(main)
      return
    end

    if result then
      elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
    end
  end

  if not stepAtPriority then
    local connection = RunService.RenderStepped:Connect(step)

    cleanupStepper = function()
      connection:Disconnect()
    end
  else
    local id = utility.getRandomId()

    RunService:BindToRenderStep(id, stepAtPriority, step)

    local bound = true

    cleanupStepper = function()
      if not bound then
        return
      end

      bound = false

      RunService:UnbindFromRenderStep(id)
    end
  end

  if scope then
    table.insert(scope, cleanupStepper)
  end

  coroutine.yield()
end

return tween
