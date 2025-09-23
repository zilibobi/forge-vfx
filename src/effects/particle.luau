local tween = require("../mod/tween")
local utility = require("../mod/utility")

local particle = {}

function particle.emit(ref: ParticleEmitter, obj: ParticleEmitter, scope: utility.scope)
  if ref.Enabled then
    ref.Enabled = false
  end

  local delay = utility.getAttribute(ref, "EmitDelay", 0)
  local count = utility.getAttribute(ref, "EmitCount", 1)
  local duration = utility.getAttribute(ref, "EmitDuration", 0)

  local useDuration = duration > 0

  task.wait(delay)

  if useDuration then
    obj.Enabled = true
  end

  local timeScaleDuration = utility.getAttribute(ref, "TimeScale_Duration", 0.1)

  local timeScaleStart = utility.getAttribute(ref, "TimeScale_Start", obj.TimeScale)
  local timeScaleEnd = utility.getAttribute(ref, "TimeScale_End", obj.TimeScale)

  local speedTween

  if timeScaleStart ~= timeScaleEnd then
    speedTween = tween.fromParams(
      utility.getAttribute(ref, "TimeScale_Curve", utility.default_bezier),
      timeScaleDuration,
      function(alpha, deltaTime)
        local speed = utility.lerp(timeScaleStart, timeScaleEnd, math.clamp(alpha, 0, 1))

        obj.TimeScale = speed

        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  elseif timeScaleStart ~= 1 then
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
