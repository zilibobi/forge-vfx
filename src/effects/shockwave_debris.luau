local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local tween = require("../mod/tween")
local utility = require("../mod/utility")

local Promise = require("../pkg/Promise")
local ObjectCache = require("../obj/ObjectCache")

local rng = Random.new()

local debris = {}
local physicsParts = {}

local part_cache: ObjectCache.ObjectCache?
local physicsStepper: RBXScriptConnection?

function debris.init(cache)
  if physicsStepper then
    return
  end

  part_cache = cache

  if RunService:IsStudio() and script:FindFirstAncestorOfClass("Plugin") then
    physicsStepper = RunService.RenderStepped:Connect(function(deltaTime)
      if #physicsParts == 0 then
        return
      end

      workspace:StepPhysics(deltaTime, physicsParts)
    end)
  end
end

function debris.deinit()
  if physicsStepper then
    physicsStepper:Disconnect()
    physicsStepper = nil
  end

  part_cache = nil

  for _, part in physicsParts do
    part:Destroy()
  end

  table.clear(physicsParts)
end

function debris.emit(origin: Attachment, ref: Part, scope: utility.scope)
  if not part_cache then
    return
  end

  local params

  local inherit = utility.getAttribute(ref, "InheritanceEnabled", true)
  local inheritRadius = utility.getAttribute(ref, "InheritanceRadius", 5)

  if inherit then
    local inheritMaxResults = utility.getAttribute(ref, "InheritanceMaxResults", 5)

    local rayColGroup = utility.getAttribute(origin, "RayCollisionGroup", "Default")
    local rayFilterTag = utility.getAttribute(origin, "FilterTag", "")
    local rayFilterType = utility.getAttribute(origin, "FilterType", "Exclude")

    local rayIgnoreCanCollide = utility.getAttribute(origin, "IgnoreCanCollide", false)

    params = OverlapParams.new()
    params.MaxParts = inheritMaxResults
    params.CollisionGroup = rayColGroup
    params.RespectCanCollide = not rayIgnoreCanCollide
    params.FilterType = Enum.RaycastFilterType[rayFilterType]
    params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

    if rayFilterType == "Exclude" then
      params:AddToFilter({ workspace.Terrain })
    end
  end

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

  local amount = utility.getRangeAttribute(ref, "Amount", NumberRange.new(5, 10), NumberRange.new(0, math.huge))
  local lifetime = utility.getRangeAttribute(ref, "Lifetime", NumberRange.new(2, 3), NumberRange.new(0, math.huge))
  local airtime = utility.getRangeAttribute(ref, "Airtime", NumberRange.new(0.5, 0.5), NumberRange.new(0, math.huge))

  local linmag = utility.getRangeAttribute(ref, "LinearMagnitude", NumberRange.new(15, 25))
  local angmag = utility.getRangeAttribute(ref, "AngularMagnitude", NumberRange.new(5, 15))

  local sizeScaleEnd = utility.getAttribute(ref, "SizeScaleEnd", vector.zero)

  local minSize = utility.getAttribute(ref, "MinSize", vector.create(2, 1, 2))
  local maxSize = utility.getAttribute(ref, "MaxSize", vector.create(3, 2, 3))

  local minDir = utility.getAttribute(ref, "MinDirection", -vector.one)
  local maxDir = utility.getAttribute(ref, "MaxDirection", vector.one)

  local count = rng:NextInteger(amount.Min, amount.Max)

  local sizeCurve = utility.getAttribute(ref, "Size_Curve", utility.default_bezier)
  local tpCurve = utility.getAttribute(ref, "Transparency_Curve", utility.default_bezier)

  local tpDuration = utility.getAttribute(ref, "Transparency_Duration", 0.5)
  local sizeDuration = utility.getAttribute(ref, "Size_Duration", 0.5)

  local tpStart = utility.getAttribute(ref, "Transparency_Start", 0)
  local tpEnd = utility.getAttribute(ref, "Transparency_End", 1)

  local partData = {}
  local promises = {}

  ref.CanCollide = false

  if params then
    local parts = workspace:GetPartBoundsInRadius(origin.WorldPosition, inheritRadius, params)

    for _, p in parts do
      if p.Transparency == 1 then
        continue
      end

      table.insert(partData, p)
    end
  end

  task.wait(emitDelay)

  for _ = 1, count do
    local iref = #partData ~= 0 and partData[rng:NextInteger(1, #partData)]

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

    part.Anchored = false
    part.CanCollide = true

    part.Transparency = tpStart

    if part.CollisionGroup == "Default" then
      part.CollisionGroup = "ForgeDebris"
    end

    part.CFrame = CFrame.new(origin.WorldPosition)

    local size = Vector3.new(
      rng:NextNumber(minSize.X, maxSize.X),
      rng:NextNumber(minSize.Y, maxSize.Y),
      rng:NextNumber(minSize.Z, maxSize.Z)
    )

    part.Size = size

    if iref then
      part.Material = iref.Material
      part.Color = iref.Color
      part.Transparency = iref.Transparency
    end

    table.insert(scope, function()
      local index = table.find(physicsParts, realPart)

      if index then
        table.remove(physicsParts, index)
      end

      if part_cache then
        part_cache:free(id)
      end
    end)

    table.insert(physicsParts, realPart)

    part.AssemblyLinearVelocity = origin.WorldCFrame:VectorToWorldSpace(part.AssemblyLinearVelocity)

    local relDir = utility.randomUnitVector(minDir, maxDir)
    local worldDir = origin.WorldCFrame:VectorToWorldSpace(relDir)

    part:ApplyImpulse(
      part.AssemblyMass
        * utility.getImpulseForce(
          origin.WorldPosition,
          origin.WorldPosition + worldDir.Unit * rng:NextNumber(linmag.Min, linmag.Max),
          rng:NextNumber(airtime.Min, airtime.Max)
        )
    )

    part:ApplyAngularImpulse(part.AssemblyMass * rng:NextUnitVector() * rng:NextNumber(angmag.Min, angmag.Max))

    if shared.vfx and #part:GetChildren() ~= 0 then
      local env = shared.vfx.emit(part)
      table.insert(promises, env.Finished)
    end

    task.delay(rng:NextNumber(lifetime.Min, lifetime.Max), function()
      local startSize = part.Size

      if startSize ~= size * sizeScaleEnd then
        table.insert(
          scope,
          tween.fromParams(sizeCurve, sizeDuration, function(alpha, deltaTime)
            part.Size = startSize:Lerp(size * sizeScaleEnd, alpha)
            return deltaTime
          end)
        )
      end

      if tpStart ~= tpEnd then
        table.insert(
          scope,
          tween.fromParams(tpCurve, tpDuration, function(alpha, deltaTime)
            part.Transparency = utility.lerp(tpStart, tpEnd, alpha)
            return deltaTime
          end)
        )
      else
        part.Transparency = tpStart
      end
    end)
  end

  task.wait(lifetime.Max + math.max(tpDuration, sizeDuration))

  Promise.all(promises):await()
end

return debris
