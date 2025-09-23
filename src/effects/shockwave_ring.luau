local CollectionService = game:GetService("CollectionService")

local tween = require("../mod/tween")
local utility = require("../mod/utility")

local Promise = require("../pkg/Promise")
local ObjectCache = require("../obj/ObjectCache")

local rng = Random.new()

local ring = {}

local part_cache: ObjectCache.ObjectCache?

function ring.init(cache)
  part_cache = cache
end

function ring.deinit()
  part_cache = nil
end

function ring.emit(origin: Attachment, ref: Part, scope: utility.scope)
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

  local radius = utility.getAttribute(ref, "Radius", 5)
  local segments = utility.getAttribute(ref, "Segments", 7)

  local lifetime = utility.getRangeAttribute(ref, "Lifetime", NumberRange.new(2, 3), NumberRange.new(0, math.huge))

  local old_partOffset = utility.getAttribute(ref, "PartOffset", vector.zero, true)

  local baseOffset = utility.getAttribute(ref, "BaseOffset", old_partOffset)
  local offsetStart = utility.getAttribute(ref, "Offset_Start", old_partOffset)
  local offsetEnd = utility.getAttribute(ref, "Offset_End", old_partOffset)

  local offsetStartDuration = utility.getAttribute(ref, "Offset_Start_Duration", 0.5)
  local offsetEndDuration = utility.getAttribute(ref, "Offset_End_Duration", 0.5)

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

  task.wait(emitDelay)

  local promises = {}

  for i = 0, segments - 1 do
    local angle = i / segments * math.pi * 2

    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)

    local result = workspace:Raycast(
      (origin.WorldCFrame * CFrame.new(x, 0, y)).Position,
      origin.WorldCFrame:VectorToWorldSpace(raydir),
      params
    )

    if not result then
      continue
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

    if shared.vfx and #part:GetChildren() ~= 0 then
      local env = shared.vfx.emit(part)
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

  task.wait(lifetime.Max + math.max(sizeEndDuration, offsetEndDuration))

  Promise.all(promises):await()
end

return ring
