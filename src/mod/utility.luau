local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local logger = require("./logger")

export type scope = {
  depth: number,
}

local utility = {}

utility.DEG_TO_RAD = math.pi / 180

utility.BEZIER_TAG = "BezierParticle"
utility.SHOCKWAVE_TAG = "Shockwave"
utility.SCREENSHAKE_TAG = "CameraShake"
utility.ENABLED_VFX_TAG = "ConstantVFX"
utility.TEXTURE_LOAD_TAG = "LoadVFXTextures"

utility.RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

utility.COLLISION_GROUPS = {
  StudioSelectable = {},

  ForgeDebris = {
    ForgeDebris = false,
  },

  ForgeMouseIgnore = {
    StudioSelectable = false,
  },
}

utility.COPY_SPECIALMESH_PROPERTIES = {
  "MeshId",
  "MeshType",
  "Offset",
  "Scale",
  "TextureId",
  "VertexColor",
}

utility.COPY_PART_PROPERTIES = {
  "CastShadow",

  "Color",

  "Material",
  "MaterialVariant",
  "Reflectance",

  "Shape",

  "FrontSurface",
  "BackSurface",
  "LeftSurface",
  "RightSurface",
  "TopSurface",
  "BottomSurface",
}

utility.COPY_EXTENDED_PART_PROPERTIES = {
  "Size",
  "Transparency",

  "CanCollide",
  "CanQuery",
  "CanTouch",

  "CollisionGroup",
}

local LOCKS = setmetatable({} :: { [Instance]: boolean }, { __mode = "k" })

function utility.lock(ref: Instance)
  if LOCKS[ref] then
    return true
  end

  LOCKS[ref] = coroutine.running()

  return false
end

function utility.unlock(ref: Instance, key: thread?)
  local thread = LOCKS[ref]

  if coroutine.running() ~= thread and key ~= thread then
    logger.error("attempt to unlock an instance owned by a different thread")
  end

  LOCKS[ref] = nil
end

function utility.setCollisionGroups(groups)
  local rules = {}

  for name, list in groups do
    PhysicsService:RegisterCollisionGroup(name)

    if not name:match("Studio") or RunService:IsStudio() then
      rules[name] = list
    end
  end

  for name, list in rules do
    for group, collidable in list do
      if group:match("Studio") and not RunService:IsStudio() then
        continue
      end

      PhysicsService:CollisionGroupSetCollidable(name, group, collidable)
    end
  end
end

local last_id = 0

function utility.getRanomId()
  last_id += 1
  return tostring(last_id)
end

function utility.copyProperties(from: Instance, to: Instance, list: { string })
  for _, k in list do
    to[k] = from[k]
  end
end

function utility.lerp(a: number, b: number, t: number)
  return a + (b - a) * t
end

function utility.try<R, A>(msg: string, func: (...A) -> ...R, ...: A): (boolean, ...R)
  local res = { xpcall(func, function(err)
    logger.warn(string.format(msg, err))
  end, ...) }

  return res[1], table.unpack(res, 2)
end

function utility.reboundfn<A>(sec: number, func: (...A) -> never): (...A) -> never
  local lastRunThread

  return function(...)
    if lastRunThread then
      task.cancel(lastRunThread)
    end

    local args = { ... }

    lastRunThread = task.delay(sec, function()
      lastRunThread = nil
      func(table.unpack(args))
    end)
  end
end

function utility.randomUnitVector(min: Vector3, max: Vector3, rng: Random?)
  if not rng then
    rng = Random.new()
  end

  return Vector3.new(rng:NextNumber(min.X, max.X), rng:NextNumber(min.Y, max.Y), rng:NextNumber(min.Z, max.Z))
end

function utility.getImpulseForce(start: Vector3, goal: Vector3, duration: number)
  return (goal - start) / duration + Vector3.new(0, workspace.Gravity * duration * 0.5, 0)
end

function utility.isMeshVFX(obj: Instance)
  return obj
    and obj:IsA("Model")
    and obj:FindFirstChild("Start")
    and obj.Start:IsA("BasePart")
    and obj:FindFirstChild("End")
    and obj.End:IsA("BasePart")
end

function utility.cleanupScope(scope: { unknown })
  for _, v in scope do
    local t = typeof(v)

    if t == "Instance" then
      v:Destroy()
    elseif t == "RBXScriptConnection" then
      v:Disconnect()
    elseif t == "thread" then
      if coroutine.status(v) ~= "dead" then
        task.cancel(v)
      end
    elseif t == "function" then
      task.spawn(v)
    elseif t == "table" then
      utility.cleanupScope(v)
    end
  end

  table.clear(scope)
end

function utility.protectParent(scope: { unknown }, parent: Instance)
  table.insert(
    scope,
    parent.AncestryChanged:Connect(function(_, new)
      if parent.Parent == workspace.Terrain then
        return
      end

      parent.Parent = workspace.Terrain
    end)
  )
