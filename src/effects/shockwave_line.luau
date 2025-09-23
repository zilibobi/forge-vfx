local CollectionService = game:GetService("CollectionService")

local tween = require("../mod/tween")
local logger = require("../mod/logger")
local utility = require("../mod/utility")

local Bezier = require("../obj/Bezier")
local Promise = require("../pkg/Promise")
local ObjectCache = require("../obj/ObjectCache")

local rng = Random.new()

local line = {}

local part_cache: ObjectCache.ObjectCache?

function line.init(cache)
  part_cache = cache
end

function line.deinit()
  part_cache = nil
end

function line.emit(origin: Attachment, ref: Part, scope: utility.scope)
  if not part_cache then
    return
  end

  local raydir = utility.getAttribute(origin, "RayDirection", vector.create(0, -50, 0))

  local rayColGroup = utility.getAttribute(origin, "RayCollisionGroup", "Default")
  local rayFilterTag = utility.getAttribute(origin, "FilterTag", "")
  local rayFilterType = utility.getAttribute(origin, "FilterType", "Exclude")

  local rayIgnoreWater = utility.getAttribute(origin, "IgnoreWater", true)
  local rayIgnoreCanCollide = utility.getAttribute(origin, "IgnoreCanCollide", false)

  local params = RaycastParams.new()
  params.CollisionGroup = rayColGroup
  params.IgnoreWater = rayIgnoreWater
  params.RespectCanCollide = not rayIgnoreCanCollide
  params.FilterType = Enum.RaycastFilterType[rayFilterType]
  params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

  if rayFilterType == "Exclude" then
    params:AddToFilter({ workspace.Terrain })
  end

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

  local rateStart = utility.getAttribute(ref, "Rate_Start", 30)
  local rateEnd = utility.getAttribute(ref, "Rate_End", 30)

  local fixedAmount = utility.getAttribute(ref, "FixedAmount", 0)

  local scaleStart = utility.getAttribute(ref, "Scale_Start", 1)
  local scaleEnd = utility.getAttribute(ref, "Scale_End", 1)

  local duration = utility.getAttribute(ref, "Duration", 1)
  local direction = utility.getAttribute(ref, "Direction", vector.create(0, 0, -1))
  local lineLength = utility.getAttribute(ref, "Length", 50)

  local rot = utility.getRangeAttribute(ref, "Rotation", NumberRange.new(-180, 180))

  local old_partOffset = utility.getAttribute(ref, "PartOffset", vector.zero, true)

  local baseOffset = utility.getAttribute(ref, "BaseOffset", old_partOffset)
  local offsetStart = utility.getAttribute(ref, "Offset_Start", old_partOffset)
  local offsetEnd = utility.getAttribute(ref, "Offset_End", old_partOffset)

  local offsetStartDuration = utility.getAttribute(ref, "Offset_Start_Duration", 0.5)
  local offsetEndDuration = utility.getAttribute(ref, "Offset_End_Duration", 0.5)

  local lifetime = utility.getRangeAttribute(ref, "Lifetime", NumberRange.new(2, 3), NumberRange.new(0, math.huge))

  local sizeScaleStart = utility.getAttribute(ref, "SizeScaleStart", vector.zero)
  local sizeScaleEnd = utility.getAttribute(ref, "SizeScaleEnd", vector.zero)

  local minSize = utility.getAttribute(ref, "MinSize", vector.create(2, 1, 2))
  local maxSize = utility.getAttribute(ref, "MaxSize", vector.create(3, 2, 3))

  local old_sizeCurve = utility.getAttribute(ref, "Size_Curve", utility.default_bezier, true)
  local old_sizeDuration = utility.getAttribute(ref, "Size_Duration", 0.5, true)

  local sizeStartCurve = utility.getAttribute(ref, "Size_Start_Curve", old_sizeCurve)
  local sizeEndCurve = utility.getAttribute(ref, "Size_End_Curve", old_sizeCurve)

  local sizeStartDuration = utility.getAttribute(ref, "Size_Start_Duration", old_sizeDuration)
  local sizeEndDuration = utility.getAttribute(ref, "Size_End_Duration", old_sizeDuration)

  local tpDuration = utility.getAttribute(ref, "Transparency_Duration", 0.5)

  local tpStart = utility.getAttribute(ref, "Transparency_Start", 0)
  local tpEnd = utility.getAttribute(ref, "Transparency_End", 0)

  local sync = utility.getAttribute(ref, "SyncPosition", false)

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

  local start = origin.WorldCFrame

  local last = 0
  local total = 0

  local currentRate = rateStart
  local currentScale = scaleStart

  if scaleStart ~= scaleEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Scale_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          currentScale = utility.lerp(scaleStart, scaleEnd, alpha)
          return deltaTime
        end
      )
    )
  end

  if rateStart ~= rateEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Rate_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          currentRate = utility.lerp(rateStart, rateEnd, alpha)
          return deltaTime
        end
      )
    )
  end

  local pathCurve = utility.getAttribute(ref, "Path_Curve", utility.linear_bezier)

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
          start = origin.WorldCFrame
        end

        local result = workspace:Raycast(
          start.Position + start:VectorToWorldSpace(direction) * lineLength * alpha,
          origin.WorldCFrame:VectorToWorldSpace(raydir),
          params
        )

        if not result then
          last = 0
          return deltaTime
        end

        local width = rng:NextNumber(minSize.X, maxSize.X)

        local height = rng:NextNumber(minSize.Y, maxSize.Y)
        local length = rng:NextNumber(minSize.Z, maxSize.Z)

        local id = utility.getRanomId()

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

        local dir = origin.WorldCFrame:VectorToWorldSpace(Vector3.new(rx, 0, rz))
        local right = dir:Cross(result.Normal).Unit

        local rotCF = CFrame.fromMatrix(result.Position, right, result.Normal)
          * CFrame.fromOrientation(-math.atan(height / length), 0, 0)

        part.CFrame = CFrame.new(offsetStart) * rotCF

        local sizeTween
        local offsetTween

        local currentOffset = Vector3.zero

        if offsetStart ~= baseOffset then
          offsetTween = tween.fromParams(
            utility.getAttribute(ref, "Offset_Start_Curve", utility.default_bezier),
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

        if shared.vfx and #part:GetChildren() ~= 0 then
          local env = shared.vfx.emit(realPart)
          table.insert(promises, env.Finished)
        end

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
                utility.getAttribute(ref, "Offset_End_Curve", utility.default_bezier),
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
                utility.getAttribute(ref, "Transparency_Curve", utility.default_bezier),
                tpDuration,
                function(alpha, deltaTime)
                  part.Transparency = utility.lerp(startTp, tpEnd, alpha)
                  return deltaTime
                end
              )
            )
          else
            part.Transparency = startTp
          end
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
