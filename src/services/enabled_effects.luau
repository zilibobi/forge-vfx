local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local attr = require("@mod/attributes")
local types = require("@root/types")
local utility = require("@mod/utility")
local emitters = require("@root/emitters")

local enabled_effects = {}

function enabled_effects.init(scope: types.scope, shared_part_cache: any, effects_service: any)
  local enabledScopes = {}
  local ancestryConnections: { [Instance]: RBXScriptConnection } = {}

  local function removeEnabledEffect(obj: Instance)
    local effectScope = enabledScopes[obj]

    if effectScope then
      utility.cleanupScope(effectScope)
    end

    enabledScopes[obj] = nil
  end

  local function removeEnabledEffectFull(obj: Instance)
    removeEnabledEffect(obj)

    local conn = ancestryConnections[obj]

    if conn then
      conn:Disconnect()
      ancestryConnections[obj] = nil
    end
  end

  local function addEnabledEffect(obj: Instance)
    -- Find which effect type this object is
    local effectConfig = nil

    for _, config in emitters.enabled_registry do
      if config.check(obj) then
        effectConfig = config
        break
      end
    end

    if not effectConfig then
      return
    end

    local tempScope = {} :: { any }
    local effectScope = {} :: { any }

    table.insert(effectScope, tempScope)

    enabledScopes[obj] = effectScope

    if not ancestryConnections[obj] then
      ancestryConnections[obj] = obj.AncestryChanged:Connect(function()
        if obj:IsDescendantOf(workspace) or (obj.Parent and obj.Parent:HasTag("AllowEmitting")) then
          if not enabledScopes[obj] then
            addEnabledEffect(obj)
          end
        else
          removeEnabledEffect(obj)
        end
      end)
    end

    local function onEnabled(enabled: boolean?)
      if enabled == nil then
        enabled = attr.get(obj, "Enabled", true)
      end

      local canEmit = utility.isForceEmitting(obj)
        or obj:IsDescendantOf(workspace)
        or (obj.Parent and obj.Parent:HasTag("AllowEmitting"))

      if enabled and not canEmit then
        return
      end

      if enabled then
        utility.cleanupScope(tempScope)

        local last = 0

        -- inherit the user's emit context (if any) so that particles spawned
        -- by this enabled-effect loop are pausable via the same env:Pause()
        -- call that started them. we use a metatable so _paused and
        -- _pausableInstances read through to the parent without needing to
        -- keep them in sync manually. the local _promises/_scopes fields stay
        -- isolated because stopEmitDuration must only cancel this loop's work.
        local parentContext = utility.getCurrentContext()
        local cancelToken = setmetatable(
          { _promises = {}, _scopes = {} },
          if parentContext then { __index = parentContext } else nil
        )

        utility.setEnabledCancelToken(obj, cancelToken :: any)

        table.insert(
          tempScope,
          RunService.RenderStepped:Connect(function()
            -- skip emission while the owning user context is paused.
            if cancelToken._paused then
              return
            end

            local rate = attr.get(obj, "Rate", 5)
            local speed = attr.getState(obj, "SpeedOverride", 1)

            if speed == 0 then
              return
            end

            if os.clock() - last <= (1 / rate) / speed then
              return
            end

            last = os.clock()

            local emitScope = {}
            emitScope.depth = 0
            emitScope.effects = effects_service
            emitScope._context = cancelToken

            table.insert(cancelToken._scopes, emitScope)

            -- bind the cancel token to this render tick's coroutine so
            -- pause-aware tweens/timers created inside effectConfig.emit
            -- pick it up (and through its metatable, the parent context's
            -- _paused flag).
            utility.bindContext(cancelToken)

            effectConfig.emit(obj, emitScope, shared_part_cache)

            local idx = table.find(cancelToken._scopes, emitScope)
            if idx then
              table.remove(cancelToken._scopes, idx)
            end

            utility.cleanupScope(emitScope)
          end)
        )
      else
        utility.cleanupScope(tempScope)
      end
    end

    table.insert(effectScope, attr.hook(obj, "Enabled", onEnabled))

    onEnabled()
  end

  for _, obj in CollectionService:GetTagged(utility.ENABLED_VFX_TAG) do
    addEnabledEffect(obj)
  end

  CollectionService:GetInstanceAddedSignal(utility.ENABLED_VFX_TAG):Connect(addEnabledEffect)
  CollectionService:GetInstanceRemovedSignal(utility.ENABLED_VFX_TAG):Connect(removeEnabledEffectFull)

  table.insert(scope, function()
    for obj, effectScope in enabledScopes do
      utility.cleanupScope(effectScope)
    end

    for obj, conn in ancestryConnections do
      conn:Disconnect()
    end

    table.clear(ancestryConnections)
  end)
end

return enabled_effects
