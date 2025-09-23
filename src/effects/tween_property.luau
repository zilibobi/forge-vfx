local lerp = require("../mod/lerp")
local tween = require("../mod/tween")
local utility = require("../mod/utility")

local rng = Random.new()

local prop = {}

function prop.emit(parent: Instance, obj: RayValue, scope: utility.scope)
  local property = obj.Name

  local emitDelay = utility.getAttribute(obj, "EmitDelay", 0)
  local resetOnFinish = utility.getAttribute(obj, "ResetOnFinish", true)

  local durationRange = utility.getRangeAttribute(obj, "Duration", NumberRange.new(1, 1), NumberRange.new(0, math.huge))

  if emitDelay > 0 then
    task.wait(emitDelay)
  end

  local endValue = obj:GetAttribute("_END_VALUE")
  local overrideStartValue = obj:GetAttribute("_START_VALUE")

  local ok, startValue = pcall(function()
    return parent[property]
  end)

  if overrideStartValue then
    startValue = overrideStartValue
  end

  local typeName = typeof(startValue)

  if not ok or typeName ~= typeof(endValue) then
    return
  end

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local speedStart = utility.getAttribute(obj, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(obj, "Speed_End", 1)

  local currentSpeed = speedStart

  local speedTween

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      utility.getAttribute(obj, "Speed_Curve", utility.default_bezier),
      utility.getAttribute(obj, "Speed_Duration", 0.1),
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  end

  local lfunc = lerp[typeName] or lerp.Other

  table.insert(
    scope,
    tween.fromParams(
      utility.getAttribute(obj, "Easing_Curve", utility.linear_bezier),
      duration,
      function(alpha, deltaTime)
        parent[property] = lfunc(startValue, endValue, alpha)
        return deltaTime * currentSpeed
      end,
      speedTween,
      nil,
      nil,
      utility.RENDER_PRIORITY + scope.depth
    )
  )

  if resetOnFinish then
    table.insert(scope, function()
      parent[property] = startValue
    end)
  end

  tween.timer(duration, function(deltaTime, elapsed)
    return if currentSpeed > 0 or (elapsed > 0 and speedTween and speedTween.Connected)
      then deltaTime * currentSpeed
      else nil
  end, speedTween, scope)
end

return prop
