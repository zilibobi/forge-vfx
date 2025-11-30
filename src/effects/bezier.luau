--!nolint LocalShadow
local RunService = game:GetService("RunService")

local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")
local bezier_common = require("@mod/bezier_common")

local Bezier = require("@obj/Bezier")
local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

local bezier = {}

local part_cache: ObjectCache.ObjectCache?

function bezier.init(cache)
  part_cache = cache
end

function bezier.deinit()
  part_cache = nil
end

local function readBezierAttributes(ref: Attachment)
  return {
    -- animation
    facePath = utility.getAttribute(ref, "FacePath", false),
    arcSpace = utility.getAttribute(ref, "ArcSpace", false),

    -- rotation
    rotSpeedStart = utility.getRangeAttribute(ref, "RotSpeed_Start", NumberRange.new(0, 0)),
    rotSpeedEnd = utility.getRangeAttribute(ref, "RotSpeed_End", NumberRange.new(0, 0)),
    minInitRot = utility.getAttribute(ref, "MinInitRot", vector.zero),
    maxInitRot = utility.getAttribute(ref, "MaxInitRot", vector.zero),
  }
end

function bezier.emit(ref: Attachment, refObj: Part, scope: types.scope, mustEmit: boolean?)
  local root = ref:FindFirstChild("Points")

  if not root or not root:IsA("Attachment") or not part_cache then
    return
  end

  local common = bezier_common.readCommonAttributes(ref)
  local attrs = readBezierAttributes(ref)

  local drawFunc = bezier_common.drawFuncMap[common.shapeType]
    and bezier_common.drawFuncMap[common.shapeType][common.shapeStyle]

  if not drawFunc then
    return
  end

  local useDuration = common.emitDuration > 0

  task.wait(common.emitDelay)

  if useDuration and not mustEmit then
    ref:SetAttribute("Enabled", true)

    if common.speedStart ~= common.speedEnd then
      ref:SetAttribute("SpeedTweening", true)

      table.insert(
        scope,
        tween.fromParams(
          utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
          utility.getAttribute(ref, "Speed_Duration", 0.1),
          function(alpha, deltaTime)
            ref:SetAttribute("SpeedOverride", utility.lerp(common.speedStart, common.speedEnd, alpha))
            return deltaTime
          end,
          nil,
          function()
            ref:SetAttribute("SpeedTweening", nil)
          end
        )
      )
    end

    task.wait(common.emitDuration)

    ref:SetAttribute("Enabled", false)
    ref:SetAttribute("SpeedOverride", nil)

    return
  end

  if common.emitCount <= 0 then
    return
  end

  local parent = bezier_common.validateParent(ref)

  if not parent then
    return
  end

  local originSize, originCFrame = bezier_common.getOriginInfo(parent)

  if not originCFrame then
    return
  end

  local endPoint, endT1 = bezier_common.findEndAttachments(ref)
  local points = utility.getBezierPoints(root)

  local rng = Random.new()
  local baseBezier = not endPoint and Bezier.new(points)

  -- Hitbox params
  local hitboxParams = bezier_common.createHitboxParams({
    enabled = common.hitboxEnabled,
    collisionGroup = common.hitboxCollisionGroup,
    filterTag = common.hitboxFilterTag,
    filterType = common.hitboxFilterType,
    ignoreCanCollide = common.hitboxIgnoreCanCollide,
  }, parent, root)

  local promises = {}

  for _ = 1, common.emitCount do
    local rotSpeedStart = rng:NextNumber(attrs.rotSpeedStart.Min, attrs.rotSpeedStart.Max)
    local rotSpeedEnd = rng:NextNumber(attrs.rotSpeedEnd.Min, attrs.rotSpeedEnd.Max)

    local initRot = vector.create(
      rng:NextNumber(attrs.minInitRot.x, attrs.maxInitRot.x),
      rng:NextNumber(attrs.minInitRot.y, attrs.maxInitRot.y),
      rng:NextNumber(attrs.minInitRot.z, attrs.maxInitRot.z)
    )

    local duration = rng:NextNumber(common.duration.Min, common.duration.Max)
    local lifetime = common.projectileEnabled
      and rng:NextNumber(common.projectileLifetime.Min, common.projectileLifetime.Max)

    table.insert(
      promises,
      Promise.new(function(resolve)
        -- Calculate emission CFrame
        local cf = bezier_common.calculateEmissionCFrame(originCFrame, originSize, {
          face = common.face,
          spreadAngle = common.spreadAngle,
          mirror = common.mirror,
          mirrorRot = common.mirrorRot,
          partial = common.partial,
          emissionDirection = common.emissionDirection,
        }, drawFunc, rng, endPoint, parent:IsA("Attachment"))

        -- create bezier
        local pathBezier = baseBezier or bezier_common.createBezierWithEndpoint(points, cf, endPoint, endT1)
        local getPos = bezier_common.createPosGetter(pathBezier, points, cf, endPoint, attrs.arcSpace)

        -- get part from cache
        local cacheId = utility.getRandomId()

        if not part_cache then
          resolve()
          return
        end

        local objAbstr = part_cache:get(cacheId)
        objAbstr.CFrame = CFrame.new(getPos(0))

        local obj = objAbstr._getReal()

        utility.copyProperties(refObj, obj, utility.COPY_PART_PROPERTIES)
        utility.copyProperties(refObj, obj, utility.COPY_EXTENDED_PART_PROPERTIES)

        -- clone children from reference
        do
          local clone = refObj:Clone()
          for _, child in clone:GetChildren() do
            child.Parent = obj
          end
          clone:Destroy()
        end

        local emitOnFinish = scope.effects.prepareEmitOnFinish(obj, scope)
        local env = scope.effects.emitNested(obj, scope.depth + 1)

        table.insert(promises, env.Finished)

        table.insert(scope, function()
          if part_cache then
            part_cache:free(cacheId)
          end
        end)

        -- animation state
        local lastPos = Vector3.zero
        local lastVelocity = Vector3.zero

        local didHit = false
        local finished = false

        local prevCF = CFrame.identity
        local currentSpeed = common.speedStart

        local currentRot = CFrame.fromOrientation(initRot.x, initRot.y, initRot.z)
        local currentRotSpeed = rotSpeedStart

        local function onFinish()
          if finished then
            return
          end

          if common.syncPosition then
            local initOrigin = bezier_common.getCurrentOriginCFrame(parent, originCFrame)
            local initPartPos = objAbstr.CFrame

            local function updatePos()
              objAbstr.CFrame = bezier_common.getCurrentOriginCFrame(parent, originCFrame)
                * initOrigin:ToObjectSpace(initPartPos)
            end

            local id = utility.getRandomId()

            RunService:BindToRenderStep(id, utility.RENDER_PRIORITY + scope.depth, updatePos)

            table.insert(scope, function()
              RunService:UnbindFromRenderStep(id)
            end)
          end

          finished = true

          local finishEnv = scope.effects.emitOnFinish(emitOnFinish, obj, scope.depth + 1)
          finishEnv.Finished:finally(function()
            resolve()
          end)
        end

        local function shapecast()
          if not common.hitboxEnabled then
            return false
          end

          local result = workspace:GetPartsInPart(obj, hitboxParams)
          return result[1] ~= nil
        end

        -- Speed tween
        local speedTween

        if common.speedStart ~= common.speedEnd and not ref:GetAttribute("SpeedOverride") then
          speedTween = tween.fromParams(
            utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
            utility.getAttribute(ref, "Speed_Duration", 0.1),
            function(alpha, deltaTime)
              currentSpeed = utility.lerp(common.speedStart, common.speedEnd, alpha)
              return deltaTime
            end
          )

          table.insert(scope, speedTween)
        end

        -- Rotation speed tween
        bezier_common.createPropertyTween(scope, ref, "RotSpeed", duration, rotSpeedStart, rotSpeedEnd, function(v)
          currentRotSpeed = v
        end, function()
          return ref:GetAttribute("SpeedOverride") or currentSpeed
        end, speedTween)

        -- main animation
        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(ref, "Easing_Curve", utility.linear_bezier),
            duration,
            function(alpha, deltaTime, elapsed)
              local pos1 = getPos(alpha)
              local newCF = CFrame.new(pos1)

              if attrs.facePath then
                local pos2 = getPos(math.clamp((elapsed + (1 / 60)) / duration, 0, 1))

                if pos1 ~= pos2 then
                  newCF = CFrame.lookAt(pos1, pos2)
                else
                  newCF *= prevCF.Rotation
                end
              end

              local add = initRot:Sign() * currentRotSpeed * utility.DEG_TO_RAD * deltaTime
              currentRot *= CFrame.fromOrientation(add.x, add.y, add.z)

              -- save current cframe before applying rotation
              prevCF = newCF
              newCF *= currentRot

              if common.syncPosition then
                objAbstr.CFrame = bezier_common.getCurrentOriginCFrame(parent, originCFrame)
                  * originCFrame:ToObjectSpace(newCF)
              else
                objAbstr.CFrame = newCF
              end

              lastVelocity = (pos1 - lastPos) / deltaTime
              lastPos = pos1

              if shapecast() then
                onFinish()
                didHit = true
                return nil
              end

              local speed = ref:GetAttribute("SpeedOverride") or currentSpeed
              currentSpeed = speed

              if
                speed == 0 and (if speedTween then not speedTween.Connected else not ref:GetAttribute("SpeedTweening"))
              then
                return nil
              end

              if (common.projectileEnabled and alpha * duration < lifetime) or not common.projectileEnabled then
                return deltaTime * speed
              else
                onFinish()
                return nil
              end
            end,
            speedTween,
            function(organic)
              if not common.projectileEnabled or didHit then
                if organic then
                  onFinish()
                end
                return
              end

              -- Projectile mode
              local dir = if common.projectileMatchEnd and endPoint
                then endPoint.WorldCFrame.LookVector
                else lastVelocity.Unit

              if dir ~= dir then
                dir = Vector3.zero
              end

              lastVelocity = dir * common.projectileSpeed

              local projectileOrigin = obj.Position
              local originCFrameAtProjectileInit = bezier_common.getCurrentOriginCFrame(parent, originCFrame)

              tween.timer(lifetime, function(deltaTime, elapsed)
                if common.syncPosition then
                  objAbstr.CFrame = bezier_common.getCurrentOriginCFrame(parent, originCFrame)
                    * originCFrameAtProjectileInit:ToObjectSpace(CFrame.new(projectileOrigin + lastVelocity * elapsed))
                else
                  objAbstr.CFrame = CFrame.new(projectileOrigin + lastVelocity * elapsed) * obj.CFrame.Rotation
                end

                if shapecast() then
                  onFinish()
                  didHit = true
                  return nil
                end

                local speed = ref:GetAttribute("SpeedOverride") or currentSpeed
                currentSpeed = speed

                return if speed > 0
                    or (elapsed > 0 and if speedTween then speedTween.Connected else ref:GetAttribute("SpeedTweening"))
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

  task.wait(common.destroyDelay)
end

return bezier
