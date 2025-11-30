local Beam = require("@vfx/beam")
local Spin = require("@vfx/spin")
local Mesh = require("@vfx/mesh")
local Bezier = require("@vfx/bezier")
local Lightning = require("@vfx/lightning")
local Screen = require("@vfx/screen")
local Particle = require("@vfx/particle")
local CameraShake = require("@vfx/camera_shake")
local TweenProperty = require("@vfx/tween_property")
local ShockwaveRing = require("@vfx/shockwave_ring")
local ShockwaveLine = require("@vfx/shockwave_line")
local ShockwaveDebris = require("@vfx/shockwave_debris")

local types = require("@root/types")
local utility = require("@mod/utility")

local Promise = require("@pkg/Promise")

local emitters = {}

function emitters.particle(
  obj: ParticleEmitter,
  scope: types.scope,
  sharedUncMap: { [Instance]: number },
  sharedRefMap: { [Instance]: Instance },
  legacyScale: number
)
  local count = utility.getAttribute(obj, "EmitCount", 0)
  local duration = utility.getAttribute(obj, "EmitDuration", 0)

  if count <= 0 and duration <= 0 then
    return
  end

  if not obj:IsDescendantOf(workspace) then
    local parent, ancestor = utility.cloneParticleAncestry(obj, sharedRefMap)

    if not parent then
      return
    end

    table.insert(scope, ancestor)

    local clone = obj:Clone()
    clone.Archivable = false
    clone.Parent = parent

    if not sharedUncMap[ancestor] then
      ancestor.Parent = workspace.Terrain
    end

    if not sharedUncMap[ancestor] then
      sharedUncMap[ancestor] = 1
    else
      sharedUncMap[ancestor] += 1
    end

    utility.try(`failed to emit particle with error: %s`, Particle.emit, obj, clone, scope, legacyScale)

    sharedUncMap[ancestor] -= 1
  else
    utility.try(`failed to emit particle with error: %s`, Particle.emit, obj, obj, scope, legacyScale)
  end
end

function emitters.beam(obj: Beam, scope: types.scope, legacyScale: number)
  local att0, att1 = obj.Attachment0, obj.Attachment1

  if not att0 or not att1 then
    return
  end

  local clone = obj:Clone()
  clone.Archivable = false
  clone.Parent = workspace.Terrain

  -- clone attachments for beams with scaled length
  local unscaled = NumberRange.new(1, 1)

  if
    utility.getAttribute(obj, "Length_Scale_Start", unscaled, true) ~= unscaled
    or utility.getAttribute(obj, "Length_Scale_End", unscaled, true) ~= unscaled
  then
    local a, b = att0:Clone(), att1:Clone()

    table.insert(scope, a)
    table.insert(scope, b)

    a.Name = "ForgeTempAttachment"
    b.Name = "ForgeTempAttachment"

    clone.Attachment0 = a
    clone.Attachment1 = b

    a.Parent = att0.Parent
    b.Parent = att1.Parent
  end

  table.insert(scope, clone)

  utility.try(`failed to emit beam with error: %s`, Beam.emit, obj, clone, scope, legacyScale)
end

function emitters.trail(obj: Trail)
  obj.Enabled = true
end

function emitters.bezier(obj: Instance, scope: types.scope, skipEnabledCheck: boolean?)
  local part = obj:FindFirstChildOfClass("Part")

  if not part then
    return
  end

  if not skipEnabledCheck and obj:GetAttribute("Enabled") then
    obj:SetAttribute("Enabled", false)
  end

  local clone = part:Clone()
  clone.Locked = true

  table.insert(scope, clone)

  utility.try(`failed to emit bezier with error: %s`, Bezier.emit, obj, clone, scope, skipEnabledCheck)
end

function emitters.lightning(obj: Instance, scope: types.scope, skipEnabledCheck: boolean?)
  local part = obj:FindFirstChildOfClass("Part")

  if not part then
    return
  end

  if not skipEnabledCheck and obj:GetAttribute("Enabled") then
    obj:SetAttribute("Enabled", false)
  end

  local clone = part:Clone()
  clone.Locked = true

  table.insert(scope, clone)

  utility.try(`failed to emit lightning with error: %s`, Lightning.emit, obj, clone, scope, skipEnabledCheck)
end

function emitters.mesh(
  obj: Instance,
  scope: types.scope,
  shared_part_cache: any,
  legacyScale: number,
  skipEnabledCheck: boolean?
)
  local start = obj:FindFirstChild("Start")

  if not start then
    return
  end

  if not skipEnabledCheck and obj:GetAttribute("Enabled") then
    obj:SetAttribute("Enabled", false)
  end

  local tasks = {}

  for i = 1, utility.getAttribute(obj, "EmitCount", 1) do
    table.insert(
      tasks,
      Promise.new(function(resolve)
        utility.try(
          `failed to emit mesh with error: %s`,
          Mesh.emit,
          obj,
          utility.assembleMeshVFX(start, scope, shared_part_cache),
          scope,
          legacyScale,
          skipEnabledCheck
        )

        resolve()
      end)
    )
  end

  Promise.all(tasks):await()
