--!nolint LocalShadow
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")
local bezier_common = require("@mod/bezier_common")

local Bezier = require("@obj/Bezier")
local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

local lightning = {}

local part_cache: ObjectCache.ObjectCache?

function lightning.init(cache)
  part_cache = cache
end

function lightning.deinit()
  part_cache = nil
end

local function readLightningAttributes(ref: Attachment)
  return {
    -- lightning
    segments = math.max(utility.getAttribute(ref, "Segments", 8), 2),
    jaggedness = utility.getRangeAttribute(ref, "Jaggedness", NumberRange.new(0.3, 0.5), NumberRange.new(0, 10)),
    offsetScale = utility.getAttribute(ref, "OffsetScale", 1),
    refreshRate = utility.getAttribute(ref, "RefreshRate", 15),
    independentSegments = utility.getAttribute(ref, "IndependentSegments", false),
    refreshDuringDissipate = utility.getAttribute(ref, "RefreshDuringDissipate", false),
    nestedEffectMode = utility.getEnumAttribute(ref, "NestedEffectMode", "None", { "None", "All", "Head", "Tail" }),

    -- color
    colorSequence = utility.getAttribute(ref, "Color", ColorSequence.new(Color3.new(1, 1, 1))),
    colorEasingData = utility.getAttribute(ref, "Color_Easing", utility.linear_bezier),
    colorDuration = utility.getAttribute(ref, "Color_Duration", 1),

    -- transparency
    transparencyStart = utility.getAttribute(ref, "Transparency_Start", 0),
    transparencyEnd = utility.getAttribute(ref, "Transparency_End", 0),

    -- fill
    fillColorSequence = utility.getAttribute(ref, "FillColor", ColorSequence.new(Color3.new(1, 1, 1))),
    fillColorEasingData = utility.getAttribute(ref, "FillColor_Easing", utility.linear_bezier),
    fillColorDuration = utility.getAttribute(ref, "FillColor_Duration", 1),
    fillTransparencyStart = utility.getAttribute(ref, "FillTransparency_Start", 1),
    fillTransparencyEnd = utility.getAttribute(ref, "FillTransparency_End", 1),
    fillDepthMode = utility.getEnumAttribute(ref, "FillDepthMode", "Occluded", { "AlwaysOnTop", "Occluded" }),

    -- fade-in
    fadeInStart = utility.getAttribute(ref, "Fade_In_Start", 1),
    fadeInDuration = utility.getAttribute(ref, "Fade_In_Duration", 0),
    fadeInCurveData = utility.getAttribute(ref, "Fade_In_Curve", utility.default_bezier),

    -- fade-out
    fadeOutEnd = utility.getAttribute(ref, "Fade_Out_End", 1),
    fadeOutDuration = utility.getAttribute(ref, "Fade_Out_Duration", 0),
    fadeOutCurveData = utility.getAttribute(ref, "Fade_Out_Curve", utility.default_bezier),

    -- length
    lengthStart = utility.getAttribute(ref, "Length_Start", 1),
    lengthEnd = utility.getAttribute(ref, "Length_End", 1),

    -- dissipation
    dissipateMode = utility.getEnumAttribute(ref, "DissipateMode", "None", { "None", "Retract", "Scale" }),
    dissipateDuration = utility.getAttribute(ref, "Dissipate_Duration", 0.5),
    dissipateCurveData = utility.getAttribute(ref, "Dissipate_Curve", utility.default_bezier),

    -- width
    widthStart = utility.getAttribute(ref, "Width_Start", 0.3),
    widthEnd = utility.getAttribute(ref, "Width_End", 0.1),
  }
end

local function createSegmentStates(count: number)
  local states = {}

  for j = 1, count do
    states[j] = {
      birthTime = nil,
      initialWidth = nil,
      initialTransparency = nil,
      wasVisible = false,
    }
  end

  return states
end

local function computeJaggedOffset(
  rng: Random,
  jaggedness: NumberRange,
  offsetScale: number,
  segLength: number,
  right: Vector3,
  up: Vector3
)
  local jaggedAmount = rng:NextNumber(jaggedness.Min, jaggedness.Max)
  local maxOffset = segLength * 0.8

  local offsetMag = math.min(jaggedAmount * offsetScale * segLength, maxOffset)
  local angle = rng:NextNumber(0, math.pi * 2)

  return (right * math.cos(angle) + up * math.sin(angle)) * offsetMag
