local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local tween = require("../mod/tween")
local shape = require("../mod/shape")
local utility = require("../mod/utility")

local Bezier = require("../obj/Bezier")
local Promise = require("../pkg/Promise")
local ObjectCache = require("../obj/ObjectCache")

local drawFuncMap = {
  Box = {
    Volume = shape.getPointWithinBox,
    Surface = shape.getPointOnBox,
  },

  Cylinder = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinCylinder(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinCylinder(seed, 1, partial, cframe, size, normal)
    end,
  },

  Sphere = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinSphere(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinSphere(seed, 1, partial, cframe, size, normal)
    end,
  },

  Disc = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinDisc(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinDisc(seed, 1, partial, cframe, size, normal)
    end,
  },
}

local bezier = {}

local part_cache: ObjectCache.ObjectCache?

function bezier.init(cache)
  part_cache = cache
end

function bezier.deinit()
  part_cache = nil
end

function bezier.emit(ref: Attachment, refObj: Part, scope: utility.scope, mustEmit: boolean?)
  local root = ref:FindFirstChild("Points")

  if not root or not root:IsA("Attachment") or not part_cache then
    return
  end

  -- TODO: use a default map and GetAttributes instead of this mess
  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
  local emitCount = utility.getAttribute(ref, "EmitCount", 1)
  local emitDuration = utility.getAttribute(ref, "EmitDuration", 0)
  local destroyDelay = utility.getAttribute(ref, "DestroyDelay", 0)

  local animDuration = utility.getRangeAttribute(ref, "Duration", NumberRange.new(1, 1), NumberRange.new(0, math.huge))

  local face = utility.getEnumAttribute(ref, "ShapeFace", "Outward", { "InAndOut", "Inward", "Outward" })
  local spreadAngle = utility.getAttribute(ref, "SpreadAngle", vector.zero)

  local sync = utility.getAttribute(ref, "SyncPosition", false)

  local mirror = utility.getAttribute(ref, "MirrorPaths", true)
  local mirrorRot = utility.getAttribute(ref, "MirrorRotation", vector.create(0, 0, 180))

  local animFacePath = utility.getAttribute(ref, "FacePath", false)
  local animArcSpace = utility.getAttribute(ref, "ArcSpace", false)

  local partial = utility.getAttribute(ref, "ShapePartial", 1)

  local shape = utility.getEnumAttribute(ref, "Shape", "Box", { "Box", "Cylinder", "Sphere", "Disc" })
  local style = utility.getEnumAttribute(ref, "ShapeStyle", "Volume", { "Volume", "Surface" })

  local emission_direction = Enum.NormalId[utility.getEnumAttribute(
    ref,
    "EmissionDirection",
    "Top",
    { "Top", "Bottom", "Left", "Right", "Front", "Back" }
  )]

  local projEnabled = utility.getAttribute(ref, "ProjectileEnabled", false)
  local projMatchEnd = utility.getAttribute(ref, "MatchEndDirection", false)

  local projSpeed = utility.getAttribute(ref, "ProjectileSpeed", 30)
  local projLifetime =
    utility.getRangeAttribute(ref, "ProjectileLifetime", NumberRange.new(1, 1), NumberRange.new(0, math.huge))

  local hbEnabled = utility.getAttribute(ref, "HitboxEnabled", false)
  local hbColGroup = utility.getAttribute(ref, "HitboxCollisionGroup", "Default")
  local hbFilterTag = utility.getAttribute(ref, "HitboxFilterTag", "")
  local hbFilterType = utility.getAttribute(ref, "HitboxFilterType", "Exclude")
  local hbIgnoreCanCollide = utility.getAttribute(ref, "HitboxIgnoreCanCollide", false)

  local rotSpeedStartRange = utility.getRangeAttribute(ref, "RotSpeed_Start", NumberRange.new(0, 0))
  local rotSpeedEndRange = utility.getRangeAttribute(ref, "RotSpeed_End", NumberRange.new(0, 0))

  local minInitRot = utility.getAttribute(ref, "MinInitRot", vector.zero)
  local maxInitRot = utility.getAttribute(ref, "MaxInitRot", vector.zero)

  local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

  local drawFunc = drawFuncMap[shape] and drawFuncMap[shape][style]

  if not drawFunc then
    return
  end

  local promises = {}

  local useDuration = emitDuration > 0

  task.wait(emitDelay)

  if useDuration and not mustEmit then
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
  elseif emitCount > 0 then
    local originSize: Vector3?
    local originCFrame: CFrame?

    local parent = ref.Parent

    if not parent then
      return
    end

    if not parent:IsA("BasePart") and not parent:IsA("Attachment") then
      parent = ref
    end

    if parent:IsA("BasePart") then
      originSize = parent.Size
      originCFrame = parent.CFrame
    elseif parent:IsA("Attachment") then
      originSize = Vector3.zero
      originCFrame = parent.WorldCFrame
    end

    if not originCFrame then
      return
    end

    local endPoint = ref:FindFirstChild("End")
    local endT1 = endPoint and endPoint:FindFirstChild("T1")

    if endPoint and not endPoint:IsA("Attachment") then
      endPoint = nil
    end

    if endT1 and not endT1:IsA("Attachment") then
      endT1 = nil
    end

    local points = utility.getBezierPoints(root)

    local rng = Random.new()
    local bezier = not endPoint and Bezier.new(points)

    local params = OverlapParams.new()
    params.MaxParts = 1
    params.FilterType = Enum.RaycastFilterType[hbFilterType]
    params.CollisionGroup = hbColGroup
    params.RespectCanCollide = not hbIgnoreCanCollide

    params:AddToFilter(CollectionService:GetTagged(hbFilterTag))

    if hbFilterType == "Exclude" then
      params:AddToFilter({ workspace.Terrain, parent, root:FindFirstAncestorOfClass("Part") })
    end

    for i = 1, emitCount do
      local rotSpeedStart = rng:NextNumber(rotSpeedStartRange.Min, rotSpeedStartRange.Max)
      local rotSpeedEnd = rng:NextNumber(rotSpeedEndRange.Min, rotSpeedEndRange.Max)

      local initRot = vector.create(
        rng:NextNumber(minInitRot.x, maxInitRot.x),
        rng:NextNumber(minInitRot.y, maxInitRot.y),
        rng:NextNumber(minInitRot.z, maxInitRot.z)
      )

      local duration = rng:NextNumber(animDuration.Min, animDuration.Max)
      local lifetime = projEnabled and rng:NextNumber(projLifetime.Min, projLifetime.Max)

      table.insert(
        promises,
        Promise.new(function(resolve)
          local cf = if parent:IsA("Attachment")
            then originCFrame * CFrame.new(Vector3.zero, Vector3.FromNormalId(emission_direction)).Rotation
            else drawFunc(nil, originCFrame, originSize, emission_direction, partial)

          local normal = Vector3.FromNormalId(emission_direction)

          local pitchAxis = normal:Cross(originCFrame.LookVector)

          if pitchAxis.Magnitude < 0.001 then
            pitchAxis = normal:Cross(originCFrame.UpVector)
          end

          local spread = CFrame.fromAxisAngle(normal, math.rad(rng:NextNumber(-spreadAngle.x, spreadAngle.x)))
            * CFrame.fromAxisAngle(pitchAxis, math.rad(rng:NextNumber(-spreadAngle.y, spreadAngle.y)))

          cf *= spread

          if face == "Inward" or (face == "InAndOut" and rng:NextInteger(0, 1) == 1) then
            cf *= CFrame.fromOrientation(0, math.pi, 0)
          end

          if endPoint and mirror and (cf.Position - endPoint.WorldPosition).Unit:Dot(cf.RightVector) >= 0 then
            local rot = mirrorRot * utility.DEG_TO_RAD
            cf *= CFrame.fromOrientation(rot.x, rot.y, rot.z)
          end

          local bezier = bezier

          if endPoint then
            local pts = {}

            for i, pt in points do
              table.insert(
                pts,
                if i == (#points - 1)
                  then endT1 and endT1.WorldPosition or endPoint.WorldPosition
                  else if i == #points then endPoint.WorldPosition else cf * (pt - points[1])
              )
            end

            bezier = Bezier.new(pts)
          end

          local function getPos(alpha: number)
            local p = animArcSpace and bezier:getPositionArcSpace(alpha) or bezier:getPosition(alpha)

            if endPoint then
              return p
            else
              return cf * (p - points[1])
            end
          end

          local cacheId = HttpService:GenerateGUID(false)

          if not part_cache then
            resolve()
            return
          end

          local objAbstr = part_cache:get(cacheId)
          objAbstr.CFrame = CFrame.new(getPos(0))

          local obj = objAbstr._getReal()

          utility.copyProperties(refObj, obj, utility.COPY_PART_PROPERTIES)
          utility.copyProperties(refObj, obj, utility.COPY_EXTENDED_PART_PROPERTIES)

          do
            local clone = refObj:Clone()

            for _, child in clone:GetChildren() do
              child.Parent = obj
            end

            clone:Destroy()
          end

          local emitOnFinish = obj:FindFirstChild("EmitOnFinish")

          if emitOnFinish then
            emitOnFinish.Parent = nil
            table.insert(scope, emitOnFinish)
          end

          if shared.vfx and #obj:GetChildren() ~= 0 then
            local env = shared.vfx.emit(obj)
            table.insert(promises, env.Finished)
          end

          table.insert(scope, function()
            if part_cache then
              part_cache:free(cacheId)
            end
          end)

          local lastPos = Vector3.zero
          local lastVelocity = Vector3.zero

          local finished = false

          local function onFinish()
            if finished then
              return
            end

            finished = true

            local children = emitOnFinish and emitOnFinish:GetChildren()

            if children and #children ~= 0 then
              for _, child in children do
                child.Parent = obj
              end

              local env = shared.vfx.emit(table.unpack(children))

              env.Finished:finally(function()
                resolve()
              end)
            else
              resolve()
            end
          end

          local function shapecast()
            if not hbEnabled then
              return
            end

            local result = workspace:GetPartsInPart(obj, params)

            if result[1] then
              return true
            end

            return false
          end

          local function getOriginCFrame()
            local ocf = originCFrame

            if parent:IsA("BasePart") then
              ocf = parent.CFrame
            elseif parent:IsA("Attachment") then
              ocf = parent.WorldCFrame
            end

            return ocf
          end

          local didHit = false
          local prevCF = CFrame.identity

          local currentSpeed = speedStart
          local currentRotSpeed = rotSpeedStart

          local currentRot = CFrame.fromOrientation(initRot.x, initRot.y, initRot.z)

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

          if rotSpeedStart ~= rotSpeedEnd then
            table.insert(
              scope,
              tween.fromParams(
                utility.getAttribute(ref, "RotSpeed_Curve", utility.default_bezier),
                duration,
                function(alpha, deltaTime)
                  currentRotSpeed = utility.lerp(rotSpeedStart, rotSpeedEnd, alpha)
                  return deltaTime * (ref:GetAttribute("SpeedOverride") or currentSpeed)
                end,
                speedTween
              )
            )
          end

          table.insert(
            scope,
            tween.fromParams(
              utility.getAttribute(ref, "Easing_Curve", utility.linear_bezier),
              duration,
              function(alpha, deltaTime, elapsed)
                local pos1 = getPos(alpha)

                local newCF = CFrame.new(pos1)

                if animFacePath then
                  local pos2 = getPos(math.clamp((elapsed + (1 / 60)) / duration, 0, 1))

                  if pos1 ~= pos2 then
                    newCF = CFrame.lookAt(pos1, pos2)
                  else
                    newCF *= prevCF.Rotation
                  end
                end

                local add = initRot:Sign() * currentRotSpeed * utility.DEG_TO_RAD * deltaTime
                currentRot *= CFrame.fromOrientation(add.x, add.y, add.z)

                -- save current cframe before applying rotation, otherwise
                -- the new rotation will stack on top of the previous rotation
                prevCF = newCF

                newCF *= currentRot

                if sync then
                  objAbstr.CFrame = getOriginCFrame() * originCFrame:ToObjectSpace(newCF)
                else
                  objAbstr.CFrame = newCF
                end

                lastVelocity = (pos1 - lastPos) / deltaTime
                lastPos = pos1

                local hit = shapecast()

                if hit then
                  onFinish()
                  didHit = true
                  return nil
                end

                local speed = ref:GetAttribute("SpeedOverride") or currentSpeed

                currentSpeed = speed

                if
                  speed == 0
                  and (if speedTween then not speedTween.Connected else not ref:GetAttribute("SpeedTweening"))
                then
                  return nil
                end

                if (projEnabled and alpha * duration < lifetime) or not projEnabled then
                  return deltaTime * speed
                else
                  onFinish()
                  return nil
                end
              end,
              speedTween,
              function(organic)
                if not projEnabled or didHit then
                  if organic then
                    onFinish()
                  end

                  return
                end

                local dir = if projMatchEnd and endPoint then endPoint.WorldCFrame.LookVector else lastVelocity.Unit

                if dir ~= dir then
                  dir = Vector3.zero
                end

                lastVelocity = dir * projSpeed

                local projectileOrigin = obj.Position
                local originCFrameAtProjectileInit = getOriginCFrame()

                tween.timer(lifetime, function(deltaTime, elapsed)
                  if sync then
                    objAbstr.CFrame = getOriginCFrame()
                      * originCFrameAtProjectileInit:ToObjectSpace(
                        CFrame.new(projectileOrigin + lastVelocity * elapsed)
                      )
                  else
                    objAbstr.CFrame = CFrame.new(projectileOrigin + lastVelocity * elapsed) * obj.CFrame.Rotation
                  end

                  local hit = shapecast()

                  if hit then
                    onFinish()
                    didHit = true
                    return nil
                  end

                  local speed = ref:GetAttribute("SpeedOverride") or currentSpeed

                  currentSpeed = speed

                  return if speed > 0
                      or (
                        elapsed > 0 and if speedTween then speedTween.Connected else ref:GetAttribute("SpeedTweening")
                      )
                    then deltaTime * speed
                    else nil
                end, speedTween, scope, utility.RENDER_PRIORITY + scope.depth)

                if not didHit then
                  onFinish()
                end
              end,
              true, -- start at zero, important for facepath to work on short durations
              utility.RENDER_PRIORITY + scope.depth
            )
          )
        end)
      )
    end

    Promise.all(promises):await()

    task.wait(destroyDelay)
  end
end

return bezier
