local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local common = {}

function common.serialize(ids: { number })
  local buf = buffer.create(#ids * 8)

  for i, id in ids do
    buffer.writef64(buf, (i - 1) * 8, id)
  end

  return buf
end

function common.deserialize(data: string | buffer)
  local buf = typeof(data) == "string" and buffer.fromstring(data) or data
  local count = buffer.len(buf) / 8

  local ids = {}

  for i = 0, count - 1 do
    table.insert(ids, buffer.readf64(buf, i * 8))
  end

  return ids
end

function common.isLocalFlipbook(ref: Instance)
  if not RunService:IsStudio() then
    return false
  end

  for _, tag in CollectionService:GetTags(ref) do
    if tag:match("^_local_flipbook_") then
      return true
    end
  end

  return false
end

function common.getTexturePrefix(ref: Instance)
  return common.isLocalFlipbook(ref) and "rbxtemp://" or "rbxassetid://"
end

function common.getFlipbookData(ref: Instance): { number }?
  if not ref:GetAttribute("Flipbook_Enabled") then
    return nil
  end

  local data = ref:GetAttribute("Flipbook_Textures")

  if not data then
    return nil
  end

  local frames = common.deserialize(data)

  if #frames == 0 then
    return nil
  end

  return frames
end

export type FlipbookConfig = {
  ref: Instance,
  curve: string,
  speedTween: any?,

  duration: number,
  effectDuration: number,

  frames: { number },

  getSpeed: () -> number,
  setTexture: (texture: string) -> (),
}

function common.getChangeDuration(config: FlipbookConfig)
  local changeDuration = config.duration

  if config.ref:GetAttribute("SyncDuration") then
    changeDuration = config.effectDuration
  end

  return changeDuration
end

function common.createUpdateCallback(config: FlipbookConfig)
  local prefix = common.getTexturePrefix(config.ref)

  return function(alpha, deltaTime)
    local index = math.max(math.round(#config.frames * alpha), 1)
    config.setTexture(`{prefix}{config.frames[index]}`)

    return deltaTime * config.getSpeed()
  end
end

return common
