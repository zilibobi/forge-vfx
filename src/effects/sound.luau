local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local attr = require("@mod/attributes")

local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")
local Promise = require("@pkg/Promise")

local rng = Random.new()

local sound = {}

local soundWidget: DockWidgetPluginGui?

local function selectRandomSound(ref: Sound): Sound?
  local poolTag = attr.get(ref, "SoundPoolTag", "")

  if poolTag == "" then
    return ref
  end

  local sounds = CollectionService:GetTagged(poolTag)

  local weights: { number } = {}
  local validSounds: { Sound } = {}

  local totalWeight = 0

  for _, obj in sounds do
    if not obj:IsA("Sound") then
      continue
    end

    table.insert(validSounds, obj)

    local weight = attr.get(obj, "SoundPoolWeight", 1)

    table.insert(weights, weight)
    totalWeight += weight
  end

  if #validSounds == 0 then
    return ref
  end

  if totalWeight > 0 then
    local roll = rng:NextNumber() * totalWeight
    local accumulated = 0

    for i, weight in weights do
      accumulated += weight

      if roll <= accumulated then
        return validSounds[i]
      end
    end
  end

  return validSounds[rng:NextInteger(1, #validSounds)]
end

local function createSoundClone(ref: Sound, sourceSound: Sound, scope: types.scope): (Sound, Part?)
  local clone = sourceSound:Clone()

  for _, tag in clone:GetTags() do
    clone:RemoveTag(tag)
  end

  local parent = ref:FindFirstAncestorWhichIsA("BasePart")

  local partClone

  if utility.PLUGIN_CONTEXT then
    if parent then
      partClone = Instance.new("Part")

      partClone.Name = "SoundEmitter"
      partClone.Anchored = true
      partClone.CanCollide = false
      partClone.CanQuery = false
      partClone.CanTouch = false
      partClone.Transparency = 1
      partClone.Size = Vector3.one
      partClone.CFrame = parent.CFrame
      partClone.Parent = soundWidget

      clone.Parent = partClone

      table.insert(scope, partClone)
    else
      clone.Parent = soundWidget
      table.insert(scope, clone)
    end
  else
    if parent then
      clone.Parent = parent
    else
      clone.Parent = workspace.Terrain
    end

    table.insert(scope, clone)
  end

  return clone, partClone
end

local function playSingleSound(
  ref: Sound,
  src: Sound,
  clone: Sound,
  partClone: Part?,
  scope: types.scope,
  emitDuration: number
): RBXScriptConnection?
  local currentSpeed = clone.PlaybackSpeed

  local volumeEnd = attr.get(src, "Volume_End", clone.Volume)
  local volumeStart = attr.get(src, "Volume_Start", clone.Volume)

  clone.Volume = volumeStart

  if volumeStart ~= volumeEnd then
    local volumeDuration = attr.get(src, "Volume_Duration", clone.TimeLength)

    table.insert(
      scope,
      tween.fromParams(attr.get(src, "Volume_Curve", utility.default_bezier), volumeDuration, function(alpha, deltaTime)
        clone.Volume = utility.lerp(volumeStart, volumeEnd, alpha)
        return deltaTime * currentSpeed
      end)
    )
  else
    clone.Volume = volumeStart
  end

  local speedEnd = attr.get(src, "Speed_End", clone.PlaybackSpeed)
  local speedStart = attr.get(src, "Speed_Start", clone.PlaybackSpeed)

  currentSpeed = speedStart

  local speedTween: RBXScriptConnection? = nil

  if speedStart ~= speedEnd then
    local speedDuration = attr.get(src, "Speed_Duration", clone.TimeLength)

    speedTween = tween.fromParams(
      attr.get(src, "Speed_Curve", utility.default_bezier),
      speedDuration,
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
        clone.PlaybackSpeed = currentSpeed
        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  else
    clone.PlaybackSpeed = speedStart
  end

  local rolloffEnd = attr.get(src, "RollOff_End", clone.RollOffMinDistance)
  local rolloffStart = attr.get(src, "RollOff_Start", clone.RollOffMinDistance)

  if rolloffStart ~= rolloffEnd then
    local rolloffDuration = attr.get(src, "RollOff_Duration", clone.TimeLength)

    table.insert(
      scope,
      tween.fromParams(
        attr.get(src, "RollOff_Curve", utility.default_bezier),
        rolloffDuration,
        function(alpha, deltaTime)
          clone.RollOffMinDistance = utility.lerp(rolloffStart, rolloffEnd, alpha)
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  end

  if clone.PlayOnRemove and not utility.PLUGIN_CONTEXT then
    clone:Destroy()
  else
    clone:Play()
  end

  if partClone then
    local parent = ref:FindFirstAncestorWhichIsA("BasePart")

    if parent then
      table.insert(
        scope,
        RunService.Heartbeat:Connect(function()
          if partClone.Parent then
            partClone.CFrame = parent.CFrame
          end
        end)
      )
    end
  end

  if emitDuration > 0 then
    utility.pausableWait(emitDuration)
    clone:Stop()
  else
    tween.timer(clone.TimeLength, function(deltaTime, elapsed)
      return if clone.PlaybackSpeed > 0 or (elapsed > 0 and speedTween and speedTween.Connected)
        then deltaTime * clone.PlaybackSpeed
        else nil
    end, speedTween, scope)
  end

  return speedTween
end

function sound.init()
  if not utility.PLUGIN_CONTEXT then
    return
  end

  local plugin = script:FindFirstAncestorOfClass("Plugin")

  if not plugin then
    return
  end

  soundWidget = plugin:CreateDockWidgetPluginGui(
    "VFXForgeSoundPlayer",
    DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 200, 100, 100, 50)
  )

  if soundWidget then
    soundWidget.Name = "VFXForgeSoundPlayer"
  end
end

function sound.deinit()
  if soundWidget then
    soundWidget:Destroy()
    soundWidget = nil
  end
end

function sound.emit(ref: Sound, scope: types.scope)
  if ref.Playing then
    ref:Stop()
  end

  local isSource = attr.get(ref, "SoundPoolIsSource", false)
  local inheritPoolAttributes = attr.get(ref, "SoundPoolInheritAttributes", false)

  if inheritPoolAttributes then
    ref = not isSource and selectRandomSound(ref) or ref
  end

  local emitDelay = attr.get(ref, "EmitDelay", 0)
  local emitDuration = attr.get(ref, "EmitDuration", 0)

  local emitCount = attr.get(ref, "EmitCount", 1)
  local emitInterval = attr.getRange(ref, "EmitInterval", NumberRange.new(0, 0))

  local repeatCount = attr.get(ref, "RepeatCount", 1)
  local repeatInterval = attr.getRange(ref, "RepeatInterval", NumberRange.new(0, 0))

  utility.pausableWait(emitDelay)

  local promises = {}
  local context = scope._context

  for i = 1, emitCount do
    local sourceSound = inheritPoolAttributes and ref or (not isSource and selectRandomSound(ref) or ref)

    if not sourceSound then
      continue
    end

    local src = if inheritPoolAttributes and sourceSound ~= ref then sourceSound else ref

    for r = 1, repeatCount do
      table.insert(
        promises,
        Promise.new(function(resolve)
          utility.bindContext(context)

          local clone, partClone = createSoundClone(ref, sourceSound, scope)
          utility.registerPausable(scope, "sound", clone)

          playSingleSound(ref, src, clone, partClone, scope, emitDuration)

          if partClone then
            partClone:Destroy()
          else
            clone:Destroy()
          end

          resolve()
        end)
      )

      if r < repeatCount and repeatInterval.Max > 0 then
        utility.pausableWait(rng:NextNumber(repeatInterval.Min, repeatInterval.Max))
      end
    end

    if i < emitCount and emitInterval.Max > 0 then
      utility.pausableWait(rng:NextNumber(emitInterval.Min, emitInterval.Max))
    end
  end

  Promise.all(promises):await()
end

return sound