end

function emitters.spin(obj: Model, scope: types.scope)
  if utility.lock(obj) then
    return
  end

  utility.try(`failed to emit spinning model with error: %s`, Spin.emit, obj, scope)
  utility.unlock(obj)
end

function emitters.camera_shake(obj: RayValue, scope: types.scope)
  utility.try(`failed to emit camera shake with error: %s`, CameraShake.emit, obj, scope)
end

function emitters.tween_property(obj: RayValue, scope: types.scope)
  if not obj.Parent or utility.lock(obj) then
    return
  end

  utility.try(`failed to emit tween property with error: %s`, TweenProperty.emit, obj.Parent, obj, scope)

  utility.unlock(obj)
end

function emitters.screen(obj: BasePart, scope: types.scope)
  local ok, result = utility.try(`failed to emit screen effect with error: %s`, Screen.emit, obj, scope)

  return if ok then result else false
end

function emitters.shockwave_ring(att: Attachment, obj: Part, scope: types.scope)
  utility.try(`failed to emit shockwave ring with error: %s`, ShockwaveRing.emit, att, obj, scope)
end

function emitters.shockwave_debris(att: Attachment, obj: Part, scope: types.scope)
  utility.try(`failed to emit shockwave debris with error: %s`, ShockwaveDebris.emit, att, obj, scope)
end

function emitters.shockwave_line(att: Attachment, obj: Part, scope: types.scope)
  utility.try(`failed to emit shockwave line with error: %s`, ShockwaveLine.emit, att, obj, scope)
end

-- Dispatch function to determine which emitter to use and call it
function emitters.dispatch(
  obj: any, -- since we don't use IsA(...), we don't get type narrowing
  scope: types.scope,
  sharedUncMap: { [Instance]: number },
  sharedRefMap: { [Instance]: Instance },
  shared_part_cache: any,
  legacyScale: number
)
  local className = obj.ClassName

  if className == "ParticleEmitter" then
    emitters.particle(obj, scope, sharedUncMap, sharedRefMap, legacyScale)
    return
  elseif className == "Beam" then
    emitters.beam(obj, scope, legacyScale)
    return
  elseif className == "Trail" then
    emitters.trail(obj)
    return
  elseif className == "RayValue" then
    if obj:HasTag(utility.SCREENSHAKE_TAG) then
      emitters.camera_shake(obj, scope)
    else
      emitters.tween_property(obj, scope)
    end

    return
  end

  if obj:HasTag(utility.BEZIER_TAG) then
    emitters.bezier(obj, scope)
    return
  end

  if obj:HasTag(utility.LIGHTNING_TAG) then
    emitters.lightning(obj, scope)
    return
  end

  if className == "Model" then
    if utility.isMeshVFX(obj) then
      emitters.mesh(obj, scope, shared_part_cache, legacyScale)
    else
      emitters.spin(obj, scope)
    end

    return
  end

  if className == "Part" then
    local att = utility.findFirstClassWithTag(obj, "Attachment", utility.SHOCKWAVE_TAG)

    if att then
      local name = obj.Parent and obj.Parent.Name or ""

      if name == "Rings" then
        emitters.shockwave_ring(att, obj, scope)
      elseif name == "Debris" then
        emitters.shockwave_debris(att, obj, scope)
      elseif name == "Lines" then
        emitters.shockwave_line(att, obj, scope)
      end
    end
  end
end

-- Registry for enabled effects (effects that emit continuously)
type EnabledEffectConfig = {
  check: (obj: Instance) -> boolean,
  emit: (obj: Instance, scope: types.scope, shared_part_cache: any) -> (),
}

emitters.enabled_registry = {
  mesh = {
    check = function(obj: Instance)
      return utility.isMeshVFX(obj)
    end,
    emit = function(obj: Instance, scope: types.scope, shared_part_cache: any)
      emitters.mesh(obj, scope, shared_part_cache, 1, true)
    end,
  },

  bezier = {
    check = function(obj: Instance)
      return obj:HasTag(utility.BEZIER_TAG)
    end,
    emit = function(obj: Instance, scope: types.scope, shared_part_cache: any)
      emitters.bezier(obj, scope, true)
    end,
  },

  lightning = {
    check = function(obj: Instance)
      return obj:HasTag(utility.LIGHTNING_TAG)
    end,
    emit = function(obj: Instance, scope: types.scope, shared_part_cache: any)
      emitters.lightning(obj, scope, true)
    end,
  },
} :: { [string]: EnabledEffectConfig }

return emitters
