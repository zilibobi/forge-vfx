local CollectionService = game:GetService("CollectionService")

local attr = require("@mod/attributes")
local tween = require("@mod/tween")
local types = require("@root/types")
local logger = require("@mod/logger")
local utility = require("@mod/utility")

local Bezier = require("@obj/Bezier")
local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

local rng = Random.new()

local line = {}

local part_cache: ObjectCache.ObjectCache?

function line.init(cache)
  part_cache = cache
end

function line.deinit()
  part_cache = nil
end

function line.emit(origin: Attachment, ref: Part, scope: types.scope)
  if not part_cache then
    return
  end

  local raydir = attr.get(origin, "RayDirection", vector.create(0, -50, 0))

  local rayColGroup = attr.get(origin, "RayCollisionGroup", "Default")
  local rayFilterTag = attr.get(origin, "FilterTag", "")
  local rayFilterType = attr.get(origin, "FilterType", "Exclude")

  local rayIgnoreWater = attr.get(origin, "IgnoreWater", true)
  local rayIgnoreCanCollide = attr.get(origin, "IgnoreCanCollide", false)

  local params = RaycastParams.new()
  params.CollisionGroup = rayColGroup
  params.IgnoreWater = rayIgnoreWater
  params.RespectCanCollide = not rayIgnoreCanCollide
  params.FilterType = Enum.RaycastFilterType[rayFilterType]
  params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

  if rayFilterType == "Exclude" then
    params:AddToFilter({ workspace.Terrain })
  end

  local emitDelay = attr.get(ref, "EmitDelay", 0)

  local rateStart = attr.get(ref, "Rate_Start", 30)
  local rateEnd = attr.get(ref, "Rate_End", 30)

  local fixedAmount = attr.get(ref, "FixedAmount", 0)

  local scaleStart = attr.get(ref, "Scale_Start", 1)
  local scaleEnd = attr.get(ref, "Scale_End", 1)

  local duration = attr.get(ref, "Duration", 1)
  local direction = attr.get(ref, "Direction", vector.create(0, 0, -1))
  local lineLength = attr.get(ref, "Length", 50)

  local rot = attr.getRange(ref, "Rotation", NumberRange.new(-180, 180))

  local old_partOffset = attr.get(ref, "PartOffset", vector.zero, true)

  local baseOffset = attr.get(ref, "BaseOffset", old_partOffset)
  local offsetStart = attr.get(ref, "Offset_Start", old_partOffset)
  local offsetEnd = attr.get(ref, "Offset_End", old_partOffset)

  local offsetStartDuration = attr.get(ref, "Offset_Start_Duration", 0.5)
  local offsetEndDuration = attr.get(ref, "Offset_End_Duration", 0.5)

  local lifetime = attr.getRange(ref, "Lifetime", NumberRange.new(2, 3), NumberRange.new(0, math.huge))

  local sizeScaleStart = attr.get(ref, "SizeScaleStart", vector.zero)
  local sizeScaleEnd = attr.get(ref, "SizeScaleEnd", vector.zero)

  local minSize = attr.get(ref, "MinSize", vector.create(2, 1, 2))
  local maxSize = attr.get(ref, "MaxSize", vector.create(3, 2, 3))

  local old_sizeCurve = attr.get(ref, "Size_Curve", utility.default_bezier, true)
  local old_sizeDuration = attr.get(ref, "Size_Duration", 0.5, true)

  local sizeStartCurve = attr.get(ref, "Size_Start_Curve", old_sizeCurve)
  local sizeEndCurve = attr.get(ref, "Size_End_Curve", old_sizeCurve)

  local sizeStartDuration = attr.get(ref, "Size_Start_Duration", old_sizeDuration)
  local sizeEndDuration = attr.get(ref, "Size_End_Duration", old_sizeDuration)

  local tpDuration = attr.get(ref, "Transparency_Duration", 0.5)

  local tpStart = attr.get(ref, "Transparency_Start", 0)
  local tpEnd = attr.get(ref, "Transparency_End", 0)

  local sync = attr.get(ref, "SyncPosition", false)

  duration = math.max(duration, 0.001)

  if fixedAmount > 0 then
    local rate = fixedAmount / duration

    rateStart = rate
    rateEnd = rate
  end

  direction = direction.Unit

  if direction ~= direction then
    direction = -Vector3.zAxis
  end

  task.wait(emitDelay)

  local promises = {}

  local start = utility.getTransformedOriginExtents(origin)

  local last = 0
  local total = 0

  local currentRate = rateStart
  local currentScale = scaleStart

  if scaleStart ~= scaleEnd then
    table.insert(
      scope,
      tween.fromParams(attr.get(ref, "Scale_Curve", utility.default_bezier), duration, function(alpha, deltaTime)
        currentScale = utility.lerp(scaleStart, scaleEnd, alpha)
        return deltaTime
      end)
    )
  end

  if rateStart ~= rateEnd then
    table.insert(
      scope,
      tween.fromParams(attr.get(ref, "Rate_Curve", utility.default_bezier), duration, function(alpha, deltaTime)
        currentRate = utility.lerp(rateStart, rateEnd, alpha)
        return deltaTime
      end)
    )
  end

  local pathCurve = attr.get(ref, "Path_Curve", utility.linear_bezier)

  local ok, points = pcall(function()
    return utility.deserializePath(pathCurve)
  end)

  if not ok then
    logger.error(`failed to decode bezier path data with error: {points}`)
  end

  local bezier = Bezier.new(points, 0)

  table.insert(
    scope,
    tween.fromParams(utility.linear_bezier, duration, function(_, deltaTime)
      last += deltaTime

      local threshold = 1 / currentRate
      local max = duration * currentRate

      if last < threshold or total >= max then
        return deltaTime
      end

      local ticks = last // threshold

      for i = 1, ticks do
        if total >= max then
          continue
        end

        total += 1

        local t = math.clamp(total / max, 0, 1)
        local alpha = 1 - bezier:getEase(t).y

        if sync then
          start = utility.getTransformedOriginExtents(origin)
        end

        local originCFrame = utility.getTransformedOriginExtents(origin)
        local result = workspace:Raycast(
          start.Position + start:VectorToWorldSpace(direction) * lineLength * alpha,
          originCFrame:VectorToWorldSpace(raydir),
          params
        )

        if not result then
          last = 0
          return deltaTime
        end

        local width = rng:NextNumber(minSize.X, maxSize.X)

        local height = rng:NextNumber(minSize.Y, maxSize.Y)
        local length = rng:NextNumber(minSize.Z, maxSize.Z)

        local id = utility.getRandomId()

        local part = part_cache:get(id)

        local realPart = part._getReal()

        utility.copyProperties(ref, realPart, utility.COPY_PART_PROPERTIES)
        utility.copyProperties(ref, realPart, utility.COPY_EXTENDED_PART_PROPERTIES)

        if #ref:GetChildren() ~= 0 then
          local clone = ref:Clone()

          for _, child in clone:GetChildren() do
            child.Parent = realPart
          end

          clone:Destroy()
        end

        local emitOnFinish = scope.effects.prepareEmitOnFinish(realPart, scope)

        table.insert(scope, function()
          if part_cache then
            part_cache:free(id)
          end
        end)

        part.Color = result.Instance.Color
        part.Material = result.Material
        part.Transparency = result.Instance.Transparency

        if part.Transparency == 0 then
          part.Transparency = tpStart
        end

        part.Size = Vector3.zero

        local angle = rng:NextNumber(rot.Min, rot.Max)

        local rx = -math.cos(angle)
        local rz = -math.sin(angle)

        local dir = originCFrame:VectorToWorldSpace(Vector3.new(rx, 0, rz))
        local right = dir:Cross(result.Normal).Unit

        local rotCF = CFrame.fromMatrix(result.Position, right, result.Normal)
          * CFrame.fromOrientation(-math.atan(height / length), 0, 0)

        part.CFrame = CFrame.new(offsetStart) * rotCF

        local sizeTween
        local offsetTween

        local currentOffset = Vector3.zero

        if offsetStart ~= baseOffset then
          offsetTween = tween.fromParams(
            attr.get(ref, "Offset_Start_Curve", utility.default_bezier),
            offsetStartDuration,
            function(alpha, deltaTime)
              currentOffset = offsetStart:Lerp(baseOffset, alpha)
              part.CFrame = CFrame.new(currentOffset) * rotCF
              return deltaTime
            end
          )

          table.insert(scope, offsetTween)
        end

        local size = Vector3.new(width, height, length) * currentScale

        if size * sizeScaleStart ~= size then
          sizeTween = tween.fromParams(sizeStartCurve, sizeStartDuration, function(alpha, deltaTime)
            part.Size = (size * sizeScaleStart):Lerp(size, alpha)
            return deltaTime
          end)

          table.insert(scope, sizeTween)
        else
          part.Size = size * sizeScaleStart
        end

        local env = scope.effects.emitNested(realPart, scope.depth + 1, scope)
        table.insert(promises, env.Finished)

        task.delay(rng:NextNumber(lifetime.Min, lifetime.Max), function()
          if sizeTween then
            sizeTween:Disconnect()
          end

          if offsetTween then
            offsetTween:Disconnect()
          end

          local startSize = part.Size
          local startTp = part.Transparency

          if startSize ~= size * sizeScaleEnd then
            table.insert(
              scope,
              tween.fromParams(sizeEndCurve, sizeEndDuration, function(alpha, deltaTime)
                part.Size = startSize:Lerp(size * sizeScaleEnd, alpha)
                return deltaTime
              end)
            )
          end

          if currentOffset ~= offsetEnd then
            table.insert(
              scope,
              tween.fromParams(
                attr.get(ref, "Offset_End_Curve", utility.default_bezier),
                offsetEndDuration,
                function(alpha, deltaTime)
                  part.CFrame = CFrame.new(currentOffset:Lerp(offsetEnd, alpha)) * rotCF
                  return deltaTime
                end
              )
            )
          end

          if startTp ~= tpEnd then
            table.insert(
              scope,
              tween.fromParams(
                attr.get(ref, "Transparency_Curve", utility.default_bezier),
                tpDuration,
                function(alpha, deltaTime)
                  part.Transparency = utility.lerp(startTp, tpEnd, alpha)
                  return deltaTime
                end
              )
            )
          end

          local env = scope.effects.emitOnFinish(emitOnFinish, realPart, scope.depth + 1, scope)
          table.insert(promises, env.Finished)
        end)
      end

      last %= threshold

      return deltaTime
    end, nil, nil, true, utility.RENDER_PRIORITY + scope.depth)
  )

  task.wait(lifetime.Max + duration + math.max(sizeEndDuration, offsetEndDuration))

  Promise.all(promises):await()
end

return line
