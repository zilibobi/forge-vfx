local ObjectCache = require("@obj/ObjectCache")

local utility = require("@mod/utility")

local caches = {}

function caches.init(scope: { any })
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

    utility.protectParent(scope, parent)

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

  local result = {
    shared_part = shared_part_cache,
  }

  table.insert(scope, function()
    shared_part_cache:destroy()
  end)

  return result
end

return caches
