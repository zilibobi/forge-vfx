local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local types = require("@root/types")
local utility = require("@mod/utility")
local emitters = require("@root/emitters")

local enabled_effects = {}

function enabled_effects.init(scope: types.scope, shared_part_cache: any, effects_service: any)
  local enabledScopes = {}

  local function removeEnabledEffect(obj: Instance)
    local effectScope = enabledScopes[obj]

    if effectScope then
      utility.cleanupScope(effectScope)
    end

    enabledScopes[obj] = nil
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
    local preEffectScope = {} :: { any }

    table.insert(preEffectScope, tempScope)

    enabledScopes[obj] = preEffectScope

    table.insert(
      preEffectScope,
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

    if not obj:IsDescendantOf(workspace) and (if obj.Parent then not obj.Parent:HasTag("AllowEmitting") else false) then
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

            last = os.clock()

            local emitScope = {}
            emitScope.depth = 0
            emitScope.effects = effects_service

            effectConfig.emit(obj, emitScope, shared_part_cache)

            utility.cleanupScope(emitScope)
          end)
        )
      else
        utility.cleanupScope(tempScope)
      end
    end

    table.insert(preEffectScope, obj:GetAttributeChangedSignal("Enabled"):Connect(onEnabled))

    onEnabled()
  end

  for _, obj in CollectionService:GetTagged(utility.ENABLED_VFX_TAG) do
    addEnabledEffect(obj)
  end

  CollectionService:GetInstanceAddedSignal(utility.ENABLED_VFX_TAG):Connect(addEnabledEffect)
  CollectionService:GetInstanceRemovedSignal(utility.ENABLED_VFX_TAG):Connect(removeEnabledEffect)

  table.insert(scope, function()
    for _, effectScope in enabledScopes do
      utility.cleanupScope(effectScope)
    end
  end)
end

return enabled_effects
