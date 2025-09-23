local Oklab = require("./color/Oklab")

local MAX_KEYPOINTS = 20

local lerp = {}

function lerp.number(a: number, b: number, t: number)
  return a + (b - a) * t
end

function lerp.Vector3(a: Vector3, b: Vector3, t: number)
  return a:Lerp(b, t)
end

function lerp.Vector2(a: Vector2, b: Vector2, t: number)
  return a:Lerp(b, t)
end

function lerp.CFrame(a: CFrame, b: CFrame, t: number)
  return a:Lerp(b, t)
end

function lerp.UDim2(a: UDim2, b: UDim2, t: number)
  return a:Lerp(b, t)
end

function lerp.UDim(a: UDim, b: UDim, t: number)
  -- stylua: ignore
  return UDim.new(
    lerp.number(a.Scale, b.Scale, t),
    lerp.number(a.Offset, b.Offset, t)
  )
end

function lerp.NumberRange(a: NumberRange, b: NumberRange, t: number)
  -- stylua: ignore
  return NumberRange.new(
    lerp.number(a.Min, b.Min, t),
    lerp.number(a.Max, b.Max, t)
  )
end

function lerp.Color3(a: Color3, b: Color3, t: number)
  -- stylua: ignore
  return Oklab.toSRGB(
    Oklab.fromSRGB(a):Lerp(Oklab.fromSRGB(b), t)
  )
end

function lerp.PhysicalProperties(a: PhysicalProperties, b: PhysicalProperties, t: number)
  return PhysicalProperties.new(
    lerp.number(a.Density, b.Density, t),
    lerp.number(a.Friction, b.Friction, t),
    lerp.number(a.Elasticity, b.Elasticity, t),
    lerp.number(a.FrictionWeight, b.FrictionWeight, t),
    lerp.number(a.ElasticityWeight, b.ElasticityWeight, t)
  )
end

function lerp.Rect(a: Rect, b: Rect, t: number)
  return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
end

-- credit https://github.com/boatbomber/BoatTween
function lerp.NumberSequence(a: NumberSequence, b: NumberSequence, t: number)
  local keypoints = {}
  local addedTimes = {}

  local keylength = 0

  for _, ap in a.Keypoints do
    local closestAbove, closestBelow

    for _, bp in b.Keypoints do
      if bp.Time == ap.Time then
        closestAbove, closestBelow = bp, bp
        break
      elseif bp.Time < ap.Time and (closestBelow == nil or bp.Time > closestBelow.Time) then
        closestBelow = bp
      elseif bp.Time > ap.Time and (closestAbove == nil or bp.Time < closestAbove.Time) then
        closestAbove = bp
      end
    end

    local bValue, bEnvelope

    if closestAbove == closestBelow then
      bValue, bEnvelope = closestAbove.Value, closestAbove.Envelope
    else
      local p = (ap.Time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)
      bValue = (closestAbove.Value - closestBelow.Value) * p + closestBelow.Value
      bEnvelope = (closestAbove.Envelope - closestBelow.Envelope) * p + closestBelow.Envelope
    end

    keylength += 1
    keypoints[keylength] = NumberSequenceKeypoint.new(
      ap.Time,
      (bValue - ap.Value) * t + ap.Value,
      (bEnvelope - ap.Envelope) * t + ap.Envelope
    )

    addedTimes[ap.Time] = true
  end

  for _, bp in b.Keypoints do
    if not addedTimes[bp.Time] then
      local closestAbove, closestBelow

      for _, ap in a.Keypoints do
        if ap.Time == bp.Time then
          closestAbove, closestBelow = ap, ap
          break
        elseif ap.Time < bp.Time and (closestBelow == nil or ap.Time > closestBelow.Time) then
          closestBelow = ap
        elseif ap.Time > bp.Time and (closestAbove == nil or ap.Time < closestAbove.Time) then
          closestAbove = ap
        end
      end

      local aValue, aEnvelope

      if closestAbove == closestBelow then
        aValue, aEnvelope = closestAbove.Value, closestAbove.Envelope
      else
        local p = (bp.Time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)
        aValue = (closestAbove.Value - closestBelow.Value) * p + closestBelow.Value
        aEnvelope = (closestAbove.Envelope - closestBelow.Envelope) * p + closestBelow.Envelope
      end

      keylength += 1
      keypoints[keylength] =
        NumberSequenceKeypoint.new(bp.Time, (bp.Value - aValue) * t + aValue, (bp.Envelope - aEnvelope) * t + aEnvelope)
    end
  end

  table.sort(keypoints, function(a, b)
    return a.Time < b.Time
  end)

  local finalKeypoints

  if #keypoints > MAX_KEYPOINTS then
    finalKeypoints = {}
    local step = (#keypoints - 1) / (MAX_KEYPOINTS - 1)

    for i = 0, MAX_KEYPOINTS - 1 do
      local index = math.floor(i * step + 1)
      table.insert(finalKeypoints, keypoints[index])
    end

    if finalKeypoints[#finalKeypoints].Time < keypoints[#keypoints].Time then
      finalKeypoints[#finalKeypoints] = keypoints[#keypoints]
    end
  else
    finalKeypoints = keypoints
  end

  return NumberSequence.new(finalKeypoints)
end

local function getColorAtTime(sequence: ColorSequence, time: number)
  local keypoints = sequence.Keypoints

  if time <= keypoints[1].Time then
    return keypoints[1].Value
  end

  if time >= keypoints[#keypoints].Time then
    return keypoints[#keypoints].Value
  end

  local closestBelow
  local closestAbove

  for i = 1, #keypoints do
    local kp = keypoints[i]
    if kp.Time == time then
      return kp.Value
    elseif kp.Time < time then
      closestBelow = kp
    elseif kp.Time > time then
      closestAbove = kp
      break
    end
  end

  local alpha = (time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)

  return closestBelow.Value:Lerp(closestAbove.Value, alpha)
end

function lerp.ColorSequence(a: ColorSequence, b: ColorSequence, t: number)
  local newKeypoints = {}

  for _, bp in ipairs(b.Keypoints) do
    local aValueAtBTime = getColorAtTime(a, bp.Time)

    -- use linear space because color sequences are in linear space anyway
    -- and from my observations, using Oklab results in darker transitions
    -- that do look more natural, but don't create a satisfying result
    local finalColor = aValueAtBTime:Lerp(bp.Value, t)

    table.insert(newKeypoints, ColorSequenceKeypoint.new(bp.Time, finalColor))
  end

  return ColorSequence.new(newKeypoints)
end

function lerp.Other(a: any, b: any, t: number)
  return t < 0.5 and a or b
end

return lerp
