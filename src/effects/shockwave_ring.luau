local CollectionService = game:GetService("CollectionService")

local attr = require("@mod/attributes")
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")

local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

local rng = Random.new()

local ring = {}

local part_cache: ObjectCache.ObjectCache?

function ring.init(cache)
  part_cache = cache
end

function ring.deinit()
  part_cache = nil
end

function ring.emit(origin: Attachment, ref: Part, scope: types.scope)
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

  local radius = attr.get(ref, "Radius", 5)
  local segments = attr.get(ref, "Segments", 7)

  local lifetime = attr.getRange(ref, "Lifetime", NumberRange.new(2, 3), NumberRange.new(0, math.huge))

  local old_partOffset = attr.get(ref, "PartOffset", vector.zero, true)

  local baseOffset = attr.get(ref, "BaseOffset", old_partOffset)
  local offsetStart = attr.get(ref, "Offset_Start", old_partOffset)
  local offsetEnd = attr.get(ref, "Offset_End", old_partOffset)

  local offsetStartDuration = attr.get(ref, "Offset_Start_Duration", 0.5)
  local offsetEndDuration = attr.get(ref, "Offset_End_Duration", 0.5)

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

  utility.pausableWait(emitDelay)

  local promises = {}
  local originCFrame = utility.getTransformedOriginExtents(origin)

  for i = 0, segments - 1 do
    local angle = i / segments * math.pi * 2

    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)

    local result =
      workspace:Raycast((originCFrame * CFrame.new(x, 0, y)).Position, originCFrame:VectorToWorldSpace(raydir), params)

    if not result then
      continue
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

    local emitOnFinish = scope.effects.prepareEmitOnFinish(part, scope)

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

      table.insert(scope, sizeTween)
    end

    local size = Vector3.new(width, height, length)

    if size * sizeScaleStart ~= size then
      sizeTween = tween.fromParams(sizeStartCurve, sizeStartDuration, function(alpha, deltaTime)
        part.Size = (size * sizeScaleStart):Lerp(size, alpha)
        return deltaTime
      end)

      table.insert(scope, sizeTween)
    else
      part.Size = size * sizeScaleStart
    end

    local env = scope.effects.emitNested(part, scope.depth + 1, scope)
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

      local env = scope.effects.emitOnFinish(emitOnFinish, part, scope.depth + 1, scope)
      table.insert(promises, env.Finished)
    end)
  end

  utility.pausableWait(lifetime.Max + math.max(sizeEndDuration, offsetEndDuration))

  Promise.all(promises):await()
end

return ring
