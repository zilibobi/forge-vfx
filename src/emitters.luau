local Beam = require(script.Parent.effects.beam)
local Spin = require(script.Parent.effects.spin)
local Mesh = require(script.Parent.effects.mesh)
local Bezier = require(script.Parent.effects.bezier)
local Particle = require(script.Parent.effects.particle)
local CameraShake = require(script.Parent.effects.camera_shake)
local TweenProperty = require(script.Parent.effects.tween_property)
local ShockwaveRing = require(script.Parent.effects.shockwave_ring)
local ShockwaveLine = require(script.Parent.effects.shockwave_line)
local ShockwaveDebris = require(script.Parent.effects.shockwave_debris)

local utility = require(script.Parent.mod.utility)

local Promise = require(script.Parent.pkg.Promise)

local emitters = {}

function emitters.particle(
  obj: ParticleEmitter,
  scope: utility.scope,
  sharedUncMap: { [Instance]: number },
  sharedRefMap: { [Instance]: Instance },
  legacyScale: number
): boolean
  if not obj:IsDescendantOf(workspace) then
    local parent, ancestor = utility.cloneParticleAncestry(obj, sharedRefMap)

    if not parent then
      return true
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

    utility.try(
      `failed to emit particle '{obj:GetFullName()}' with error: %s`,
      Particle.emit,
      obj,
      clone,
      scope,
      legacyScale
    )

    sharedUncMap[ancestor] -= 1

    return sharedUncMap[ancestor] <= 0
  else
    utility.try(
      `failed to emit particle '{obj:GetFullName()}' with error: %s`,
      Particle.emit,
      obj,
      obj,
      scope,
      legacyScale
    )

    return true
  end
end

function emitters.beam(obj: Beam, scope: utility.scope, legacyScale: number): boolean
  local clone = obj:Clone()
  clone.Archivable = false
  clone.Parent = workspace.Terrain

  table.insert(scope, clone)

  utility.try(`failed to emit beam '{obj:GetFullName()}' with error: %s`, Beam.emit, obj, clone, scope, legacyScale)

  return true
end

function emitters.trail(obj: Trail): boolean
  obj.Enabled = true
  return true
end

function emitters.bezier(obj: Instance, scope: utility.scope): boolean
  local part = obj:FindFirstChildOfClass("Part")

  if not part then
    return true
  end

  if obj:GetAttribute("Enabled") then
    obj:SetAttribute("Enabled", false)
  end

  local clone = part:Clone()
  clone.Locked = true

  table.insert(scope, clone)

  utility.try(`failed to emit bezier '{obj:GetFullName()}' with error: %s`, Bezier.emit, obj, clone, scope)

  return true
end

function emitters.mesh(obj: Instance, scope: utility.scope, shared_part_cache: any, legacyScale: number)
  local start = obj:FindFirstChild("Start")

  if not start then
    return true
  end

  if obj:GetAttribute("Enabled") then
    obj:SetAttribute("Enabled", false)
  end

  local tasks = {}

  for i = 1, utility.getAttribute(obj, "EmitCount", 1) do
    table.insert(
      tasks,
      Promise.new(function(resolve)
        utility.try(
          `failed to emit mesh '{obj:GetFullName()}' with error: %s`,
          Mesh.emit,
          obj,
          utility.assembleMeshVFX(start, scope, shared_part_cache),
          scope,
          legacyScale
        )

        resolve()
      end)
    )
  end

  Promise.all(tasks):await()

  return true
end

function emitters.spin(obj: Model, scope: utility.scope): boolean
  if utility.lock(obj) then
    return true
  end

  -- fix. the. lag.
  -- https://devforum.roblox.com/t/selecting-a-model-moved-using-pivotto-on-every-frame-causes-severe-lag/3775544
  utility.try(`failed to emit spinning model '{obj:GetFullName()}' with error: %s`, Spin.emit, obj, scope)

  utility.unlock(obj)

  return true
end

function emitters.camera_shake(obj: RayValue, scope: utility.scope): boolean
  utility.try(`failed to emit camera shake '{obj:GetFullName()}' with error: %s`, CameraShake.emit, obj, scope)

  return true
end

function emitters.tween_property(obj: RayValue, scope: utility.scope): boolean
  if not obj.Parent or utility.lock(obj) then
    return true
  end

  utility.try(
    `failed to emit tween property '{obj:GetFullName()}' with error: %s`,
    TweenProperty.emit,
    obj.Parent,
    obj,
    scope
  )

  utility.unlock(obj)

  return true
end

function emitters.shockwave_ring(att: Attachment, obj: Part, scope: utility.scope): boolean
  utility.try(`failed to emit shockwave ring '{obj:GetFullName()}' with error: %s`, ShockwaveRing.emit, att, obj, scope)

  return true
end

function emitters.shockwave_debris(att: Attachment, obj: Part, scope: utility.scope): boolean
  utility.try(
    `failed to emit shockwave debris '{obj:GetFullName()}' with error: %s`,
    ShockwaveDebris.emit,
    att,
    obj,
    scope
  )

  return true
end

function emitters.shockwave_line(att: Attachment, obj: Part, scope: utility.scope): boolean
  utility.try(`failed to emit shockwave line '{obj:GetFullName()}' with error: %s`, ShockwaveLine.emit, att, obj, scope)

  return true
end

-- Dispatch function to determine which emitter to use and call it
function emitters.dispatch(
  obj: Instance,
  scope: utility.scope,
  sharedUncMap: { [Instance]: number },
  sharedRefMap: { [Instance]: Instance },
  shared_part_cache: any,
  legacyScale: number
): boolean
  local shouldCleanup = true

  if obj:IsA("ParticleEmitter") then
    shouldCleanup = emitters.particle(obj, scope, sharedUncMap, sharedRefMap, legacyScale)
  elseif obj:IsA("Beam") then
    shouldCleanup = emitters.beam(obj, scope, legacyScale)
  elseif obj:IsA("Trail") then
    shouldCleanup = emitters.trail(obj)
  elseif obj:HasTag(utility.BEZIER_TAG) then
    shouldCleanup = emitters.bezier(obj, scope)
  elseif utility.isMeshVFX(obj) then
    shouldCleanup = emitters.mesh(obj, scope, shared_part_cache, legacyScale)
  elseif obj:IsA("Model") then
    shouldCleanup = emitters.spin(obj, scope)
  elseif obj:IsA("RayValue") then
    if obj:HasTag(utility.SCREENSHAKE_TAG) then
      shouldCleanup = emitters.camera_shake(obj, scope)
    else
      shouldCleanup = emitters.tween_property(obj, scope)
    end
  end

  -- Handle shockwave emissions for Parts
  if obj:IsA("Part") then
    local att = utility.findFirstClassWithTag(obj, "Attachment", utility.SHOCKWAVE_TAG)

    if att then
      local name = obj.Parent.Name

      if name == "Rings" then
        shouldCleanup = emitters.shockwave_ring(att, obj, scope)
      elseif name == "Debris" then
        shouldCleanup = emitters.shockwave_debris(att, obj, scope)
      elseif name == "Lines" then
        shouldCleanup = emitters.shockwave_line(att, obj, scope)
      end
    end
  end

  return shouldCleanup
end

return emitters
