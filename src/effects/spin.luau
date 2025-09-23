local tween = require("../mod/tween")
local utility = require("../mod/utility")

local spin = {}

function spin.emit(ref: Model, scope: utility.scope)
  local rotation = utility.getAttribute(ref, "SpinRotation", vector.zero, true) * utility.DEG_TO_RAD

  local scaleStart = utility.getAttribute(ref, "Scale_Start", 1, true)
  local scaleEnd = utility.getAttribute(ref, "Scale_End", 1, true)

  if rotation == vector.zero and scaleStart == 1 and scaleEnd == 1 then
    return
  end

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

  local sync = utility.getAttribute(ref, "SyncPosition", false)
  local duration = utility.getAttribute(ref, "SpinDuration", 0.5)

  local speedDuration = utility.getAttribute(ref, "SpinSpeed_Duration", 0.1)

  local speedStart = utility.getAttribute(ref, "SpinSpeed_Start", 0)
  local speedEnd = utility.getAttribute(ref, "SpinSpeed_End", 1)

  local currentSpeed = speedStart

  task.wait(emitDelay)

  local speedTween

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      utility.getAttribute(ref, "SpinSpeed_Curve", utility.default_bezier),
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
        utility.getAttribute(ref, "Scale_Curve", utility.default_bezier),
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
    ref:PivotTo(parent and (parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame) or originalPivot)
    ref:ScaleTo(originalScale)
  end)

  rotation *= duration

  tween.timer(duration, function(deltaTime, elapsed)
    local alpha = math.clamp(elapsed / duration, 0, 1)

    local r = rotation * alpha
    local cf = (
      if parent and sync then (parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame) else originalPivot
    ) * CFrame.fromOrientation(r.x, r.y, r.z)

    ref:PivotTo(cf)

    return if currentSpeed > 0 or (elapsed > 0 and speedTween.Connected) then deltaTime * currentSpeed else nil
  end, speedTween, scope, utility.RENDER_PRIORITY + scope.depth)
end

return spin
