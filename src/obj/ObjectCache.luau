local utility = require("../mod/utility")

local RECYCLE_INTERVAL = 15

local cache = {}
cache.__index = cache

type item = {
  key: any,
  value: Instance,

  added: number,
  dependents: number,
}

type params = {
  size: number?,
  excess_lifetime: number?,
  on_free: ((item) -> ())?,
}

export type ObjectCache = typeof(cache) & {
  ref: Instance,
  parent: Instance?,

  params: params,

  amount: number,
  restore_amount: number,

  part_mode: boolean,

  item_map: { [any]: item },
  unused: { item },

  scope: { unknown },
}

local function reconcile(a, b)
  for k, v in b do
    if a[k] == nil then
      a[k] = v
    end
  end

  return a
end

local moveParts: { BasePart } = table.create(10_000)
local movePartCFrames: { CFrame } = table.create(10_000)

local partUpdateScheduled = false

local bulkPartMoveThread = coroutine.create(function()
  while true do
    workspace:BulkMoveTo(moveParts, movePartCFrames, Enum.BulkMoveMode.FireCFrameChanged)

    table.clear(moveParts)
    table.clear(movePartCFrames)

    partUpdateScheduled = false

    coroutine.yield()
  end
end)

function cache.new(ref: Instance, parent: Instance?, params: params?)
  local self = setmetatable({}, cache)

  self.ref = ref
  self.parent = parent

  self.amount = 0
  self.restore_amount = 0

  self.params = reconcile(params or {}, {
    size = 100,
    excess_lifetime = 30,
  })

  self.scope = { ref, parent }
  self.unused = table.create(self.params.size)
  self.item_map = {}

  self.part_mode = ref:IsA("BasePart")

  for _ = 1, self.params.size do
    self:_add()
  end

  table.insert(
    self.scope,
    task.spawn(function()
      while task.wait(RECYCLE_INTERVAL) do
        if self.restore_amount > 0 then
          for _ = 1, self.restore_amount do
            self:_add()
            self.restore_amount -= 1
          end
        end

        if self.amount <= self.params.size then
          continue
        end

        local offset = 0

        for i = 1, #self.unused do
          if self.amount <= self.params.size then
            break
          end

          i -= offset

          local item = self.unused[i]

          if item.dependents ~= 0 or (os.clock() - item.added) > self.params.excess_lifetime then
            continue
          end

          item:destroy()

          table.remove(self.unused, i)

          self.item_map[item.key] = nil
          self.amount -= 1

          offset += 1
        end
      end
    end)
  )

  return self
end

function cache._add(self: ObjectCache, key: any?, excess: boolean?)
  local obj = self.ref:Clone()
  obj.Archivable = false
  obj.Parent = self.parent

  local item = {
    key = key,
    value = obj,

    added = os.clock(),
    dependents = 1,
  }

  local ignoreDestroy = false

  function item:destroy()
    ignoreDestroy = true
    obj:Destroy()
  end

  self.amount += 1

  obj.Destroying:Connect(function()
    if ignoreDestroy then
      return
    end

    local index = table.find(self.unused, item)

    if index then
      table.remove(self.unused, index)
    end

    if item.key then
      self.item_map[item.key] = nil
    end

    self.amount -= 1
    self.restore_amount += 1
  end)

  if key then
    self.item_map[key] = item
  end

  if not excess then
    table.insert(self.unused, item)
  end

  return item
end

function cache.has(self: ObjectCache, key: any)
  return if self.item_map[key] then true else false
end

function cache.peek(self: ObjectCache, key: any)
  return self.item_map[key]
end

function cache.get(self: ObjectCache, key: any)
  if self:has(key) then
    local item = self:peek(key)

    if item then
      item.dependents += 1
    end

    return item.value
  end

  local item = table.remove(self.unused)

  if item then
    item.key = key
    item.added = os.clock()

    self.item_map[key] = item
  else
    item = self:_add(key, true)
  end

  if self.part_mode then
    local meta = {}

    function meta:__newindex(key, value)
      if key == "CFrame" then
        table.insert(moveParts, item.value)
        table.insert(movePartCFrames, value)

        if not partUpdateScheduled then
          partUpdateScheduled = true
          task.defer(bulkPartMoveThread)
        end
      else
        item.value[key] = value
      end
    end

    function meta:__index(key)
      local v = item.value[key]

      if typeof(v) == "function" then
        return function(_, ...)
          return v(item.value, ...)
        end
      else
        return v
      end
    end

    return setmetatable({
      _getReal = function()
        return item.value
      end,
    }, meta)
  else
    return item.value
  end
end

function cache.free(self: ObjectCache, key: any)
  local item = self.item_map[key]

  if not item then
    return
  end

  item.dependents = math.max(item.dependents - 1, 0)

  if item.dependents == 0 then
    item.added = os.clock()

    if self.params.on_free then
      task.spawn(self.params.on_free, item)
    end

    table.insert(self.unused, item)
  end
end

function cache.destroy(self: ObjectCache)
  utility.cleanupScope(self.scope)

  for _, item in self.item_map do
    item.value:Destroy()
  end

  table.clear(self.unused)
  table.clear(self.item_map)
end

return cache
