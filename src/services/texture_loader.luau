local CollectionService = game:GetService("CollectionService")

local ObjectCache = require(script.Parent.Parent.obj.ObjectCache)
local utility = require(script.Parent.Parent.mod.utility)

local texture_loader = {}

function texture_loader.init(scope: utility.scope)
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

  utility.protectParent(scope, parent)

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

      local loadScope = {}
      local snapshotScope = {}

      table.insert(loadScope, snapshotScope)

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

          if utility.PLUGIN_CONTEXT then
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

      if utility.PLUGIN_CONTEXT then
        local run = utility.reboundfn(1, refresh)

        table.insert(loadScope, obj.DescendantAdded:Connect(run))
        table.insert(loadScope, obj.DescendantRemoving:Connect(run))
      end

      preloadScopes[ref] = loadScope
    else
      local loadScope = {}
      local snapshotScope = {}

      table.insert(loadScope, snapshotScope)

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

      if utility.PLUGIN_CONTEXT then
        local run = utility.reboundfn(1, refresh)

        table.insert(loadScope, ref.DescendantAdded:Connect(run))
        table.insert(loadScope, ref.DescendantRemoving:Connect(run))
      end

      preloadScopes[ref] = loadScope
    end
  end

  for _, ref in CollectionService:GetTagged(utility.TEXTURE_LOAD_TAG) do
    loadTextures(ref)
  end

  CollectionService:GetInstanceAddedSignal(utility.TEXTURE_LOAD_TAG):Connect(loadTextures)
  CollectionService:GetInstanceRemovedSignal(utility.TEXTURE_LOAD_TAG):Connect(function(ref)
    local loadScope = preloadScopes[ref]

    if loadScope then
      utility.cleanupScope(loadScope)
      preloadScopes[ref] = nil
    end
  end)

  table.insert(scope, function()
    texture_cache:destroy()

    for _, loadScope in preloadScopes do
      utility.cleanupScope(loadScope)
    end
  end)
end

return texture_loader
