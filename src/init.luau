-- The license is placed inside a string in order for it to be preserved when the code is decompiled
-- Even if the engine retains the entire string in memory, it's only around 3.5kB
local _ = [[
Preamble.
Disclaimer: nothing stated in this preamble is legal advice.

This is a simple license that allows anyone to use the emit module in their Roblox games.

1. You cannot use the module in anything that isn't a Roblox game. For example, it means
that you cannot create a plugin using this module.

2. You are allowed to use the module commercially in your games.

3. You are free to share the module with other developers so they can use it in their games,
as long as the license is retained.

4. You can modify and share the module as long as you follow the terms of the license. All
derivates of the module must have the same license.

5. If you break the terms and conditions of the license, you are required to stop the use and
distribution of the module immediately.

End of preamble.

VFX Forge Developer License (VFX-DL) Version 1.0

Copyright (c) 2025 zilibobi

1. Definitions.
   - "Module" means the source code and any compiled form of the Emit Module.
   - "You" means any individual or organization exercising the rights granted herein.
   - "Derivative Work" means any work based upon or incorporating the Module.
   - "Roblox Experience" means a user-facing game or simulation that runs on the
   Roblox platform, created using Roblox Studio and played via the Roblox client.

2. Grant of Rights.
   Permission is hereby granted, free of charge, to You to use, reproduce,
   prepare Derivative Works of, publicly display, publicly perform,
   sublicense, and distribute the Module, **solely when embedded in the runtime
   environment of a Roblox Experience** (including playtesting in Roblox Studio),
   and **not** when loaded by any Roblox Studio plugin or other developer tool,
   running in any context that has access to API methods or permissions unavailable
   to runtime scripts within Roblox Experiences. You may distribute the Module or
   Derivative Work to other developers, provided they use it only within the permitted
   runtime context described above.

3. Conditions.
   a. Copyleft.
       Any Derivative Work, including modified or extended versions of the Module, that
       You distribute must be licensed under the exact same terms as this VFX-DL.
   b. Redistribution.
       You must include a copy of this license text with any distribution of the Module or Derivative Work.
   c. No Other Contexts.
       You may not embed, load, or distribute the Module within any Roblox Studio
       plugin, editor extension, command-line tool, test harness, or any code running
       under Studio outside of normal game runtime.

4. Disclaimer of Warranty.
    The Module is provided "AS IS," without warranty of any kind, express or implied,
    including but not limited to the warranties of merchantability, fitness for a
    particular purpose, and noninfringement.

5. Limitation of Liability.
    In no event shall the authors or copyright holders be liable for any claim,
    damages, or other liability arising from, out of, or in connection with the
    Module or the use or other dealings in the Module.

6. Termination.
    If You violate the terms of this License, Your rights under this VFX-DL will
    terminate automatically. Upon termination, You must cease all use and distribution
    of the Module and any Derivative Works.

7. Versioning.
    This license applies to Version 1.0 of the VFX-DL. Future versions may be published
    by the copyright holder.

8. Commercial use.
    This License permits commercial use within the scope defined in Section 2.

9. Trademarks and branding.
    Nothing in this License grants permission to use the trade names, trademarks, service marks,
    or product names of the Licensor.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local logger = require(script.mod.logger)
local utility = require(script.mod.utility)

local Beam = require(script.effects.beam)
local Spin = require(script.effects.spin)
local Mesh = require(script.effects.mesh)
local Bezier = require(script.effects.bezier)
local Screen = require(script.effects.screen)
local Particle = require(script.effects.particle)
local CameraShake = require(script.effects.camera_shake)
local TweenProperty = require(script.effects.tween_property)
local ShockwaveRing = require(script.effects.shockwave_ring)
local ShockwaveLine = require(script.effects.shockwave_line)
local ShockwaveDebris = require(script.effects.shockwave_debris)

local Promise = require(script.pkg.Promise)
local ObjectCache = require(script.obj.ObjectCache)

local PluginContext = script:FindFirstAncestorOfClass("Plugin")
local ServerContext = RunService:IsServer() or PluginContext

type params = {}

local api = {}

api.scope = {}
api.setup = false

local function assembleMeshVFX(start: BasePart, scope: {})
  if not api.setup then
    logger.error("API not initialized")
  end

  local id = utility.getRanomId()

  if start:IsA("Part") then
    local objAbstr = api.caches.shared_part:get(id)
    objAbstr.CFrame = start.CFrame

    local obj = objAbstr._getReal()

    utility.copyProperties(start, obj, utility.COPY_PART_PROPERTIES)
    utility.copyProperties(start, obj, utility.COPY_EXTENDED_PART_PROPERTIES)

    local clone = start:Clone()

    for _, child in clone:GetChildren() do
      child.Parent = obj
    end

    clone:Destroy()

    table.insert(scope, function()
      api.caches.shared_part:free(id)
    end)

    return objAbstr
  else
    local clone = start:Clone()
    clone.Archivable = false
    clone.Locked = true
    clone.Parent = workspace.Terrain

    table.insert(scope, clone)

    return clone
  end
end

function api.init(params: params?)
  if api.setup then
    return
  end

  if ServerContext then
    task.spawn(function()
      local done = false
      local tries = 0

      local lastErr

      repeat
        tries += 1

        local ok, err = pcall(utility.setCollisionGroups, utility.COLLISION_GROUPS)

        done = ok
        lastErr = err

        if not done then
          task.wait(tries)
        end
      until done or tries >= 5

      if not done then
        logger.warn(
          `couldn't register necessary collision groups after {tries} tries with the last error being: {lastErr}`
        )
      end
    end)
  end

  api.setup = true

  if RunService:IsServer() and not PluginContext then
    return
  end

  shared.vfx = api

  local shared_part_cache

  do
    local template = Instance.new("Part")
    template.Transparency = 1
    template.Anchored = true
    template.CanCollide = false
    template.CanQuery = false
    template.Locked = true

    local parent = Instance.new("Folder")
    parent.Name = "DO_NOT_REMOVE_ForgeSharedPartCache"
    parent.Archivable = false
    parent.Parent = workspace.Terrain

    utility.protectParent(api.scope, parent)

    shared_part_cache = ObjectCache.new(template, parent, {
      size = 150,
      on_free = function(item)
        local part = item.value

        part.Transparency = 1

        part.Anchored = true
        part.CanQuery = false
        part.CanCollide = false

        part.CollisionGroup = "ForgeMouseIgnore"

        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero

        -- this is probably not very good for performance lol
        -- but I don't think there's currently a more reasonable
        -- way of recycling parts
        part:ClearAllChildren()
      end,
    })
  end

  api.caches = {
    shared_part = shared_part_cache,
  }

  table.insert(api.scope, function()
    shared_part_cache:destroy()
  end)

  CameraShake.init()

  Bezier.init(shared_part_cache)
  ShockwaveRing.init(shared_part_cache)
  ShockwaveLine.init(shared_part_cache)
  ShockwaveDebris.init(shared_part_cache)

  do
    local template = Instance.new("Decal")

    local parent = Instance.new("Part")
    parent.Name = "DO_NOT_REMOVE_ForgeTextureCache"
    parent.Transparency = 1
    parent.Size = Vector3.zero
    parent.Archivable = false
    parent.Anchored = true
    parent.CanCollide = false
    parent.CanQuery = false
    parent.Locked = true
    parent.Parent = workspace.Terrain

    utility.protectParent(api.scope, parent)

    local texture_cache = ObjectCache.new(template, parent, {
      size = 120 * 3,
      on_free = function(item)
        item.value.Texture = ""
      end,
    })

    local preloadScopes = {}

    local function loadTextures(ref: Instance)
      if ref:IsDescendantOf(workspace.Terrain) then
        return
      end

      if utility.isMeshVFX(ref) then
        local obj = ref:FindFirstChild("Start")

        if not obj or not obj:IsA("BasePart") then
          return
        end

        local scope = {}
        local snapshotScope = {}

        table.insert(scope, snapshotScope)

        local function refresh()
          utility.cleanupScope(snapshotScope)

          local decals, flipbooks = utility.getMeshDecals(ref, obj)

          local function add(src: Decal | string)
            local tex = typeof(src) == "Instance" and src.Texture or src

            if tex == "" then
              return
            end

            local d = texture_cache:get(tex)
            d.Texture = tex

            table.insert(snapshotScope, function()
              texture_cache:free(tex)
            end)
          end

          for _, d in decals do
            add(d)
          end

          for v, list in flipbooks do
            local temp = false

            if PluginContext then
              for _, tag in CollectionService:GetTags(v) do
                if tag:match("^_local_flipbook_") then
                  temp = true
                  break
                end
              end
            end

            for _, id in list do
              add(`{temp and "rbxtemp://" or "rbxassetid://"}{id}`)
            end
          end
        end

        refresh()

        if PluginContext then
          local run = utility.reboundfn(1, refresh)

          table.insert(scope, obj.DescendantAdded:Connect(run))
          table.insert(scope, obj.DescendantRemoving:Connect(run))
        end

        preloadScopes[ref] = scope
      else
        local scope = {}
        local snapshotScope = {}

        table.insert(scope, snapshotScope)

        local function refresh()
          utility.cleanupScope(snapshotScope)

          local function check(obj: Instance)
            if not obj:IsA("ParticleEmitter") then
              return
            end

            local tex = obj.Texture

            if tex == "" then
              return
            end

            local d = texture_cache:get(tex)
            d.Texture = tex

            table.insert(snapshotScope, function()
              texture_cache:free(tex)
            end)
          end

          check(ref)

          for _, obj in ref:GetDescendants() do
            check(obj)
          end
        end

        refresh()

        if PluginContext then
          local run = utility.reboundfn(1, refresh)

          table.insert(scope, ref.DescendantAdded:Connect(run))
          table.insert(scope, ref.DescendantRemoving:Connect(run))
        end

        preloadScopes[ref] = scope
      end
    end

    for _, ref in CollectionService:GetTagged(utility.TEXTURE_LOAD_TAG) do
      loadTextures(ref)
    end

    CollectionService:GetInstanceAddedSignal(utility.TEXTURE_LOAD_TAG):Connect(loadTextures)
    CollectionService:GetInstanceRemovedSignal(utility.TEXTURE_LOAD_TAG):Connect(function(ref)
      local scope = preloadScopes[ref]

      if scope then
        utility.cleanupScope(scope)
        preloadScopes[ref] = nil
      end
    end)

    table.insert(api.scope, function()
      texture_cache:destroy()

      for _, scope in preloadScopes do
        utility.cleanupScope(scope)
      end
    end)
  end

  do
    local enabledScopes = {}

    local function removeEnabledEffect(obj: Instance)
      local scope = enabledScopes[obj]

      if scope then
        utility.cleanupScope(scope)
      end

      enabledScopes[obj] = nil
    end

    local function addEnabledEffect(obj: Instance)
      local isMesh = utility.isMeshVFX(obj)
      local isBezier = obj:HasTag(utility.BEZIER_TAG)

      if not isMesh and not isBezier then
        return
      end

      local scope = {}
      local tempScope = {}

      table.insert(scope, tempScope)

      enabledScopes[obj] = scope

      table.insert(
        scope,
        obj.AncestryChanged:Connect(function()
          if obj:IsDescendantOf(workspace) or (obj.Parent and obj.Parent:HasTag("AllowEmitting")) then
            if not enabledScopes[obj] then
              addEnabledEffect(obj)
            end
          else
            removeEnabledEffect(obj)
          end
        end)
      )

      if
        not obj:IsDescendantOf(workspace) and (if obj.Parent then not obj.Parent:HasTag("AllowEmitting") else false)
      then
        return
      end

      local function onEnabled()
        local enabled = utility.getAttribute(obj, "Enabled", true)

        if enabled then
          local last = 0

          table.insert(
            tempScope,
            RunService.RenderStepped:Connect(function()
              local rate = utility.getAttribute(obj, "Rate", 5)
              local speed = obj:GetAttribute("SpeedOverride") or 1

              if speed == 0 then
                return
              end

              if os.clock() - last <= (1 / rate) / speed then
                return
              end

              local emitScope = {}
              emitScope.depth = 0

              local function cleanup()
                utility.cleanupScope(emitScope)
              end

              table.insert(api.scope, cleanup)

              if isMesh then
                local start = obj:FindFirstChild("Start")

                if not start then
                  obj:RemoveTag(utility.ENABLED_VFX_TAG)
                  return
                end

                last = os.clock()

                for i = 1, utility.getAttribute(obj, "EmitCount", 1) do
                  utility.try(
                    `failed to emit mesh '{obj:GetFullName()}' with error: %s`,
                    Mesh.emit,
                    obj,
                    assembleMeshVFX(start, emitScope),
                    emitScope,
                    1,
                    true
                  )
                end
              elseif isBezier then
                local part = obj:FindFirstChildOfClass("Part")

                if not part then
                  return
                end

                last = os.clock()

                local clone = part:Clone()
                clone.Locked = true

                table.insert(emitScope, clone)

                utility.try(
                  `failed to emit bezier '{obj:GetFullName()}' with error: %s`,
                  Bezier.emit,
                  obj,
                  clone,
                  emitScope,
                  true
                )
              end

              local index = table.find(api.scope, cleanup)

              if index then
                table.remove(api.scope, index)
              end

              utility.cleanupScope(emitScope)
            end)
          )
        else
          utility.cleanupScope(tempScope)
        end
      end

      table.insert(scope, obj:GetAttributeChangedSignal("Enabled"):Connect(onEnabled))

      onEnabled()
    end

    for _, obj in CollectionService:GetTagged(utility.ENABLED_VFX_TAG) do
      addEnabledEffect(obj)
    end

    CollectionService:GetInstanceAddedSignal(utility.ENABLED_VFX_TAG):Connect(addEnabledEffect)
    CollectionService:GetInstanceRemovedSignal(utility.ENABLED_VFX_TAG):Connect(removeEnabledEffect)

    table.insert(api.scope, function()
      for _, scope in enabledScopes do
        utility.cleanupScope(scope)
      end
    end)
  end
end

function api.deinit()
  if not api.setup then
    return
  end

  api.setup = false

  shared.vfx = nil

  if RunService:IsServer() and not PluginContext then
    return
  end

  utility.cleanupScope(api.scope)

  Bezier.deinit()
  CameraShake.deinit()
  ShockwaveRing.deinit()
  ShockwaveLine.deinit()
  ShockwaveDebris.deinit()
end

function api.emit(arg0, ...)
  if not api.setup then
    logger.error("not initialized")
  end

  local sharedUncMap: { [Instance]: number } = {}
  local sharedRefMap: { [Instance]: Instance } = {}

  local legacyScale = 1

  local function emit(obj: Instance, depth: number)
    return Promise.new(function(resolve)
      local function run()
        local scope = {}
        scope.depth = depth

        if obj:IsA("ParticleEmitter") then
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

            utility.try(
              `failed to emit particle '{obj:GetFullName()}' with error: %s`,
              Particle.emit,
              obj,
              clone,
              scope,
              legacyScale
            )

            sharedUncMap[ancestor] -= 1

            if sharedUncMap[ancestor] <= 0 then
              utility.cleanupScope(scope)
            end
          else
            utility.try(
              `failed to emit particle '{obj:GetFullName()}' with error: %s`,
              Particle.emit,
              obj,
              obj,
              scope,
              legacyScale
            )

            utility.cleanupScope(scope)
          end
        elseif obj:IsA("Beam") then
          local clone = obj:Clone()
          clone.Archivable = false
          clone.Parent = workspace.Terrain

          table.insert(scope, clone)

          utility.try(
            `failed to emit beam '{obj:GetFullName()}' with error: %s`,
            Beam.emit,
            obj,
            clone,
            scope,
            legacyScale
          )
          utility.cleanupScope(scope)
        elseif obj:IsA("Trail") then
          obj.Enabled = true
        elseif obj:HasTag(utility.BEZIER_TAG) then
          local part = obj:FindFirstChildOfClass("Part")

          if not part then
            return
          end

          if obj:GetAttribute("Enabled") then
            obj:SetAttribute("Enabled", false)
          end

          local clone = part:Clone()
          clone.Locked = true

          table.insert(scope, clone)

          utility.try(`failed to emit bezier '{obj:GetFullName()}' with error: %s`, Bezier.emit, obj, clone, scope)
          utility.cleanupScope(scope)
        elseif utility.isMeshVFX(obj) then
          local start = obj:FindFirstChild("Start")

          if not start then
            return
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
                  assembleMeshVFX(start, scope),
                  scope,
                  legacyScale
                )

                resolve()
              end)
            )
          end

          Promise.all(tasks):await()

          utility.cleanupScope(scope)
        elseif obj:IsA("Model") then
          if utility.lock(obj) then
            return
          end

          -- fix. the. lag.
          -- https://devforum.roblox.com/t/selecting-a-model-moved-using-pivotto-on-every-frame-causes-severe-lag/3775544
          utility.try(`failed to emit spinning model '{obj:GetFullName()}' with error: %s`, Spin.emit, obj, scope)
          utility.cleanupScope(scope)

          utility.unlock(obj)
        elseif obj:IsA("RayValue") then
          if obj:HasTag(utility.SCREENSHAKE_TAG) then
            utility.try(
              `failed to emit camera shake '{obj:GetFullName()}' with error: %s`,
              CameraShake.emit,
              obj,
              scope
            )

            utility.cleanupScope(scope)
          else
            if not obj.Parent or utility.lock(obj) then
              return
            end

            utility.try(
              `failed to emit tween property '{obj:GetFullName()}' with error: %s`,
              TweenProperty.emit,
              obj.Parent,
              obj,
              scope
            )

            utility.unlock(obj)
            utility.cleanupScope(scope)
          end
        end

        if obj:IsA("Part") then
          local att = utility.findFirstClassWithTag(obj, "Attachment", utility.SHOCKWAVE_TAG)

          if att then
            local name = obj.Parent.Name

            if name == "Rings" then
              utility.try(
                `failed to emit shockwave ring '{obj:GetFullName()}' with error: %s`,
                ShockwaveRing.emit,
                att,
                obj,
                scope
              )

              utility.cleanupScope(scope)
            elseif name == "Debris" then
              utility.try(
                `failed to emit shockwave debris '{obj:GetFullName()}' with error: %s`,
                ShockwaveDebris.emit,
                att,
                obj,
                scope
              )

              utility.cleanupScope(scope)
            elseif name == "Lines" then
              utility.try(
                `failed to emit shockwave line '{obj:GetFullName()}' with error: %s`,
                ShockwaveLine.emit,
                att,
                obj,
                scope
              )

              utility.cleanupScope(scope)
            end
          end
        end
      end

      run()
      resolve()
    end)
  end

  local list = { ... }

  if typeof(arg0) ~= "number" then
    table.insert(list, arg0)
  else
    legacyScale = arg0
  end

  local rootPromises = {}

  local function emitAll(depth: number, children: { Instance }, promises: {})
    for _, obj in children do
      if
        obj:IsA("BasePart")
        and obj:GetAttribute("Enabled")
        and not utility.findFirstClassWithTag(obj, "Attachment", utility.SHOCKWAVE_TAG)
      then
        if utility.lock(obj) then
          continue
        end

        local anc = obj:FindFirstAncestorOfClass("Model")

        if
          anc
          and (
            anc:GetAttribute("SpinRotation") ~= vector.zero
            or anc:GetAttribute("Scale_Start") ~= 1
            or anc:GetAttribute("Scale_End") ~= 1
          )
        then
          continue
        end

        local lockThread = coroutine.running()

        local scope = {}
        scope.depth = depth

        local await =
          utility.try(`failed to emit screen effect '{obj:GetFullName()}' with error: %s`, Screen.emit, obj, scope)

        if await then
          local descendants = obj:GetDescendants()

          if #descendants == 0 then
            utility.cleanupScope(scope)
            return
          end

          local inner = {}

          emitAll(depth + 1, obj:GetChildren(), inner)

          table.insert(
            rootPromises,
            Promise.all(inner):finally(function()
              utility.unlock(obj, lockThread)
              utility.cleanupScope(scope)
            end)
          )
        end
      else
        table.insert(promises, emit(obj, depth))

        if
          not obj:HasTag(utility.BEZIER_TAG)
          and not utility.isMeshVFX(obj)
          and not (obj:IsA("BasePart") and utility.findFirstClassWithTag(obj, "Attachment", utility.SHOCKWAVE_TAG))
        then
          emitAll(depth + 1, obj:GetChildren(), promises)
        end
      end
    end
  end

  emitAll(0, list, rootPromises)

  local env = {
    Finished = Promise.all(rootPromises),
  }

  return env
end

return api