end

function utility.findFirstClassWithTag(obj: Instance?, class: string, tag: string)
  if not obj or obj.Parent == game then
    return
  end

  if obj.ClassName == class and obj:HasTag(tag) then
    return obj
  else
    return utility.findFirstClassWithTag(obj.Parent, class, tag)
  end
end

function utility.cloneParticleAncestry(particle: ParticleEmitter, map: { [Instance]: Instance }?): (Instance, Instance)
  if not particle:FindFirstAncestorWhichIsA("BasePart") and not particle:FindFirstAncestorOfClass("Attachment") then
    return
  end

  local function findAncestor(obj: Instance)
    local ancestor = obj

    if obj.Parent and (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment")) then
      ancestor = findAncestor(obj.Parent)
    end

    return ancestor
  end

  local function recurse(obj: Instance)
    local created = map[obj]

    if created then
      return created, if obj == particle then map[obj.Parent] else map[findAncestor(obj.Parent)] or map[obj]
    end

    local clone = Instance.fromExisting(obj)
    clone.Archivable = false

    if clone:IsA("BasePart") then
      clone.Locked = true
    end

    local ancestor = clone

    if map then
      map[obj] = clone
    end

    if obj.Parent and (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment")) then
      local parent, pa = recurse(obj.Parent)

      if pa then
        ancestor = pa
      end

      if parent then
        clone.Parent = parent
      end
    end

    return clone, ancestor
  end

  return recurse(particle.Parent)
end

function utility.getAttribute<T>(obj: Instance, name: string, default: T, soft: boolean?): T
  local value = obj:GetAttribute(name)

  if value == nil or typeof(value) ~= typeof(default) then
    value = default
  end

  if not soft then
    obj:SetAttribute(name, value)
  end

  return value
end

function utility.getRangeAttribute(
  obj: Instance,
  name: string,
  default: NumberRange,
  clamp: NumberRange?,
  soft: boolean?
)
  local value = obj:GetAttribute(name)

  if typeof(value) ~= "NumberRange" then
    value = default
  end

  if clamp then
    -- stylua: ignore
    value = NumberRange.new(
      math.clamp(value.Min, clamp.Min, clamp.Max),
      math.clamp(value.Max, clamp.Min, clamp.Max)
    )
  end

  if not soft then
    obj:SetAttribute(name, value)
  end

  return value
end

function utility.getEnumAttribute<T>(obj: Instance, name: string, default: T, enums: { T }, soft: boolean?): T
  local value = obj:GetAttribute(name)

  if value == nil or not table.find(enums, value) then
    value = default
  end

  if not soft then
    obj:SetAttribute(name, value)
  end

  return value
end

function utility.getMeshDecals(ref: Model, start: BasePart)
  local legacy_isFlipbook = utility.getAttribute(ref, "Flipbook", false, true)

  local decals = {}
  local flipbooks = {}
  local fromToMap = {}

  local function filter(list: { Instance }): { Decal }
    local filtered = {}

    for _, v in list do
      if v:IsA("Decal") then
        table.insert(filtered, v)
      end
    end

    return filtered
  end

  if legacy_isFlipbook then
    decals = filter(start:GetChildren())
  else
    local originalEnd = ref:FindFirstChild("End")
    local originalStart = ref:FindFirstChild("Start")

    if originalEnd then
      for _, v in start:GetChildren() do
        if not v:IsA("Decal") then
          continue
        end

        local from = v

        local to = originalEnd:FindFirstChild(v.Name)

        if not to or not to:IsA("Decal") then
          continue
        end

        table.insert(decals, v)

        fromToMap[from] = to

        if not v:GetAttribute("FlipbookEnabled") then
          table.insert(decals, v)
        else
          flipbooks[v] = utility.deserializeFlipbook(v:GetAttribute("FlipbookTextures"))
        end
      end

      for _, v in originalStart:GetChildren() do
        if not v:IsA("Decal") then
          continue
        end

        -- convert children decals to flipbooks
        local children = v:GetChildren()

        do
          local offset = 0

          for i = 1, #children do
            i -= offset

            local obj = children[i]

            if not obj:IsA("Decal") then
              table.remove(children, i)
              offset += 1
            end
          end
        end

        if #children ~= 0 then
          local function idx(str: string)
            return tonumber(str:match("%d+")) or 0
          end

          table.sort(children, function(a, b)
            return idx(a.Name) < idx(b.Name)
          end)

          local ids = {}

          for _, obj in children do
            table.insert(ids, idx(obj.Texture))
            obj:Destroy()
          end

          local buf = utility.serializeFlipbook(ids)

          v:SetAttribute("FlipbookEnabled", true)
          v:SetAttribute("FlipbookTextures", buffer.tostring(buf))
        end
      end
    end
  end

  return decals, flipbooks, fromToMap
end

function utility.getBezierPoints(root: Attachment, metadata: boolean)
  local objs = root:GetChildren()

  table.sort(objs, function(a, b)
    return tonumber(a.Name) < tonumber(b.Name)
  end)

  local points: { vector } = {}
  local attachments: { Attachment } = {}
  local attachmentToPointMap: { [Attachment]: vector } = {}

  local function vec(p: Attachment)
    local w = root.WorldCFrame:PointToObjectSpace(p.WorldPosition)
    local pos = vector.create(w.X, w.Y, w.Z)

    table.insert(points, pos)

    if metadata then
      attachmentToPointMap[p] = pos
      table.insert(attachments, p)
    end

    return pos
  end

  for i, p in objs do
    local t0 = p:FindFirstChild("T0")
    local t1 = p:FindFirstChild("T1")

    if i == 1 then
      vec(p)
    end

    -- left
    if i ~= 1 then
      if t1 then
        vec(t1)
      else
        vec(p)
      end
    end

    if i ~= 1 and i ~= #objs then
      vec(p)
    end

    -- right
    if i ~= #objs then
      if t0 then
        vec(t0)
      else
        vec(p)
      end
    end

    if i == #objs then
      vec(p)
    end
  end

  return points, attachments, attachmentToPointMap
end

function utility.scaleNumberSequence(
  seq: NumberSequence,
  scale: number | (value: number, envelope: number) -> (number, number)
)
  if scale == 1 then
    return seq
  end

  local scaled = {}

  for _, keypoint in seq.Keypoints do
    local value, envelope

    if typeof(scale) == "function" then
      value, envelope = scale(keypoint.Value, keypoint.Envelope)
    else
      value, envelope = keypoint.Value * scale, keypoint.Envelope * scale
    end

    table.insert(scaled, NumberSequenceKeypoint.new(keypoint.Time, value, envelope))
  end

  return NumberSequence.new(scaled)
end

@native
function utility.serializePath(points: { Path2DControlPoint })
  local buf = buffer.create(#points * 4 * 6)

  local offset = 0

  for i, p in points do
    local px = p.Position.X.Scale
    local py = p.Position.Y.Scale

    if i ~= 1 then
      buffer.writef32(buf, offset, px + p.LeftTangent.X.Scale)
      buffer.writef32(buf, offset + 4, py + p.LeftTangent.Y.Scale)

      offset += 8
    end

    buffer.writef32(buf, offset, px)
    buffer.writef32(buf, offset + 4, py)

    offset += 8

    if i ~= #points then
      buffer.writef32(buf, offset, px + p.RightTangent.X.Scale)
      buffer.writef32(buf, offset + 4, py + p.RightTangent.Y.Scale)

      offset += 8
    end
  end

  return buf
end

@native
function utility.deserializePath(data: string | buffer)
  local buf = typeof(data) == "string" and buffer.fromstring(data) or data
  local count = buffer.len(buf) / 24

  local points = {}

  for i = 0, count - 1 do
    local offset = i * 4 * 6

    local px = buffer.readf32(buf, offset)
    local py = buffer.readf32(buf, offset + 4)

    table.insert(points, vector.create(px, py))

    if i ~= count - 1 then
      local t1x = buffer.readf32(buf, offset + 8)
      local t1y = buffer.readf32(buf, offset + 12)

      local t2x = buffer.readf32(buf, offset + 16)
      local t2y = buffer.readf32(buf, offset + 20)

      table.insert(points, vector.create(t1x, t1y))
      table.insert(points, vector.create(t2x, t2y))
    end
  end

  return points
end

@native
function utility.serializeFlipbook(ids: { number })
  local buf = buffer.create(#ids * 8)

  for i, id in ids do
    buffer.writef64(buf, (i - 1) * 8, id)
  end

  return buf
end

@native
function utility.deserializeFlipbook(data: string | buffer)
  local buf = typeof(data) == "string" and buffer.fromstring(data) or data
  local count = buffer.len(buf) / 8

  local ids = {}

  for i = 0, count - 1 do
    table.insert(ids, buffer.readf64(buf, i * 8))
  end

  return ids
end

-- out cubic
utility.default_bezier = buffer.tostring(utility.serializePath({
  Path2DControlPoint.new(UDim2.fromScale(0, 1), UDim2.new(), UDim2.fromScale(0.215, -0.61)),
  Path2DControlPoint.new(UDim2.fromScale(1, 0), UDim2.fromScale(-0.645, 0), UDim2.new()),
}))

-- linear
utility.linear_bezier = buffer.tostring(utility.serializePath({
  Path2DControlPoint.new(UDim2.fromScale(0, 1)),
  Path2DControlPoint.new(UDim2.fromScale(1, 0)),
}))

return utility
