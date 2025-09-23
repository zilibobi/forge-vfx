local tween = require("../mod/tween")
local utility = require("../mod/utility")

local rng = Random.new()

local function getLegacyWidths(obj: Beam, scale: number)
  local w0 = utility.getAttribute(obj, "Width0", obj.Width0, true) * scale
  local w1 = utility.getAttribute(obj, "Width1", obj.Width1, true) * scale

  local s_w0 = utility.getAttribute(obj, "StartWidth0", obj.Width0, true) * scale
  local s_w1 = utility.getAttribute(obj, "StartWidth1", obj.Width1, true) * scale

  return w0, w1, s_w0, s_w1
end

local beam = {}

function beam.emit(ref: Beam, obj: Beam, scope: utility.scope, scale: number)
  local a1, a2, a3, a4 = getLegacyWidths(ref, scale)

  local w1 = utility.getAttribute(ref, "Width0_Start", a3)
  local w2 = utility.getAttribute(ref, "Width0_End", a1)
  local w3 = utility.getAttribute(ref, "Width1_Start", a4)
  local w4 = utility.getAttribute(ref, "Width1_End", a2)

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

  local legacy_duration = utility.getAttribute(ref, "Duration", 1, true)
  local legacy_tpScale = utility.getAttribute(ref, "EndTransparencyScale", 1, true)

  local durationRange = utility.getRangeAttribute(
    ref,
    "EffectDuration",
    NumberRange.new(legacy_duration, legacy_duration),
    NumberRange.new(0, math.huge)
  )

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local tStart, tEnd =
    utility.getAttribute(ref, "Transparency_Scale_Start", 1),
    utility.getAttribute(ref, "Transparency_Scale_End", legacy_tpScale)

  local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

  local baseTexSpeed = obj.TextureSpeed

  task.wait(emitDelay)

  obj.Enabled = true

  local currentSpeed = 1

  local speedTween

  if speedStart ~= speedEnd then
    speedTween = tween.fromParams(
      utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
      utility.getAttribute(obj, "Speed_Duration", 0.1),
      function(alpha, deltaTime)
        currentSpeed = utility.lerp(speedStart, speedEnd, alpha)

        obj.TextureSpeed = baseTexSpeed * currentSpeed

        return deltaTime
      end
    )

    table.insert(scope, speedTween)
  end

  local function setTScale(tscale: number)
    obj.Transparency = utility.scaleNumberSequence(ref.Transparency, function(value, envelope)
      local base = tscale > 1 and (1 - value) or -value
      local offset = tscale > 1 and tscale - 1 or 1 - tscale

      return value + base * offset, envelope
    end)
  end

  if tStart ~= tEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Transparency_Scale_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          setTScale(utility.lerp(tStart, tEnd, alpha))
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  elseif tStart ~= 1 then
    setTScale(tStart)
  end

  if w1 ~= w2 then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Width0_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.Width0 = utility.lerp(w1, w2, alpha)
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  else
    obj.Width0 = w1
  end

  if w3 ~= w4 then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Width1_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.Width1 = utility.lerp(w3, w4, alpha)
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  else
    obj.Width1 = w3
  end

  tween.timer(duration, function(deltaTime, elapsed)
    return if currentSpeed > 0 or (elapsed > 0 and speedTween and speedTween.Connected)
      then deltaTime * currentSpeed
      else nil
  end, speedTween, scope)
end

return beam
