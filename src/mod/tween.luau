local RunService = game:GetService("RunService")

local logger = require("./logger")
local utility = require("./utility")

local Bezier = require("../obj/Bezier")

local tween = {}

function tween.fromParams(
  params: string,
  duration: number,
  animator: (alpha: number, deltaTime: number, elapsed: number) -> number?,
  awaitTween: RBXScriptConnection?,
  onFinish: (() -> ())?,
  startAtZero: boolean?,
  stepAtPriority: number?
)
  local success, points = pcall(function()
    return utility.deserializePath(params)
  end)

  if not success then
    logger.error(`failed to decode bezier path data with error: {points}`)
  end

  -- use 0 accuracy as it saves performance because there is no need to calculate the length
  local bezier = Bezier.new(points, 0)
  local elapsed = 0

  local cleanupStepper

  local function step(deltaTime)
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
    local id = utility.getRanomId()

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
  stepAtPriority: number?
)
  local main = coroutine.running()

  local elapsed = 0

  local cleanupStepper

  local function step(deltaTime)
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
    local id = utility.getRanomId()

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