end

local function generateLightningPoints(
  rng: Random,
  segments: number,
  getPos: (number) -> Vector3,
  jaggedness: NumberRange,
  offsetScale: number
)
  local points = table.create(segments + 1)
  local invSegments = 1 / segments

  points[1] = getPos(0)

  local prevPos = points[1]

  for j = 1, segments - 1 do
    local t = j * invSegments
    local pos = getPos(t)

    local nextT = math.min(t + 0.01, 1)
    local tangent = getPos(nextT) - pos

    tangent = if tangent.Magnitude > 0.001 then tangent.Unit else Vector3.yAxis

    local right, up = bezier_common.getPerpendicularVectors(tangent)
    local segmentLength = (pos - prevPos).Magnitude

    local offset = computeJaggedOffset(rng, jaggedness, offsetScale, segmentLength, right, up)

    pos = pos + offset
    prevPos = pos

    points[j + 1] = pos
  end

  points[segments + 1] = getPos(1)

  return points
end

local function generateProjectilePoints(
  rng: Random,
  segments: number,
  tailPos: Vector3,
  headPos: Vector3,
  jaggedness: NumberRange,
  offsetScale: number,
  fallbackDir: Vector3
)
  local points = table.create(segments + 1)
  local invSegments = 1 / segments

  local pathDir = headPos - tailPos
  local pathLength = pathDir.Magnitude

  local tangent = if pathLength > 0.001 then pathDir / pathLength else fallbackDir

  local right, up = bezier_common.getPerpendicularVectors(tangent)
  local segLength = pathLength * invSegments

  points[1] = tailPos

  for j = 1, segments - 1 do
    local t = j * invSegments

    local pos = tailPos:Lerp(headPos, t)
    local offset = computeJaggedOffset(rng, jaggedness, offsetScale, segLength, right, up)

    points[j + 1] = pos + offset
  end

  points[segments + 1] = headPos

  return points
end

export type TransitionState = {
  curvedTailT: number,
  curvedLengthT: number,
  boltLength: number,
  transitionBuffer: number,
  distanceTraveled: number,
  jaggedOffsets: { Vector3 }?,
}

local function getBlendedPosition(
  t: number,
  getPos: (number) -> Vector3,
  straightTailPos: Vector3,
  straightHeadPos: Vector3,
  state: TransitionState
): Vector3
  -- per-point transition alpha
  local pointExitDistance = (1 - t) * state.boltLength
  local pointOvershoot = state.distanceTraveled - pointExitDistance
  local pointAlpha = math.clamp(pointOvershoot / state.transitionBuffer, 0, 1)

  -- curved position on sliding bezier
  local bezierProgress = math.min(state.distanceTraveled / state.boltLength, 1) * state.curvedLengthT
  local bezierT = math.min(1, state.curvedTailT + t * state.curvedLengthT + bezierProgress)

  local curvedPos = getPos(bezierT)

  -- straight position
  local straightPos = straightTailPos:Lerp(straightHeadPos, t)

  return curvedPos:Lerp(straightPos, pointAlpha)
end

local function generateTransitionPoints(
  rng: Random,
  segments: number,
  getPos: (number) -> Vector3,
  straightTailPos: Vector3,
  straightHeadPos: Vector3,
  jaggedness: NumberRange,
  offsetScale: number,
  fallbackDir: Vector3,
  state: TransitionState
)
  local points = table.create(segments + 1)
  local offsets = table.create(segments + 1)

  local invSegments = 1 / segments

  local straightDir = straightHeadPos - straightTailPos
  local straightLength = straightDir.Magnitude

  local tangent = if straightLength > 0.001 then straightDir / straightLength else fallbackDir
  local right, up = bezier_common.getPerpendicularVectors(tangent)

  local segLength = straightLength * invSegments

  for j = 0, segments do
    local t = j * invSegments
    local basePos = getBlendedPosition(t, getPos, straightTailPos, straightHeadPos, state)

    if j == 0 or j == segments then
      points[j + 1] = basePos
      offsets[j + 1] = Vector3.zero
    else
      local offset = computeJaggedOffset(rng, jaggedness, offsetScale, segLength, right, up)

      points[j + 1] = basePos + offset
      offsets[j + 1] = offset
    end
  end

  return points, offsets
end

