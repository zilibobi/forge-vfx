--!nolint LocalShadow
local RunService = game:GetService("RunService")

local attr = require("@mod/attributes")
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")
local flipbook_common = require("@mod/common/flipbook")

local Oklab = require("@mod/color/Oklab")
local Promise = require("@pkg/Promise")

local rng = Random.new()

local mesh = {}

function mesh.emit(ref: Model, obj: BasePart, scope: types.scope, scale: number, mustEmit: boolean?)
  local start = ref:FindFirstChild("Start")
  local goal = ref:FindFirstChild("End")

  if
    not start
    or not goal
    or not start:IsA("BasePart")
    or not goal:IsA("BasePart")
    or (attr.get(ref, "Enabled", false) and not mustEmit)
  then
    return
  end

  local legacy_duration = attr.get(ref, "Duration", 1, true)

  local durationRange = attr.getRange(
    ref,
    "EffectDuration",
    NumberRange.new(legacy_duration, legacy_duration),
    NumberRange.new(0, math.huge)
  )

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local emitDelay = attr.get(ref, "EmitDelay", 0)
  local destroyDelay = attr.get(ref, "DestroyDelay", 0)
  local emitDuration = attr.get(ref, "EmitDuration", 0)

  local legacy_isFlipbook = attr.get(ref, "Flipbook", false, true)
  local legacy_flipbookFadeOffset = attr.get(ref, "FlipbookFadeOffset", 0, true)

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

  local useEmitDuration = ref:HasTag(utility.ENABLED_VFX_TAG) and emitDuration > 0

  local legacy_decalST = attr.get(ref, "Decal_StartTransparency", 0, true)
  local legacy_decalET = attr.get(ref, "Decal_EndTransparency", 1, true)

  local partDefaultTp = 0

  do
    local decal = start and start:FindFirstChildOfClass("Decal")

    if decal then
      partDefaultTp = 1
    end
  end

  local legacy_meshST = attr.get(ref, "Mesh_StartTransparency", partDefaultTp, true)
  local legacy_meshET = attr.get(ref, "Mesh_EndTransparency", partDefaultTp, true)

  local sync = attr.get(ref, "SyncPosition", false)

  local speedStart = attr.get(ref, "Speed_Start", 1)
  local speedEnd = attr.get(ref, "Speed_End", 1)

  local tpStart = attr.get(ref, "Part_Transparency_Start", legacy_meshST)
  local tpEnd = attr.get(ref, "Part_Transparency_End", legacy_meshET)

  local spreadAngle = attr.get(ref, "SpreadAngle", vector.zero)

  local rotSpeedStartRange = attr.getRange(ref, "Part_RotSpeed_Start", NumberRange.new(0, 0))
  local rotSpeedEndRange = attr.getRange(ref, "Part_RotSpeed_End", NumberRange.new(0, 0))

  local rotAroundOrigin = attr.get(ref, "RotAroundOrigin", false)

  local minInitRot = attr.get(ref, "MinInitRot", vector.zero)
  local maxInitRot = attr.get(ref, "MaxInitRot", vector.zero)

  local rotSpeedStart = rng:NextNumber(rotSpeedStartRange.Min, rotSpeedStartRange.Max)
  local rotSpeedEnd = rng:NextNumber(rotSpeedEndRange.Min, rotSpeedEndRange.Max)

  local initRot = vector.create(
    rng:NextNumber(minInitRot.x, maxInitRot.x),
    rng:NextNumber(minInitRot.y, maxInitRot.y),
    rng:NextNumber(minInitRot.z, maxInitRot.z)
  ) * utility.DEG_TO_RAD

  local pauseContext = utility.getCurrentContext() or (scope :: any)._context

  utility.pausableWait(emitDelay)

  if useEmitDuration and not mustEmit then
    utility.forceEmit(ref, true)
    attr.trigger(ref, "Enabled", true)

    utility.onCancel(scope, function()
      local token = utility.stopEmitDuration(ref)

      if token then
        utility.cancelToken(token)
      end
    end)

    if speedStart ~= speedEnd then
      attr.setState(ref, "SpeedTweening", true)

      table.insert(
        scope,
        tween.fromParams(
          attr.get(ref, "Speed_Curve", utility.default_bezier),
          attr.get(ref, "Speed_Duration", 0.1),
          function(alpha, deltaTime)
            attr.setState(ref, "SpeedOverride", utility.lerp(speedStart, speedEnd, alpha))
            return deltaTime
          end,
          nil,
          function()
            attr.setState(ref, "SpeedTweening", nil)
          end,
          nil,
          nil,
          pauseContext
        )
      )
    end

    utility.pausableWait(emitDuration)

    utility.awaitEmitDuration(utility.stopEmitDuration(ref))

    return
  end

  local parent = ref:FindFirstAncestorOfClass("Attachment") or start
  local realObj = typeof(obj) == "table" and obj._getReal() or obj

  utility.registerPausable(scope, "meshPart", realObj)

  local origin = utility.getTransformedOriginExtents(parent)
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
    if pauseContext and pauseContext._paused then
      return
    end

    local o = sync and utility.getTransformedOriginExtents(parent) or origin
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
    local id = utility.getRandomId()

    RunService:BindToRenderStep(id, utility.RENDER_PRIORITY + scope.depth, updatePos)

    table.insert(scope, function()
      RunService:UnbindFromRenderStep(id)
    end)
  end

  local promises = {}

  local emitOnFinish = scope.effects.prepareEmitOnFinish(obj, scope)

  local env = scope.effects.emitNested(obj, scope.depth + 1, scope)
  table.insert(promises, env.Finished)

  local speedTween

  if speedStart ~= speedEnd and not attr.getState(ref, "SpeedOverride", nil) then
    speedTween = tween.fromParams(
      attr.get(ref, "Speed_Curve", utility.default_bezier),
      attr.get(ref, "Speed_Duration", 0.1),
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        return deltaTime
      end,
      nil,
      nil,
      nil,
      nil,
      pauseContext
    )

    table.insert(scope, speedTween)
  end

  if goalCFrameOffset ~= CFrame.identity then
    table.insert(
      scope,
      tween.fromParams(attr.get(ref, "Part_CFrame_Curve", utility.default_bezier), duration, function(alpha, deltaTime)
        currentCFrame = CFrame.identity:Lerp(goalCFrameOffset, alpha)
        return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
      end, speedTween, nil, nil, nil, pauseContext)
    )
  end

  if rotSpeedStart ~= rotSpeedEnd then
    table.insert(
      scope,
      tween.fromParams(
        attr.get(ref, "Part_RotSpeed_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          currentRotSpeed = utility.lerp(rotSpeedStart, rotSpeedEnd, alpha)
          return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
        end,
        speedTween,
        nil,
        nil,
        nil,
        pauseContext
      )
    )
  end

  if tpStart ~= tpEnd then
    table.insert(
      scope,
      tween.fromParams(
        attr.get(ref, "Part_Transparency_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.Transparency = utility.lerp(tpStart, tpEnd, alpha)
          return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
        end,
        speedTween,
        nil,
        nil,
        nil,
        pauseContext
      )
    )
  else
    obj.Transparency = tpStart
  end

  local sizeStart, sizeEnd = start.Size * scale, goal.Size * scale

  if sizeStart ~= sizeEnd then
    local lastSizeAlpha = -1

    table.insert(
      scope,
      tween.fromParams(attr.get(ref, "Part_Size_Curve", utility.default_bezier), duration, function(alpha, deltaTime)
        local speed = attr.getState(ref, "SpeedOverride", currentSpeed)

        -- reduce size writes
        if math.abs(alpha - lastSizeAlpha) < 0.005 then
          return deltaTime * speed
        end

        lastSizeAlpha = alpha
        obj.Size = sizeStart:Lerp(sizeEnd, alpha)

        return deltaTime * speed
      end, speedTween, nil, nil, nil, pauseContext)
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
            attr.get(ref, "Mesh_Scale_Curve", utility.default_bezier),
            duration,
            function(alpha, deltaTime)
              objMesh.Scale = utility.lerp(scaleStart, scaleEnd, alpha)
              return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
            end,
            speedTween,
            nil,
            nil,
            nil,
            pauseContext
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
            return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
          end, speedTween, nil, nil, nil, pauseContext)
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

        return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
      end, speedTween, nil, nil, nil, pauseContext)
    )
  else
    for _, decal in decals do
      local from = decal
      local to = fromToMap[from]

      local decal_tpStart = attr.get(from, "Transparency_Start", legacy_decalST)
      local decal_tpEnd = attr.get(from, "Transparency_End", legacy_decalET)

      if decal_tpStart ~= decal_tpEnd then
        table.insert(
          scope,
          tween.fromParams(
            attr.get(from, "Transparency_Curve", utility.default_bezier),
            duration,
            function(alpha, deltaTime)
              decal.Transparency = utility.lerp(decal_tpStart, decal_tpEnd, alpha)
              return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
            end,
            speedTween,
            nil,
            nil,
            nil,
            pauseContext
          )
        )
      else
        decal.Transparency = decal_tpStart
      end

      if from.Color3 ~= to.Color3 then
        table.insert(
          scope,
          tween.fromParams(attr.get(from, "Color_Curve", utility.default_bezier), duration, function(alpha, deltaTime)
            local a = Oklab.fromSRGB(from.Color3)
            local b = Oklab.fromSRGB(to.Color3)

            decal.Color3 = Oklab.toSRGB(a:Lerp(b, alpha), true)

            return deltaTime * (attr.getState(ref, "SpeedOverride", currentSpeed))
          end, speedTween, nil, nil, nil, pauseContext)
        )
      end

      local flipbook = flipbooks[from]

      if flipbook then
        local config = {
          ref = from,
          frames = flipbook,
          speedTween = speedTween,
          effectDuration = duration,

          curve = attr.get(from, "Flipbook_Change_Curve", utility.linear_bezier),
          duration = attr.get(from, "Flipbook_Change_Duration", duration),

          getSpeed = function()
            return attr.getState(ref, "SpeedOverride", currentSpeed)
          end,

          setTexture = function(texture)
            decal.Texture = texture
          end,
        }

        local changeDuration = flipbook_common.getChangeDuration(config)

        if changeDuration > longestFlipbookDuration then
          longestFlipbookDuration = changeDuration
        end

        table.insert(
          scope,
          tween.fromParams(config.curve, changeDuration, flipbook_common.createUpdateCallback(config), speedTween, nil, nil, nil, pauseContext)
        )
      end
    end
  end

  tween.timer(
    math.max(duration, longestFlipbookDuration) + legacy_flipbookFadeOffset + destroyDelay,
    function(deltaTime, elapsed)
      local speed = attr.getState(ref, "SpeedOverride", currentSpeed)

      currentSpeed = speed

      return if speed > 0
          or (elapsed > 0 and if speedTween then speedTween.Connected else attr.getState(ref, "SpeedTweening", false))
        then deltaTime * speed
        else nil
    end,
    speedTween,
    scope,
    nil,
    pauseContext
  )

  Promise.all(promises):await()

  local env = scope.effects.emitOnFinish(emitOnFinish, realObj, scope.depth + 1, scope)
  env.Finished:await()
end

return mesh
