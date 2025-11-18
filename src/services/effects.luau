local types = require("@root/types")
local logger = require("@mod/logger")
local utility = require("@mod/utility")
local emitters = require("@root/emitters")

local Promise = require("@pkg/Promise")

local effects = {}

local api_ref: types.Api?

function effects.init(api: types.Api)
  api_ref = api
end

function effects.deinit()
  api_ref = nil
end

-- Emits nested effects from a list of instances
-- This is the function that effects should use for emitting nested effects
function effects.emit(depth: number, ...: Instance): types.EmitEnv
  if not api_ref or not api_ref.setup then
    logger.error("effects service not initialized")
    return { Finished = Promise.resolve() }
  end

  local sharedUncMap: { [Instance]: number } = {}
  local sharedRefMap: { [Instance]: Instance } = {}

  local legacyScale = 1

  local list = { ... }
  local rootPromises = {}

  local function emitAll(depth: number, children: { Instance }, promises: {})
    for _, obj in children do
      -- Special handling for screen effects
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
        scope.effects = effects

        local await = emitters.screen(obj, scope)

        if await then
          local descendants = obj:GetDescendants()

          if #descendants == 0 then
            utility.cleanupScope(scope)
            continue
          end

          local inner = {}

          emitAll(depth + 1, obj:GetChildren(), inner)

          table.insert(
            promises,
            Promise.all(inner):finally(function()
              utility.unlock(obj, lockThread)
              utility.cleanupScope(scope)
            end)
          )
        end
      else
        table.insert(
          promises,
          Promise.new(function(resolve)
            local scope = {}
            scope.depth = depth
            scope.effects = effects

            emitters.dispatch(obj, scope, sharedUncMap, sharedRefMap, api_ref.caches.shared_part, legacyScale)
            utility.cleanupScope(scope)

            resolve()
          end)
        )

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

-- Helper function to prepare EmitOnFinish folder
-- Call this when setting up an effect to extract the EmitOnFinish folder
-- Returns the EmitOnFinish folder or nil
function effects.prepareEmitOnFinish(obj: Instance, scope: types.scope): Folder?
  local emitOnFinish = obj:FindFirstChild("EmitOnFinish")

  if emitOnFinish and emitOnFinish:IsA("Folder") then
    emitOnFinish.Parent = nil
    table.insert(scope, emitOnFinish)
    return emitOnFinish
  end

  return nil
end

-- Helper function to emit nested effects during the effect
-- Call this to emit effects that are children of the cloned part
-- Returns an env with Finished promise that resolves when all nested effects finish
function effects.emitNested(part: Instance, depth: number): types.EmitEnv
  if not api_ref or not api_ref.setup then
    return { Finished = Promise.resolve() }
  end

  local children = part:GetChildren()

  if #children == 0 then
    return { Finished = Promise.resolve() }
  end

  return effects.emit(depth, table.unpack(children))
end

-- Helper function to emit EmitOnFinish effects at the end of an effect
-- Call this when the effect finishes to emit the EmitOnFinish children
-- The children will be parented to the targetParent before emitting
-- Returns an env with Finished promise that resolves when all EmitOnFinish effects finish
function effects.emitOnFinish(emitOnFinish: Folder?, targetParent: Instance, depth: number): types.EmitEnv
  if not emitOnFinish then
    return { Finished = Promise.resolve() }
  end

  local children = emitOnFinish:GetChildren()

  if #children == 0 then
    return { Finished = Promise.resolve() }
  end

  for _, child in children do
    child.Parent = targetParent
  end

  return effects.emit(depth, table.unpack(children))
end

return effects
