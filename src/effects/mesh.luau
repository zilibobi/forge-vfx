local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local tween = require("../mod/tween")
local utility = require("../mod/utility")

local Oklab = require("../mod/color/Oklab")
local Promise = require("../pkg/Promise")

local rng = Random.new()

local mesh = {}

function mesh.emit(ref: Model, obj: BasePart, scope: utility.scope, scale: number, mustEmit: boolean?)
  local start = ref:FindFirstChild("Start")
  local goal = ref:FindFirstChild("End")

  if
    not start
    or not goal
    or not start:IsA("BasePart")
    or not goal:IsA("BasePart")
    or (ref:GetAttribute("Enabled") and not mustEmit)
  then
    return
  end

  local legacy_duration = utility.getAttribute(ref, "Duration", 1, true)

  local durationRange = utility.getRangeAttribute(
    ref,
    "EffectDuration",
    NumberRange.new(legacy_duration, legacy_duration),
    NumberRange.new(0, math.huge)
  )

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
  local emitDuration = utility.getAttribute(ref, "EmitDuration", 0, true)

  local legacy_isFlipbook = utility.getAttribute(ref, "Flipbook", false, true)
  local legacy_flipbookFadeOffset = utility.getAttribute(ref, "FlipbookFadeOffset", 0, true)

  -- stone age compatibility
  do
    local prefix

    if legacy_isFlipbook or not start:FindFirstChildOfClass("Decal") then
      prefix = "Mesh_"
    else
      prefix = "Decal_"
    end

    local ts = ref:GetAttribute("StartTransparency")

    if ts ~= nil then
      ref:SetAttribute(prefix .. "StartTransparency", ts)
      ref:SetAttribute("StartTransparency", nil)
    end

    local te = ref:GetAttribute("EndTransparency")

    if te ~= nil then
      ref:SetAttribute(prefix .. "EndTransparency", te)
      ref:SetAttribute("EndTransparency", nil)
    end
  end

  local useEmitDuration = ref:GetAttribute("Enabled") ~= nil and ref:HasTag(utility.ENABLED_VFX_TAG) and duration > 0

  local legacy_decalST = utility.getAttribute(ref, "Decal_StartTransparency", 0, true)
  local legacy_decalET = utility.getAttribute(ref, "Decal_EndTransparency", 1, true)

  local partDefaultTp = 0

  do
    local decal = start and start:FindFirstChildOfClass("Decal")

    if decal then
      partDefaultTp = 1
    end
  end

  local legacy_meshST = utility.getAttribute(ref, "Mesh_StartTransparency", partDefaultTp, true)
  local legacy_meshET = utility.getAttribute(ref, "Mesh_EndTransparency", partDefaultTp, true)

  local sync = utility.getAttribute(ref, "SyncPosition", false)

  local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

  local tpStart = utility.getAttribute(ref, "Part_Transparency_Start", legacy_meshST)
  local tpEnd = utility.getAttribute(ref, "Part_Transparency_End", legacy_meshET)

  local spreadAngle = utility.getAttribute(ref, "SpreadAngle", vector.zero)

  local rotSpeedStartRange = utility.getRangeAttribute(ref, "Part_RotSpeed_Start", NumberRange.new(0, 0))
  local rotSpeedEndRange = utility.getRangeAttribute(ref, "Part_RotSpeed_End", NumberRange.new(0, 0))

  local rotAroundOrigin = utility.getAttribute(ref, "RotAroundOrigin", false)

  local minInitRot = utility.getAttribute(ref, "MinInitRot", vector.zero)
  local maxInitRot = utility.getAttribute(ref, "MaxInitRot", vector.zero)

  local rotSpeedStart = rng:NextNumber(rotSpeedStartRange.Min, rotSpeedStartRange.Max)
  local rotSpeedEnd = rng:NextNumber(rotSpeedEndRange.Min, rotSpeedEndRange.Max)

  local initRot = vector.create(
    rng:NextNumber(minInitRot.x, maxInitRot.x),
    rng:NextNumber(minInitRot.y, maxInitRot.y),
    rng:NextNumber(minInitRot.z, maxInitRot.z)
  ) * utility.DEG_TO_RAD

  task.wait(emitDelay)

  if useEmitDuration and not mustEmit then
    ref:SetAttribute("Enabled", true)

    if speedStart ~= speedEnd then
      ref:SetAttribute("SpeedTweening", true)

      table.insert(
        scope,
        tween.fromParams(
          utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
          utility.getAttribute(ref, "Speed_Duration", 0.1),
          function(alpha, deltaTime)
            ref:SetAttribute("SpeedOverride", utility.lerp(speedStart, speedEnd, alpha))
            return deltaTime
          end,
          nil,
          function()
            ref:SetAttribute("SpeedTweening", nil)
          end
        )
      )
    end

    task.wait(emitDuration)

    ref:SetAttribute("Enabled", false)
    ref:SetAttribute("SpeedOverride", nil)

    return
  end

  local parent = ref:FindFirstAncestorOfClass("Attachment") or start
  local realObj = typeof(obj) == "table" and obj._getReal() or obj

  local function getOrigin()
    return parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame
  end

  local origin = getOrigin()
  local goalCFrameOffset = start.CFrame:ToObjectSpace(goal.CFrame)

  local currentSpeed = speedStart
  local currentRotSpeed = rotSpeedStart

  local currentRot = CFrame.fromOrientation(initRot.x, initRot.y, initRot.z)
  local currentCFrame = CFrame.identity

  local spread = CFrame.fromOrientation(
    math.rad(rng:NextNumber(-spreadAngle.x, spreadAngle.x)),
    math.rad(rng:NextNumber(-spreadAngle.y, spreadAngle.y)),
    0
  )

  local function updatePos(deltaTime: number)
    local o = sync and getOrigin() or origin
    local add = initRot:Sign() * currentRotSpeed * deltaTime

    currentRot *= CFrame.fromOrientation(add.x, add.y, add.z)

    local cf

    if rotAroundOrigin then
      cf = o * spread * currentRot * currentCFrame
    else
      cf = o * spread * currentCFrame * currentRot
    end

    cf *= currentRot

    obj.CFrame = cf
  end

  updatePos(0)

  do
    local id = utility.getRanomId()

    RunService:BindToRenderStep(id, utility.RENDER_PRIORITY + scope.depth, updatePos)

    table.insert(scope, function()
      RunService:UnbindFromRenderStep(id)
    end)
  end

  local promises = {}

  local emitOnFinish = obj:FindFirstChild("EmitOnFinish")

  if emitOnFinish then
    emitOnFinish.Parent = nil
    table.insert(scope, emitOnFinish)
  end

  if shared.vfx and #obj:GetChildren() ~= 0 then
    local env = shared.vfx.emit(obj)
    table.insert(promises, env.Finished)
  end

  local speedTween

  if speedStart ~= speedEnd and not ref:GetAttribute("SpeedOverride") then
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

  if goalCFrameOffset ~= CFrame.identity then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Part_CFrame_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          currentCFrame = CFrame.identity:Lerp(goalCFrameOffset, alpha)
          return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
        end,
        speedTween
      )
    )
  end

  if rotSpeedStart ~= rotSpeedEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Part_RotSpeed_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          currentRotSpeed = utility.lerp(rotSpeedStart, rotSpeedEnd, alpha)
          return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
        end,
        speedTween
      )
    )
  end

  if tpStart ~= tpEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Part_Transparency_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.Transparency = utility.lerp(tpStart, tpEnd, alpha)
          return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
        end,
        speedTween
      )
    )
  else
    obj.Transparency = tpStart
  end

  local sizeStart, sizeEnd = start.Size * scale, goal.Size * scale

  if sizeStart ~= sizeEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Part_Size_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.Size = sizeStart:Lerp(sizeEnd, alpha)
          return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
        end,
        speedTween
      )
    )
  else
    obj.Size = sizeStart
  end

  local startMesh = start:FindFirstChildOfClass("SpecialMesh")
  local goalMesh = goal:FindFirstChildOfClass("SpecialMesh")

  local objMesh = obj:FindFirstChildOfClass("SpecialMesh")

  if objMesh then
    if startMesh and goalMesh then
      local scaleStart, scaleEnd = startMesh.Scale * scale, goalMesh.Scale * scale

      if scaleStart ~= scaleEnd then
        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(ref, "Mesh_Scale_Curve", utility.default_bezier),
            duration,
            function(alpha, deltaTime)
              objMesh.Scale = utility.lerp(scaleStart, scaleEnd, alpha)
              return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
            end,
            speedTween
          )
        )
      end
    else
      objMesh.Parent = nil

      table.insert(scope, function()
        objMesh.Parent = realObj
      end)
    end
  end

  local decals, flipbooks, fromToMap = utility.getMeshDecals(ref, obj)

  local longestFlipbookDuration = 0

  if legacy_isFlipbook then
    table.sort(decals, function(a, b)
      local x = a.Name:match("%d+") or 0
      local y = b.Name:match("%d+") or 0

      return tonumber(x) < tonumber(y)
    end)

    local displayDecal = Instance.new("Decal")
    displayDecal.Parent = realObj

    table.insert(scope, displayDecal)

    if legacy_flipbookFadeOffset > 0 then
      if legacy_decalST ~= legacy_decalET then
        table.insert(
          scope,
          tween.fromParams(utility.default_bezier, duration + legacy_flipbookFadeOffset, function(alpha, deltaTime)
            displayDecal.Transparency = utility.lerp(legacy_decalST, legacy_decalET, alpha)
            return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
          end, speedTween)
        )
      end
    end

    table.insert(
      scope,
      tween.fromParams(utility.default_bezier, duration, function(alpha, deltaTime)
        local index = math.max(math.round(#decals * alpha), 1)
        local target = decals[index]

        displayDecal.Texture = target.Texture

        displayDecal.Color3 = target.Color3
        displayDecal.ZIndex = target.ZIndex

        if legacy_flipbookFadeOffset == 0 then
          displayDecal.Transparency = utility.lerp(legacy_decalST, legacy_decalET, alpha)
          displayDecal.ZIndex = target.ZIndex
        end

        return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
      end, speedTween)
    )
  else
    for _, decal in decals do
      local from = decal
      local to = fromToMap[from]

      local decal_tpStart = utility.getAttribute(from, "Transparency_Start", legacy_decalST)
      local decal_tpEnd = utility.getAttribute(from, "Transparency_End", legacy_decalET)

      if decal_tpStart ~= decal_tpEnd then
        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(from, "Transparency_Curve", utility.default_bezier),
            duration,
            function(alpha, deltaTime)
              decal.Transparency = utility.lerp(decal_tpStart, decal_tpEnd, alpha)
              return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
            end,
            speedTween
          )
        )
      else
        decal.Transparency = decal_tpStart
      end

      if from.Color3 ~= to.Color3 then
        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(from, "Color_Curve", utility.default_bezier),
            duration,
            function(alpha, deltaTime)
              local a = Oklab.fromSRGB(from.Color3)
              local b = Oklab.fromSRGB(to.Color3)

              decal.Color3 = Oklab.toSRGB(a:Lerp(b, alpha), true)

              return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
            end,
            speedTween
          )
        )
      end

      local flipbook = flipbooks[from]

      if flipbook then
        local changeDuration = utility.getAttribute(from, "Flipbook_Change_Duration", duration)

        if utility.getAttribute(from, "SyncDuration", false) then
          changeDuration = duration
        end

        if changeDuration > longestFlipbookDuration then
          longestFlipbookDuration = changeDuration
        end

        local temp = false

        if RunService:IsStudio() then
          for _, tag in CollectionService:GetTags(from) do
            if tag:match("^_local_flipbook_") then
              temp = true
              break
            end
          end
        end

        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(from, "Flipbook_Change_Curve", utility.linear_bezier),
            changeDuration,
            function(alpha, deltaTime)
              local index = math.max(math.round(#flipbook * alpha), 1)
              decal.Texture = `{temp and "rbxtemp://" or "rbxassetid://"}{flipbook[index]}`

              return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
            end,
            speedTween
          )
        )
      end
    end
  end

  tween.timer(math.max(duration, longestFlipbookDuration) + legacy_flipbookFadeOffset, function(deltaTime, elapsed)
    local speed = ref:GetAttribute("SpeedOverride") or currentSpeed

    currentSpeed = speed

    return if speed > 0
        or (elapsed > 0 and if speedTween then speedTween.Connected else ref:GetAttribute("SpeedTweening"))
      then deltaTime * speed
      else nil
  end, speedTween, scope)

  Promise.all(promises):await()

  local children = emitOnFinish and emitOnFinish:GetChildren()

  if children and #children ~= 0 then
    for _, child in children do
      child.Parent = realObj
    end

    local env = shared.vfx.emit(table.unpack(children))
    env.Finished:await()
  end
end

return mesh
