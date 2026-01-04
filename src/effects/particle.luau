local attr = require("@mod/attributes")
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")

local particle = {}

function particle.emit(ref: ParticleEmitter, obj: ParticleEmitter, scope: types.scope)
  if ref.Enabled then
    ref.Enabled = false
  end

  local delay = attr.get(ref, "EmitDelay", 0)
  local count = attr.get(ref, "EmitCount", 1)
  local duration = attr.get(ref, "EmitDuration", 0)

  local useDuration = duration > 0

  task.wait(delay)

  if useDuration then
    obj.Enabled = true
  end

  local timeScaleDuration = attr.get(ref, "TimeScale_Duration", 0.1)

  local timeScaleStart = attr.get(ref, "TimeScale_Start", obj.TimeScale, true)
  local timeScaleEnd = attr.get(ref, "TimeScale_End", obj.TimeScale, true)

  local speedTween

  if timeScaleStart ~= timeScaleEnd then
    speedTween = tween.fromParams(
      attr.get(ref, "TimeScale_Curve", utility.default_bezier),
      timeScaleDuration,
      function(alpha, deltaTime)
        local speed = utility.lerp(timeScaleStart, timeScaleEnd, math.clamp(alpha, 0, 1))

        obj.TimeScale = speed

        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  elseif timeScaleStart ~= obj.TimeScale then
    obj.TimeScale = timeScaleStart
  end

  obj:Emit(count)

  if useDuration then
    task.wait(duration)
    obj.Enabled = false
  end

  tween.timer(ref.Lifetime.Max, function(deltaTime, elapsed)
    return if ref.TimeScale > 0 or (elapsed > 0 and speedTween and speedTween.Connected)
      then deltaTime * ref.TimeScale
      else nil
  end, speedTween, scope)
end

return particle
