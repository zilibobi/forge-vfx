local RunService = game:GetService("RunService")

local tween = require("../mod/tween")
local utility = require("../mod/utility")

local Shake = require("../pkg/Shake")

local activeShakes = {}
local totalShakeCF = CFrame.identity

local function updateCamera()
  if #activeShakes == 0 then
    return
  end

  local camera = workspace.CurrentCamera

  if not RunService:IsRunning() then
    camera.CFrame *= totalShakeCF:Inverse()

    -- I <3 THE STUDIO CAMERA SYSTEM !!!! YAYAY AIHU;S H;GDFAH GSDFL
    local cf = camera.CFrame
    local rx, ry = cf:ToOrientation()

    -- NO HAX ALLOWED!!!!!!!
    camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(rx, ry, 0)
  end

  local totalPos = vector.zero
  local totalRot = CFrame.identity

  local stillActive = {}

  for _, v in activeShakes do
    if v.done then
      continue
    end

    totalPos += v.pos
    totalRot *= CFrame.Angles(v.rot.x, v.rot.y, v.rot.z)

    table.insert(stillActive, v)
  end

  activeShakes = stillActive

  local total = CFrame.new(totalPos) * totalRot

  if not RunService:IsRunning() then
    totalShakeCF = total
  end

  camera.CFrame *= total
end

local camera_shake = {}

local conn
local lastCameraCf

function camera_shake.init()
  if conn then
    return
  end

  if RunService:IsRunning() then
    conn = RunService.Heartbeat:Connect(function()
      if not lastCameraCf then
        return
      end

      workspace.CurrentCamera.CFrame = lastCameraCf
    end)
  end

  RunService:BindToRenderStep("forge_updateCameraShake", Enum.RenderPriority.Last.Value + 1, updateCamera)
end

function camera_shake.deinit()
  if conn then
    conn:Disconnect()
    conn = nil
  end

  RunService:UnbindFromRenderStep("forge_updateCameraShake")
end

function camera_shake.emit(ref: RayValue, scope: utility.scope)
  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
  local emitDuration = utility.getAttribute(ref, "EmitDuration", 0)

  local falloff = utility.getAttribute(ref, "Falloff", 30)

  local amplitude = utility.getAttribute(ref, "Amplitude", 2.5)
  local frequency = utility.getAttribute(ref, "Frequency", 0.2)

  local fadeInTime = utility.getAttribute(ref, "FadeInTime", 0.3)
  local fadeOutTime = utility.getAttribute(ref, "FadeOutTime", 2)
  local sustainTime = utility.getAttribute(ref, "SustainTime", 1)

  local posInfluence = utility.getAttribute(ref, "PositionInfluence", vector.one)
  local rotInfluence = utility.getAttribute(ref, "RotationInfluence", vector.one * 0.2)

  local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

  local sustained = emitDuration > 0

  local shake = Shake.new()
  shake.Sustain = sustained
  shake.Amplitude = amplitude
  shake.Frequency = frequency
  shake.FadeInTime = fadeInTime
  shake.FadeOutTime = fadeOutTime
  shake.SustainTime = sustainTime
  shake.PositionInfluence = posInfluence
  shake.RotationInfluence = rotInfluence

  local currentSpeed = 1

  local elapsed = 0

  shake.TimeFunction = function()
    return elapsed
  end

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
      utility.getAttribute(ref, "Speed_Duration", 0.1),
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  end

  table.insert(
    scope,
    RunService.RenderStepped:Connect(function(deltaTime)
      elapsed += deltaTime * currentSpeed
    end)
  )

  local obj = {
    done = false,
    pos = vector.zero,
    rot = vector.zero,
  }

  task.wait(emitDelay)

  table.insert(activeShakes, obj)

  local thread = coroutine.running()

  shake:BindToRenderStep(Shake.NextRenderName(), utility.RENDER_PRIORITY + scope.depth, function(pos, rot, isDone)
    local camera = workspace.CurrentCamera

    lastCameraCf = camera.CFrame

    local origin = ref:FindFirstAncestorOfClass("Attachment") or ref:FindFirstAncestorWhichIsA("BasePart")

    if origin then
      local alpha = 1
        - math.clamp(
          (camera.CFrame.Position - (origin:IsA("Attachment") and origin.WorldPosition or origin.Position)).Magnitude
            / falloff,
          0,
          1
        )

      pos *= alpha
      rot *= alpha
    end

    obj.pos = pos
    obj.rot = rot
    obj.done = isDone

    if isDone then
      lastCameraCf = nil
      task.spawn(thread)
    end
  end)

  shake:Start()

  if sustained then
    task.wait(emitDuration)
    shake:StopSustain()
  end

  if not obj.done then
    coroutine.yield()
  end
end

return camera_shake