local function updateTransitionPoints(
  segments: number,
  getPos: (number) -> Vector3,
  straightTailPos: Vector3,
  straightHeadPos: Vector3,
  state: TransitionState
): { Vector3 }
  local points = table.create(segments + 1)

  local invSegments = 1 / segments
  local offsets = state.jaggedOffsets

  for j = 0, segments do
    local t = j * invSegments
    local basePos = getBlendedPosition(t, getPos, straightTailPos, straightHeadPos, state)

    points[j + 1] = basePos + (if offsets then offsets[j + 1] else Vector3.zero)
  end

  return points
end

local function isTransitionComplete(state: TransitionState): boolean
  return state.distanceTraveled >= state.boltLength + state.transitionBuffer
end

function lightning.emit(ref: Attachment, refObj: Part, scope: types.scope, mustEmit: boolean?)
  local root = ref:FindFirstChild("Points")

  if not root or not root:IsA("Attachment") or not part_cache then
    return
  end

  local common = bezier_common.readCommonAttributes(ref)
  local attrs = readLightningAttributes(ref)

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

  local colorEasingBezier = Bezier.new(utility.deserializePath(attrs.colorEasingData), 0)
  local fillColorEasingBezier = Bezier.new(utility.deserializePath(attrs.fillColorEasingData), 0)

  local fadeInEasingBezier = Bezier.new(utility.deserializePath(attrs.fadeInCurveData), 0)
  local fadeOutEasingBezier = Bezier.new(utility.deserializePath(attrs.fadeOutCurveData), 0)

  local hitboxParams = bezier_common.createHitboxParams({
    enabled = common.hitboxEnabled,
    collisionGroup = common.hitboxCollisionGroup,
    filterTag = common.hitboxFilterTag,
    filterType = common.hitboxFilterType,
    ignoreCanCollide = common.hitboxIgnoreCanCollide,
  }, parent, root)

  local promises = {}

  for _ = 1, common.emitCount do
    local duration = rng:NextNumber(common.duration.Min, common.duration.Max)
    local lifetime = common.projectileEnabled
      and rng:NextNumber(common.projectileLifetime.Min, common.projectileLifetime.Max)

    table.insert(
      promises,
      Promise.new(function(resolve)
        local cf = bezier_common.calculateEmissionCFrame(originCFrame, originSize, {
          face = common.face,
          spreadAngle = common.spreadAngle,
          mirror = common.mirror,
          mirrorRot = common.mirrorRot,
          partial = common.partial,
          emissionDirection = common.emissionDirection,
        }, drawFunc, rng, endPoint, parent:IsA("Attachment"))

        local bezier = baseBezier or bezier_common.createBezierWithEndpoint(points, cf, endPoint, endT1)
        local getPos = bezier_common.createPosGetter(bezier, points, cf, endPoint, true)

        -- create segment parts
        local segmentRealParts = table.create(attrs.segments)
        local segmentCacheIds = table.create(attrs.segments)

        local segmentState = createSegmentStates(attrs.segments)

        local invSegments = 1 / attrs.segments
        local segmentBounds = table.create(attrs.segments)

        for j = 1, attrs.segments do
          segmentBounds[j] = {
            start = (j - 1) * invSegments,
            finish = j * invSegments,
          }
        end

        if not part_cache then
          resolve()
          return
        end

        -- create a highlight container if needed
        local useHighlight = attrs.fillTransparencyStart < 1 or attrs.fillTransparencyEnd < 1

        local highlight: Highlight?
        local containerModel: Model?

        if useHighlight then
          local container = Instance.new("Model")
          container.Name = "LightningContainer"
          container.Parent = workspace.Terrain
          containerModel = container

          local hl = Instance.new("Highlight")
          hl.Adornee = container
          hl.FillColor = bezier_common.getColorWithEasingOklab(attrs.fillColorSequence, 0, fillColorEasingBezier)
          hl.FillTransparency = attrs.fillTransparencyStart
          hl.OutlineTransparency = 1
          hl.DepthMode = Enum.HighlightDepthMode[attrs.fillDepthMode]
          hl.Parent = container

          highlight = hl
        end

        -- determine which segments get nested effects
        local function shouldEmitNested(segmentIndex: number): boolean
          local mode = attrs.nestedEffectMode

          if mode == "All" then
            return true
          elseif mode == "Head" then
            return segmentIndex == attrs.segments
          elseif mode == "Tail" then
            return segmentIndex == 1
          end

          return false
        end

        -- create segment parts
        for j = 1, attrs.segments do
          local cacheId = utility.getRandomId()

          local objAbstr = part_cache:get(cacheId)
          local obj = objAbstr._getReal()

          utility.copyProperties(refObj, obj, utility.COPY_PART_PROPERTIES)

          obj.Size = Vector3.new(attrs.widthStart, attrs.widthStart, 1)

          obj.Anchored = true
          obj.CanQuery = false
          obj.CanTouch = false
          obj.CanCollide = false

          if useHighlight and containerModel then
            obj.Parent = containerModel
          end

          if shouldEmitNested(j) then
            local clone = refObj:Clone()

            for _, child in clone:GetChildren() do
              child.Parent = obj
            end

            clone:Destroy()

            local env = scope.effects.emitNested(obj, scope.depth + 1)
            table.insert(promises, env.Finished)
          end

          segmentRealParts[j] = obj
          segmentCacheIds[j] = cacheId
        end

        -- cleanup
        table.insert(scope, function()
          if part_cache then
            for j = 1, attrs.segments do
              part_cache:free(segmentCacheIds[j])
            end

            if containerModel then
              containerModel:Destroy()
            end
          end
        end)

        local effectContainer = containerModel or refObj
        local emitOnFinish = scope.effects.prepareEmitOnFinish(refObj, scope)

        -- animation state
        local didHit = false
        local finished = false

        local currentSpeed = common.speedStart
        local currentWidth = attrs.widthStart
        local currentLength = attrs.lengthStart
        local currentTransparency = attrs.transparencyStart
        local currentFillTransparency = attrs.fillTransparencyStart

        local currentColorAlpha = 0
        local currentFillColorAlpha = 0

        local lastRefreshTime = 0

        local lightningPoints =
          generateLightningPoints(rng, attrs.segments, getPos, attrs.jaggedness, attrs.offsetScale)

        local lastVelocity = Vector3.zero
        local lastHeadPos = Vector3.zero

        local effectStartTime = os.clock()

        local isDissipating = false

        local dissipateProgress = 0
        local dissipateStartTail = 0

        local dissipateStartWidth = attrs.widthStart
        local currentOriginCFrame = originCFrame

        local projectileDir: Vector3?
        local projectileHeadPos: Vector3?
        local projectileTailPos: Vector3?

        local transitionState: TransitionState?

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

        local function getEffectiveSpeed()
          return ref:GetAttribute("SpeedOverride") or currentSpeed
        end

        local function isSpeedTweening()
          return if speedTween then speedTween.Connected else ref:GetAttribute("SpeedTweening")
        end

        local function getSpeedDelta(deltaTime: number, allowZeroSpeed: boolean?)
          local speed = getEffectiveSpeed()
          currentSpeed = speed

          if speed > 0 then
            return deltaTime * speed
          elseif allowZeroSpeed or isSpeedTweening() then
            return deltaTime * speed
          else
            return nil
          end
        end

        local function onFinish()
          if finished then
            return
          end

          finished = true

          local finishEnv = scope.effects.emitOnFinish(emitOnFinish, effectContainer, scope.depth + 1)

          finishEnv.Finished:finally(function()
            resolve()
          end)
        end

        local function shapecast()
          if not common.hitboxEnabled then
            return false
          end

          local headSegment = segmentRealParts[attrs.segments]

          if headSegment and headSegment.Transparency < 1 then
            local result = workspace:GetPartsInPart(headSegment, hitboxParams)

            if result[1] then
              return true
            end
          end

          return false
        end

        -- refresh lightning points based on current state
        local function refreshPoints()
          if projectileHeadPos and projectileTailPos and projectileDir then
            if transitionState and not isTransitionComplete(transitionState) then
              lightningPoints, transitionState.jaggedOffsets = generateTransitionPoints(
                rng,
                attrs.segments,
                getPos,
                projectileTailPos,
                projectileHeadPos,
                attrs.jaggedness,
                attrs.offsetScale,
                projectileDir,
                transitionState
              )
            else
              lightningPoints = generateProjectilePoints(
                rng,
                attrs.segments,
                projectileTailPos,
                projectileHeadPos,
                attrs.jaggedness,
                attrs.offsetScale,
                projectileDir
              )

              if transitionState then
                transitionState.jaggedOffsets = nil
              end
            end
          else
            lightningPoints = generateLightningPoints(rng, attrs.segments, getPos, attrs.jaggedness, attrs.offsetScale)
          end
        end

        -- update points between refreshes during transition
        local function updatePointsBetweenRefreshes(deltaTime: number)
          if transitionState and not isTransitionComplete(transitionState) then
            if transitionState.jaggedOffsets then
              lightningPoints = updateTransitionPoints(
                attrs.segments,
                getPos,
                projectileTailPos :: Vector3,
                projectileHeadPos :: Vector3,
                transitionState
              )
            else
              -- generate offsets on first frame
              lightningPoints, transitionState.jaggedOffsets = generateTransitionPoints(
                rng,
                attrs.segments,
                getPos,
                projectileTailPos :: Vector3,
                projectileHeadPos :: Vector3,
                attrs.jaggedness,
                attrs.offsetScale,
                projectileDir :: Vector3,
                transitionState
              )
            end
          else
            -- fully transitioned, move points along the projectile direction
            local offset = projectileDir * common.projectileSpeed * deltaTime

            for j = 1, #lightningPoints do
              lightningPoints[j] = lightningPoints[j] + offset
            end
          end
        end

        local function updateSegments(
          headAlpha: number,
          tailAlphaOverride: number?,
          deltaTime: number,
          allowRefresh: boolean?,
          widthOverride: number?
        )
          local currentTime = os.clock()

          local tailAlpha = tailAlphaOverride or math.max(0, headAlpha - currentLength)
          local effectiveWidth = widthOverride or currentWidth

          -- refresh lightning points
          if allowRefresh ~= false and attrs.refreshRate > 0 then
            local refreshInterval = 1 / attrs.refreshRate
            lastRefreshTime += deltaTime

            if lastRefreshTime >= refreshInterval then
              refreshPoints()
              lastRefreshTime = 0
            end
          end

          -- update each segment
          for j = 1, attrs.segments do
            local state = segmentState[j]

            local bounds = segmentBounds[j]
            local segment = segmentRealParts[j]

            local segStart = bounds.start
            local segEnd = bounds.finish

            local isVisible = segEnd > tailAlpha and segStart < headAlpha

            if not isVisible then
              segment.Transparency = 1

              if state.wasVisible then
                state.wasVisible = false
                state.birthTime = nil
                state.initialWidth = nil
                state.initialTransparency = nil
              end
            else
              if not state.wasVisible then
                state.wasVisible = true
                state.birthTime = currentTime
                state.initialWidth = currentWidth
                state.initialTransparency = currentTransparency
              end

              -- color
              segment.Color =
                bezier_common.getColorWithEasingOklab(attrs.colorSequence, currentColorAlpha, colorEasingBezier)

              -- transparency with fade in/out
              local baseTransparency = if attrs.independentSegments and state.initialTransparency
                then state.initialTransparency
                else currentTransparency

              local effectAge = currentTime - effectStartTime

              local fadeInAlpha = if attrs.fadeInDuration > 0
                then math.clamp(effectAge / attrs.fadeInDuration, 0, 1)
                else 1

              local fadeInEased = 1 - fadeInEasingBezier:getEase(fadeInAlpha).y
              local fadeInTransparency = utility.lerp(attrs.fadeInStart, baseTransparency, fadeInEased)

              local fadeOutTransparency = baseTransparency

              if isDissipating and attrs.fadeOutDuration > 0 then
                local fadeOutAlpha = math.clamp(dissipateProgress / attrs.fadeOutDuration, 0, 1)
                local fadeOutEased = 1 - fadeOutEasingBezier:getEase(fadeOutAlpha).y

                fadeOutTransparency = utility.lerp(baseTransparency, attrs.fadeOutEnd, fadeOutEased)
              end

              segment.Transparency = if fadeInAlpha < 1
                then fadeInTransparency
                elseif isDissipating then fadeOutTransparency
                else baseTransparency

              -- width
              local useWidth

              if widthOverride then
                local baseWidth = if attrs.independentSegments and state.initialWidth
                  then state.initialWidth
                  else currentWidth

                useWidth = baseWidth * (if currentWidth > 0 then widthOverride / currentWidth else 0)
              elseif attrs.independentSegments and state.initialWidth then
                useWidth = state.initialWidth
              else
                useWidth = effectiveWidth
              end

              -- geometry
              local p1 = lightningPoints[j]
              local p2 = lightningPoints[j + 1]

              if p1 and p2 then
                local clampedP1 = if segStart < tailAlpha
                  then p1:Lerp(p2, (tailAlpha - segStart) / (segEnd - segStart))
                  else p1

                local clampedP2 = if segEnd > headAlpha
                  then p1:Lerp(p2, (headAlpha - segStart) / (segEnd - segStart))
                  else p2

                local midpoint = (clampedP1 + clampedP2) / 2
                local length = (clampedP2 - clampedP1).Magnitude

                if length > 0.001 then
                  segment.Size = Vector3.new(useWidth, useWidth, length)
                  segment.CFrame = CFrame.lookAt(midpoint, clampedP2)
                end
              end
            end
          end

          -- update fill
          if highlight then
            highlight.FillColor = bezier_common.getColorWithEasingOklab(
              attrs.fillColorSequence,
              currentFillColorAlpha,
              fillColorEasingBezier
            )

            highlight.FillTransparency = currentFillTransparency
          end

          -- track velocity
          local currentHeadPos = getPos(math.min(headAlpha, 1))

          if deltaTime > 0 then
            lastVelocity = (currentHeadPos - lastHeadPos) / deltaTime
          end
          lastHeadPos = currentHeadPos
        end

        -- property tweens
        bezier_common.createPropertyTween(scope, ref, "Width", duration, attrs.widthStart, attrs.widthEnd, function(v)
          currentWidth = v
        end, getEffectiveSpeed, speedTween)

        bezier_common.createPropertyTween(
          scope,
          ref,
          "Transparency",
          duration,
          attrs.transparencyStart,
          attrs.transparencyEnd,
          function(v)
            currentTransparency = v
          end,
          getEffectiveSpeed,
          speedTween
        )

        bezier_common.createPropertyTween(
          scope,
          ref,
          "Length",
          duration,
          attrs.lengthStart,
          attrs.lengthEnd,
          function(v)
            currentLength = v
          end,
          getEffectiveSpeed,
          speedTween
        )

        if useHighlight then
          bezier_common.createPropertyTween(
            scope,
            ref,
            "FillTransparency",
            attrs.fillColorDuration,
            attrs.fillTransparencyStart,
            attrs.fillTransparencyEnd,
            function(v)
              currentFillTransparency = v
            end,
            getEffectiveSpeed,
            speedTween
          )
        end

        -- dissipation handler
        local function handleDissipation(
          startTail: number,
          startWidth: number,
          curveData: string,
          dissipationDuration: number,
          mode: string
        )
          isDissipating = true
          dissipateStartTail = startTail
          dissipateStartWidth = startWidth

          tween.fromParams(
            curveData,
            dissipationDuration,
            function(alpha, deltaTime, elapsed)
              dissipateProgress = elapsed

              if attrs.refreshDuringDissipate then
                currentColorAlpha = (currentColorAlpha + deltaTime / attrs.colorDuration) % 1
                currentFillColorAlpha = (currentFillColorAlpha + deltaTime / attrs.fillColorDuration) % 1
              end

              local tailOverride = if mode == "Retract" then utility.lerp(dissipateStartTail, 1, alpha) else nil
              local widthOverrideVal = if mode == "Scale" then utility.lerp(dissipateStartWidth, 0, alpha) else nil

              updateSegments(1, tailOverride, deltaTime, attrs.refreshDuringDissipate, widthOverrideVal)

              if shapecast() then
                onFinish()
                didHit = true
                return nil
              end

              return getSpeedDelta(deltaTime, true)
            end,
            speedTween,
            function()
              if not didHit then
                onFinish()
              end
            end,
            true,
            utility.RENDER_PRIORITY + scope.depth
          )
        end

        local function startDissipation()
          if attrs.dissipateMode ~= "None" then
            handleDissipation(
              math.max(0, 1 - currentLength),
              currentWidth,
              attrs.dissipateCurveData,
              attrs.dissipateDuration,
              attrs.dissipateMode
            )
          elseif attrs.fadeOutDuration > 0 then
            handleDissipation(0, currentWidth, attrs.fadeOutCurveData, attrs.fadeOutDuration, "None")
          else
            onFinish()
          end
        end

        -- main animation
        table.insert(
          scope,
          tween.fromParams(
            utility.getAttribute(ref, "Easing_Curve", utility.linear_bezier),
            duration,
            function(alpha, deltaTime, elapsed)
              currentColorAlpha = (currentColorAlpha + deltaTime / attrs.colorDuration) % 1
              currentFillColorAlpha = (currentFillColorAlpha + deltaTime / attrs.fillColorDuration) % 1

              if common.syncPosition then
                local newOrigin = bezier_common.getCurrentOriginCFrame(parent, currentOriginCFrame)
                local offset = newOrigin * currentOriginCFrame:Inverse()

                for j = 1, #lightningPoints do
                  lightningPoints[j] =
                    offset:PointToWorldSpace(currentOriginCFrame:PointToObjectSpace(lightningPoints[j]))
                end

                currentOriginCFrame = newOrigin
              end

              updateSegments(alpha, nil, deltaTime)

              if shapecast() then
                onFinish()
                didHit = true
                return nil
              end

              local speedDelta = getSpeedDelta(deltaTime)

              if speedDelta == nil then
                return nil
              end

              if (common.projectileEnabled and alpha * duration < lifetime) or not common.projectileEnabled then
                return speedDelta
              else
                onFinish()
                return nil
              end
            end,
            speedTween,
            function(organic)
              if didHit then
                if organic then
                  onFinish()
                end
                return
              end

              -- non-projectile mode
              if not common.projectileEnabled then
                if common.destroyDelay > 0 then
                  tween.fromParams(
                    utility.linear_bezier,
                    common.destroyDelay,
                    function(_, deltaTime)
                      currentColorAlpha = (currentColorAlpha + deltaTime / attrs.colorDuration) % 1
                      currentFillColorAlpha = (currentFillColorAlpha + deltaTime / attrs.fillColorDuration) % 1

                      updateSegments(1, nil, deltaTime, true)

                      if shapecast() then
                        onFinish()
                        didHit = true
                        return nil
                      end

                      return getSpeedDelta(deltaTime, true)
                    end,
                    speedTween,
                    function()
                      if not didHit then
                        startDissipation()
                      end
                    end,
                    true,
                    utility.RENDER_PRIORITY + scope.depth
                  )
                else
                  startDissipation()
                end

                return
              end

              -- projectile mode
              local dir = if common.projectileMatchEnd and endPoint
                then endPoint.WorldCFrame.LookVector
                else lastVelocity.Unit

              if dir ~= dir or dir.Magnitude < 0.001 then
                dir = Vector3.zAxis
              else
                dir = dir.Unit
              end

              local initialHeadPos = getPos(1)
              local initialTailPos = getPos(math.max(0, 1 - currentLength))

              local boltLength = (initialHeadPos - initialTailPos).Magnitude

              local curvedTailT = math.max(0, 1 - currentLength)
              local curvedLengthT = 1 - curvedTailT

              local transitionBuffer = boltLength * 0.3

              local state: TransitionState = {
                curvedTailT = curvedTailT,
                curvedLengthT = curvedLengthT,
                boltLength = boltLength,
                transitionBuffer = transitionBuffer,
                distanceTraveled = 0,
                jaggedOffsets = nil,
              }

              transitionState = state

              tween.timer(lifetime, function(deltaTime, elapsed)
                currentColorAlpha = (currentColorAlpha + deltaTime / attrs.colorDuration) % 1
                currentFillColorAlpha = (currentFillColorAlpha + deltaTime / attrs.fillColorDuration) % 1

                local distanceTraveled = elapsed * common.projectileSpeed
                state.distanceTraveled = distanceTraveled

                local currentHeadPos = initialHeadPos + dir * distanceTraveled
                local currentTailPos = currentHeadPos - dir * boltLength

                projectileHeadPos = currentHeadPos
                projectileTailPos = currentTailPos
                projectileDir = dir

                local shouldRefresh = attrs.refreshRate > 0

                if shouldRefresh then
                  lastRefreshTime += deltaTime

                  if lastRefreshTime >= 1 / attrs.refreshRate then
                    refreshPoints()
                    lastRefreshTime = 0
                  else
                    updatePointsBetweenRefreshes(deltaTime)
                  end
                else
                  updatePointsBetweenRefreshes(deltaTime)
                end

                updateSegments(1, nil, deltaTime, false)

                if shapecast() then
                  onFinish()
                  didHit = true
                  return nil
                end

                if elapsed >= lifetime then
                  return nil
                end

                return getSpeedDelta(deltaTime, true)
              end, speedTween, scope, utility.RENDER_PRIORITY + scope.depth)

              if not didHit then
                startDissipation()
              end
            end,
            true,
            utility.RENDER_PRIORITY + scope.depth
          )
        )
      end)
    )
  end

  Promise.all(promises):await()
end

return lightning
