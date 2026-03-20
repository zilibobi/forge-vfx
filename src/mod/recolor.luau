local colorProps = {
  Single = {
    Color3 = {
      "Decal",
      "Texture",
    },

    Color = {
      "Part",
      "Union",
      "MeshPart",

      "SpotLight",
      "PointLight",
      "SurfaceLight",

      "SurfaceAppearance",
    },
  },

  Sequence = {
    Color = {
      "Beam",
      "Trail",
      "ParticleEmitter",
    },
  },
}

local function warp(x: number)
  return ((x % 1) + 1) % 1
end

local function multiplyHue(h0: number, h1: number)
  local rotation = (h1 - 0.5) * 1
  return warp(h0 + rotation)
end

local function multiplyChannel(c0: number, c1: number)
  local t = 2 * c1 - 1

  if t >= 0 then
    return math.clamp(c0 + (1 - c0) * t, 0, 1)
  else
    return math.clamp(c0 - c0 * math.abs(t), 0, 1)
  end
end

local function normalizeColor(color: Color3)
  local r, g, b = color.R, color.G, color.B
  local f = math.max(1, r, g, b)
  return f, Color3.new(r / f, g / f, b / f)
end

local function multiplyRGB(color: Color3, factor: number)
  return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function recolorObj(obj: Instance, color: Color3, mode: string, isDirect: boolean)
  if not isDirect and obj:IsA("BasePart") then
    return
  end

  local hue, sat, val = color:ToHSV()

  for _, info in colorProps do
    for k, v in info do
      if not table.find(v, obj.ClassName) then
        continue
      end

      local c = obj[k]

      if mode == "multiply" then
        if typeof(c) == "Color3" then
          local f, col = normalizeColor(c)
          local h0, s0, v0 = col:ToHSV()

          local h2 = multiplyHue(h0, hue)
          local s2 = multiplyChannel(s0, sat)
          local v2 = multiplyChannel(v0, val)

          obj[k] = multiplyRGB(Color3.fromHSV(h2, s2, v2), f)
        elseif typeof(c) == "ColorSequence" then
          local res = {}

          for _, kp in c.Keypoints do
            local f, col = normalizeColor(kp.Value)
            local h0, s0, v0 = col:ToHSV()

            local h2 = multiplyHue(h0, hue)
            local s2 = multiplyChannel(s0, sat)
            local v2 = multiplyChannel(v0, val)

            table.insert(res, ColorSequenceKeypoint.new(kp.Time, multiplyRGB(Color3.fromHSV(h2, s2, v2), f)))
          end

          obj[k] = ColorSequence.new(res)
        end
      else
        if typeof(c) == "Color3" then
          local f = normalizeColor(c)
          obj[k] = Color3.new(color.R * f, color.G * f, color.B * f)
        elseif typeof(c) == "ColorSequence" then
          obj[k] = ColorSequence.new(color)
        end
      end
    end
  end
end

local function recolor(color: Color3, mode: "replace" | "multiply", ...: Instance)
  for _, instance in { ... } do
    recolorObj(instance, color, mode, true)

    for _, desc in instance:GetDescendants() do
      recolorObj(desc, color, mode, false)
    end
  end
end

return recolor
