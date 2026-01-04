local attr = require("@mod/attributes")
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")

local spin = {}

function spin.emit(ref: Model, scope: types.scope)
  if utility.isSpinModelStatic(ref) then
    return
  end

  local rotation = attr.get(ref, "SpinRotation", vector.zero) * utility.DEG_TO_RAD

  local scaleStart = attr.get(ref, "Scale_Start", 1)
  local scaleEnd = attr.get(ref, "Scale_End", 1)

  local emitDelay = attr.get(ref, "EmitDelay", 0)

  local sync = attr.get(ref, "SyncPosition", false)
  local duration = attr.get(ref, "SpinDuration", 0.5)

  local speedDuration = attr.get(ref, "SpinSpeed_Duration", 0.1)

  local speedStart = attr.get(ref, "SpinSpeed_Start", 0)
  local speedEnd = attr.get(ref, "SpinSpeed_End", 1)

  local currentSpeed = speedStart

  task.wait(emitDelay)

  local speedTween

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      attr.get(ref, "SpinSpeed_Curve", utility.default_bezier),
      speedDuration,
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  end

  local originalPivot = ref:GetPivot()
  local originalScale = ref:GetScale()

  if scaleStart ~= scaleEnd then
    table.insert(
      scope,
      tween.fromParams(
        attr.get(ref, "Scale_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          ref:ScaleTo(utility.lerp(scaleStart, scaleEnd, alpha))
          return deltaTime
        end
      )
    )
  else
    ref:ScaleTo(scaleStart)
  end

  local parent = ref:FindFirstAncestorOfClass("Attachment") or ref:FindFirstAncestorWhichIsA("BasePart")

  table.insert(scope, function()
    ref:PivotTo(parent and utility.getTransformedOriginExtents(parent) or originalPivot)
    ref:ScaleTo(originalScale)
  end)

  rotation *= duration

  tween.timer(duration, function(deltaTime, elapsed)
    local alpha = math.clamp(elapsed / duration, 0, 1)

    local r = rotation * alpha
    local cf = (if parent and sync then utility.getTransformedOriginExtents(parent) else originalPivot)
      * CFrame.fromOrientation(r.x, r.y, r.z)

    ref:PivotTo(cf)

    return if currentSpeed > 0 or (elapsed > 0 and speedTween.Connected) then deltaTime * currentSpeed else nil
  end, speedTween, scope, utility.RENDER_PRIORITY + scope.depth)
end

return spin
