local types = require("@root/types")
local logger = require("@mod/logger")
local utility = require("@mod/utility")
local emitters = require("@root/emitters")

local Promise = require("@pkg/Promise")

local EffectSelectors = table.concat({
  "Beam",
  "Trail",
  "Sound",
  "ParticleEmitter",

  -- Beziers
  `.{utility.BEZIER_TAG}`,

  -- Lightning bolts
  `.{utility.LIGHTNING_TAG}`,

  -- Spin models
  "Model",

  -- Camera shakes
  "RayValue",

  -- Screen effects
  "BasePart[$Enabled=true]",

  -- Shockwave effects
  "#Rings > Part",
  "#Lines > Part",
  "#Debris > Part",
}, ",")

local effects = {}

local api_ref: types.Api?

local NOOP = function() end

local EMPTY_ENV: types.EmitEnv = {
  Finished = Promise.resolve(),
  Clear = NOOP,
}

function effects.init(api: types.Api)
  api_ref = api
end

function effects.deinit()
  api_ref = nil
end

local function emitWithContext(depth: number, context: { _promises: { any } }?, ...: Instance): types.EmitEnv
  if not api_ref or not api_ref.setup then
    logger.error("effects service not initialized")
    return EMPTY_ENV
  end

  local sharedUncMap: { [Instance]: number } = {}
  local sharedRefMap: { [Instance]: Instance } = {}

  local legacyScale = 1

  local list = { ... }
  local rootPromises = {}

  local function queryAndEmitDescendants(obj: Instance, baseDepth: number): { any }
    local allDesc = obj:QueryDescendants(EffectSelectors)
    local totalDesc = #allDesc

    if totalDesc == 0 then
      return {}
    end

    local promises = table.create(totalDesc)

    local skipCache: { [Instance]: boolean } = {}
    local depthCache: { [Instance]: number } = {}

    skipCache[obj] = false
    depthCache[obj] = baseDepth

    for _, desc in allDesc do
      local ancestors = {}
      local current = desc.Parent

      while depthCache[current] == nil do
        table.insert(ancestors, current)
        current = current.Parent
      end

      local shouldSkip = skipCache[current]
      local currentDepth = depthCache[current]

      for i = #ancestors, 1, -1 do
        local ancestor = ancestors[i]

        currentDepth += 1
        depthCache[ancestor] = currentDepth

        if not shouldSkip then
          shouldSkip = utility.shouldSkipNested(ancestor) or ancestor:HasTag(utility.EMIT_EXCLUDE_TAG)
        end

        skipCache[ancestor] = shouldSkip
      end

      if not shouldSkip then
        table.insert(
          promises,
          utility.createEmitPromise(effects, desc, depthCache[desc.Parent], function(scope)
            emitters.dispatch(desc, scope, sharedUncMap, sharedRefMap, api_ref.caches.shared_part, legacyScale)
          end, context)
        )
      end
    end

    return promises
  end

  for _, obj in list do
    -- screen effects
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
      scope._context = context

      local await = emitters.screen(obj, scope)

      if await then
        local innerPromises = queryAndEmitDescendants(obj, depth + 1)

        if #innerPromises > 0 then
          table.insert(
            rootPromises,
            Promise.all(innerPromises):finally(function()
              utility.unlock(obj, lockThread)
              utility.cleanupScope(scope)
            end)
          )
        else
          utility.unlock(obj, lockThread)
          utility.cleanupScope(scope)
        end
      end
    -- other effects
    else
      table.insert(
        rootPromises,
        utility.createEmitPromise(effects, obj, depth, function(scope)
          emitters.dispatch(obj, scope, sharedUncMap, sharedRefMap, api_ref.caches.shared_part, legacyScale)
        end, context)
      )

      if not utility.shouldSkipNested(obj) then
        local descendantPromises = queryAndEmitDescendants(obj, depth + 1)

        for _, promise in descendantPromises do
          table.insert(rootPromises, promise)
        end
      end
    end
  end

  local env = {} :: types.EmitEnv

  env.Finished = Promise.all(rootPromises)
  env.Clear = if context
    then function()
      for _, promise in context._promises do
        promise:cancel()
      end
      env.Finished:cancel()
    end
    else NOOP

  return env
end

function effects.emit(depth: number, ...: Instance): types.EmitEnv
  local context = { _promises = {} }
  return emitWithContext(depth, context, ...)
end

function effects.prepareEmitFolder(obj: Instance, folderName: string, scope: types.scope): Folder?
  local folder = obj:FindFirstChild(folderName)

  if folder and folder:IsA("Folder") then
    folder.Parent = nil
    table.insert(scope, folder)
    return folder
  end

  return nil
end

function effects.prepareEmitOnFinish(obj: Instance, scope: types.scope): Folder?
  return effects.prepareEmitFolder(obj, "EmitOnFinish", scope)
end

function effects.emitNested(part: Instance, depth: number, parentScope: types.scope?): types.EmitEnv
  if not api_ref or not api_ref.setup then
    return EMPTY_ENV
  end

  local children = part:GetChildren()

  if #children == 0 then
    return EMPTY_ENV
  end

  local context = if parentScope then parentScope._context else nil
  return emitWithContext(depth, context, table.unpack(children))
end

function effects.emitFromFolder(
  folder: Folder?,
  targetParent: Instance,
  depth: number,
  parentScope: types.scope?
): types.EmitEnv
  if not folder then
    return EMPTY_ENV
  end

  local children = folder:GetChildren()

  if #children == 0 then
    return EMPTY_ENV
  end

  for _, child in children do
    child.Parent = targetParent
  end

  local context = if parentScope then parentScope._context else nil
  return emitWithContext(depth, context, table.unpack(children))
end

function effects.emitOnFinish(
  emitOnFinish: Folder?,
  targetParent: Instance,
  depth: number,
  parentScope: types.scope?
): types.EmitEnv
  return effects.emitFromFolder(emitOnFinish, targetParent, depth, parentScope)
end

return effects
