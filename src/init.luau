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

VFX Forge Developer License (VFX-DL) Version 1.1

Copyright (c) 2025 zilibobi

1. Definitions.
   - "Module" means the source code and any compiled form of the Emit Module.
   - "You" means any individual or organization exercising the rights granted herein.
   - "Derivative Work" means any work based upon or incorporating the Module.
   - "Roblox Experience" means a user-facing game or simulation that runs on the
   Roblox platform, created using Roblox Studio and played via the Roblox client.

2. Grant of Rights.
   Permission is hereby granted, free of charge, to You to use, reproduce,
   prepare Derivative Works of, publicly display, publicly perform, sublicense,
   and distribute the Module, **solely when embedded in the runtime environment of
   a Roblox Experience** (including playtesting in Roblox Studio), and **not** when
   loaded by any Roblox Studio plugin or other developer tool, running in any context
   that has access to API methods or permissions unavailable to runtime scripts within
   Roblox Experiences (excluding the Roblox Studio command bar feature, when used for
   the purpose of viewing finished effects). You may distribute the Module or Derivative
   Work to other developers, provided they use it only within the permitted runtime
   context described above.

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

local logger = require("@mod/logger")
local utility = require("@mod/utility")

local Bezier = require("@vfx/bezier")
local Screen = require("@vfx/screen")
local CameraShake = require("@vfx/camera_shake")
local ShockwaveRing = require("@vfx/shockwave_ring")
local ShockwaveLine = require("@vfx/shockwave_line")
local ShockwaveDebris = require("@vfx/shockwave_debris")

local Promise = require("@pkg/Promise")

local caches = require("@srv/caches")
local emitters = require("@self/emitters")
local texture_loader = require("@srv/texture_loader")
local enabled_effects = require("@srv/enabled_effects")

local PluginContext = utility.PLUGIN_CONTEXT
local ServerContext = utility.SERVER_CONTEXT

type params = {}

local api = {}

api.scope = {}
api.setup = false

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

  api.caches = caches.init(api.scope)

  texture_loader.init(api.scope)
  enabled_effects.init(api.scope, api.caches.shared_part)

  CameraShake.init()

  Bezier.init(api.caches.shared_part)
  ShockwaveRing.init(api.caches.shared_part)
  ShockwaveLine.init(api.caches.shared_part)
  ShockwaveDebris.init(api.caches.shared_part)
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

  local cleanupObjects = CollectionService:GetTagged(utility.CLEANUP_TAG)

  for _, obj in cleanupObjects do
    obj:Destroy()
  end
end

local function fullEmit(scale: number, depth: number, ...: Instance)
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

        local shouldCleanup =
          emitters.dispatch(obj, scope, sharedUncMap, sharedRefMap, api.caches.shared_part, legacyScale)

        if shouldCleanup then
          utility.cleanupScope(scope)
        end
      end

      run()
      resolve()
    end)
  end

  local list = { ... }
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

        if anc and not utility.isSpinModelStatic(anc) then
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

  emitAll(depth, list, rootPromises)

  local env = {
    Finished = Promise.all(rootPromises),
  }

  return env
end

function api.emit(vfxOrScale: number | Instance, ...: Instance)
  if typeof(vfxOrScale) ~= "number" then
    return fullEmit(1, 0, vfxOrScale, ...)
  else
    return fullEmit(vfxOrScale, 0, ...)
  end
end

function api.emitWithDepth(depth: number, ...: Instance)
  return fullEmit(1, depth, ...)
end

return api
