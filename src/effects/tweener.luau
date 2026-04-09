local attr = require("@mod/attributes")
local lerp = require("@mod/lerp")
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")

local rng = Random.new()

local tweener = {}

function tweener.emit(obj: RayValue, scope: types.scope, isAttribute: boolean)
  local target = utility.getTarget(obj)

  if not target then
    return
  end

  local name = obj.Name

  local emitDelay = attr.get(obj, "EmitDelay", 0)
  local resetOnFinish = attr.get(obj, "ResetOnFinish", true)

  local durationRange = attr.getRange(obj, "Duration", NumberRange.new(1, 1), NumberRange.new(0, math.huge))

  if emitDelay > 0 then
    utility.pausableWait(emitDelay)
  end

  local endValue = attr.get(obj, "_END_VALUE", nil)
  local overrideStartValue = attr.get(obj, "_START_VALUE", nil)

  local startValue

  if isAttribute then
    startValue = attr.get(target, name, nil)
  else
    local ok, val = pcall(function()
      return target[name]
    end)

    if not ok then
      return
    end

    startValue = val
  end

  if overrideStartValue then
    startValue = overrideStartValue
  end

  local typeName = typeof(startValue)

  if typeName ~= typeof(endValue) then
    return
  end

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local speedStart = attr.get(obj, "Speed_Start", 1)
  local speedEnd = attr.get(obj, "Speed_End", 1)

  local currentSpeed = speedStart

  local speedTween

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      attr.get(obj, "Speed_Curve", utility.default_bezier),
      attr.get(obj, "Speed_Duration", 0.1),
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  end

  local lfunc = lerp[typeName] or lerp.Other

  local animator = if isAttribute
    then function(alpha, deltaTime)
      attr.set(target, name, lfunc(startValue, endValue, alpha))
      return deltaTime * currentSpeed
    end
    else function(alpha, deltaTime)
      target[name] = lfunc(startValue, endValue, alpha)
      return deltaTime * currentSpeed
    end

  table.insert(
    scope,
    tween.fromParams(
      attr.get(obj, "Easing_Curve", utility.linear_bezier),
      duration,
      animator,
      speedTween,
      nil,
      nil,
      utility.RENDER_PRIORITY + scope.depth
    )
  )

  if resetOnFinish then
    table.insert(scope, function()
      if isAttribute then
        attr.set(target, name, startValue)
      else
        target[name] = startValue
      end
    end)
  end

  tween.timer(duration, function(deltaTime, elapsed)
    return if currentSpeed > 0 or (elapsed > 0 and speedTween and speedTween.Connected)
      then deltaTime * currentSpeed
      else nil
  end, speedTween, scope)
end

return tweener
