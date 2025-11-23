--!nolint LocalShadow
local tween = require("@mod/tween")
local types = require("@root/types")
local utility = require("@mod/utility")

local Promise = require("@pkg/Promise")

local rng = Random.new()

local function getLegacyWidths(obj: Beam, scale: number)
  local w0 = utility.getAttribute(obj, "Width0", obj.Width0, true) * scale
  local w1 = utility.getAttribute(obj, "Width1", obj.Width1, true) * scale

  local s_w0 = utility.getAttribute(obj, "StartWidth0", obj.Width0, true) * scale
  local s_w1 = utility.getAttribute(obj, "StartWidth1", obj.Width1, true) * scale

  return w0, w1, s_w0, s_w1
end

local beam = {}

function beam.emit(ref: Beam, obj: Beam, scope: types.scope, scale: number)
  local emitOnFinish = scope.effects.prepareEmitOnFinish(obj, scope)

  local a1, a2, a3, a4 = getLegacyWidths(ref, scale)

  local w1 = utility.getAttribute(ref, "Width0_Start", a3)
  local w2 = utility.getAttribute(ref, "Width0_End", a1)
  local w3 = utility.getAttribute(ref, "Width1_Start", a4)
  local w4 = utility.getAttribute(ref, "Width1_End", a2)

  local c1 = utility.getAttribute(ref, "CurveSize0_Start", obj.CurveSize0)
  local c2 = utility.getAttribute(ref, "CurveSize0_End", obj.CurveSize0)
  local c3 = utility.getAttribute(ref, "CurveSize1_Start", obj.CurveSize1)
  local c4 = utility.getAttribute(ref, "CurveSize1_End", obj.CurveSize1)

  local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

  local legacy_duration = utility.getAttribute(ref, "Duration", 1, true)
  local legacy_tpScale = utility.getAttribute(ref, "EndTransparencyScale", 1, true)

  local durationRange = utility.getRangeAttribute(
    ref,
    "EffectDuration",
    NumberRange.new(legacy_duration, legacy_duration),
    NumberRange.new(0, math.huge)
  )

  local lengthScaleRangeStart = utility.getAttribute(ref, "Length_Scale_Start", NumberRange.new(1, 1))
  local lengthScaleRangeEnd = utility.getAttribute(ref, "Length_Scale_End", NumberRange.new(1, 1))

  local texLengthStart = utility.getAttribute(ref, "Length_Texture_Start", ref.TextureLength)
  local textLengthEnd = utility.getAttribute(ref, "Length_Texture_End", ref.TextureLength)

  local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

  local lengthScaleStart = rng:NextNumber(lengthScaleRangeStart.Min, lengthScaleRangeStart.Max)
  local lengthScaleEnd = rng:NextNumber(lengthScaleRangeEnd.Min, lengthScaleRangeEnd.Max)

  local tStart, tEnd =
    utility.getAttribute(ref, "Transparency_Scale_Start", 1),
    utility.getAttribute(ref, "Transparency_Scale_End", legacy_tpScale)

  local texSpeedStart = utility.getAttribute(ref, "Speed_Texture_Start", ref.TextureSpeed)
  local texSpeedEnd = utility.getAttribute(ref, "Speed_Texture_End", ref.TextureSpeed)

  local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
  local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

  local baseTexSpeed = obj.TextureSpeed

  task.wait(emitDelay)

  obj.Enabled = true

  local promises = {}
  local currentSpeed = 1

  local speedTween

  local env = scope.effects.emitNested(obj, scope.depth + 1)
  table.insert(promises, env.Finished)

  if texSpeedStart ~= texSpeedEnd then
    tween.fromParams(
      utility.getAttribute(ref, "Speed_Texture_Curve", utility.default_bezier),
      duration,
      function(alpha, deltaTime)
        baseTexSpeed = utility.lerp(texSpeedStart, texSpeedEnd, alpha)
        obj.TextureSpeed = baseTexSpeed * currentSpeed

        return deltaTime
      end
    )
  end

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

  local att0, att1 = obj.Attachment0, obj.Attachment1
  local cf0, cf1 = att0 and att0.CFrame, att1 and att1.CFrame

  local function setLengthScale(scale: number)
    if not cf0 or not cf1 then
      return
    end

    -- calculate the original offset vector from att0 to att1
    local offset = cf1.Position - cf0.Position
    local halfOffset = offset * 0.5

    -- calculate center point
    local center = cf0.Position + halfOffset

    -- scale the half-offsets and apply from center
    local scaledHalfOffset = halfOffset * scale

    att0.CFrame = CFrame.new(center - scaledHalfOffset) * (cf0 - cf0.Position)
    att1.CFrame = CFrame.new(center + scaledHalfOffset) * (cf1 - cf1.Position)
  end

  table.insert(scope, function()
    setLengthScale(1)
  end)

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

  if texLengthStart ~= textLengthEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Length_Texture_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.TextureLength = utility.lerp(texLengthStart, textLengthEnd, alpha)
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  end

  if lengthScaleStart ~= lengthScaleEnd then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "Length_Scale_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          local x = utility.lerp(lengthScaleStart, lengthScaleEnd, alpha)

          setLengthScale(x)

          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  elseif texLengthStart ~= 1 then
    setLengthScale(lengthScaleStart)
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

  if c1 ~= c2 then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "CurveSize0_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.CurveSize0 = utility.lerp(c1, c2, alpha)
          return deltaTime * currentSpeed
        end,
        speedTween
      )
    )
  else
    obj.Width0 = w1
  end

  if c3 ~= c4 then
    table.insert(
      scope,
      tween.fromParams(
        utility.getAttribute(ref, "CurveSize1_Curve", utility.default_bezier),
        duration,
        function(alpha, deltaTime)
          obj.CurveSize1 = utility.lerp(c3, c4, alpha)
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

  if emitOnFinish then
    local env = scope.effects.emitOnFinish(emitOnFinish, obj.Parent or workspace.Terrain, scope.depth + 1)
    table.insert(promises, env.Finished)
  end

  Promise.all(promises):await()
end

return beam
