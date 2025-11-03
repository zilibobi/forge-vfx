--!native
--!optimize 2
local utility = require("./utility")

local shape = {}

function shape.getSurfaceCFrame(cf: CFrame, n: Vector3, pos: Vector3)
  local up = math.abs(n:Dot(Vector3.yAxis)) > 0.99 and Vector3.zAxis or Vector3.yAxis
  local rot = CFrame.lookAt(Vector3.zero, n, up)
  return cf * CFrame.new(pos) * rot
end

function shape.getPointWithinBox(seed: number, cframe: CFrame, size: Vector3, normal: Enum.NormalId)
  debug.profilebegin("getPointWithinBox")

  local rng = Random.new(seed)

  local half = size / 2

  -- stylua: ignore
  local pos = Vector3.new(
    rng:NextNumber(-1, 1),
    rng:NextNumber(-1, 1),
    rng:NextNumber(-1, 1)
  ) * half

  local cf = shape.getSurfaceCFrame(cframe, Vector3.FromNormalId(normal), pos)

  debug.profileend()

  return cf
end

function shape.getPointOnBox(seed: number, cframe: CFrame, size: Vector3, normal: Enum.NormalId)
  debug.profilebegin("getPointOnBox")

  local rng = Random.new(seed)

  local n = Vector3.FromNormalId(normal)

  local half = size / 2
  local axes = Vector3.one - n:Abs()

  -- stylua: ignore
  local s = Vector3.new(
    rng:NextNumber(-1, 1),
    rng:NextNumber(-1, 1),
    rng:NextNumber(-1, 1)
  ) * half * axes

  local cf = shape.getSurfaceCFrame(cframe, n, s + n * half)

  debug.profileend()

  return cf
end

function shape.getPointWithinCylinder(
  seed: number,
  min_radius: number,
  partial: number,
  cframe: CFrame,
  size: Vector3,
  normal: Enum.NormalId
)
  debug.profilebegin("getPointWithinCylinder")

  local rng = Random.new(seed)

  local r = math.sqrt(rng:NextNumber(min_radius, 1))
  local theta = rng:NextNumber(0, 2 * math.pi)

  if normal == Enum.NormalId.Left or normal == Enum.NormalId.Right then
    cframe *= CFrame.fromOrientation(0, math.pi / 2 * (normal == Enum.NormalId.Right and -1 or 1), 0)
    size = Vector3.new(size.Z, size.Y, size.X)
  elseif normal == Enum.NormalId.Front or normal == Enum.NormalId.Back then
    cframe *= CFrame.fromOrientation(0, math.pi, 0)
  end

  local z = rng:NextNumber()
  local t = 1 - z ^ utility.lerp(0.5, 1, math.sqrt(partial))

  local width = utility.lerp(1, partial, t)

  -- stylua: ignore
  local pos = Vector3.new(
    t * 2 - 1,
    r * math.sin(theta) * width,
    r * math.cos(theta) * width
  ) * size / 2

  -- stylua: ignore
  local pos2 = Vector3.new(
    0,
    math.sin(theta) * width,
    math.cos(theta) * width
  ) * size / 2

  local tangent = Vector3.new(0, math.cos(theta) * width, -math.sin(theta) * width) * size / 2
  local up = tangent.Magnitude > 0.001 and tangent.Unit or cframe.UpVector
  local res = cframe * CFrame.new(pos) * CFrame.lookAt(Vector3.zero, pos2, up)

  debug.profileend()

  return res
end

function shape.getPointWithinSphere(
  seed: number,
  min_radius: number,
  partial: number,
  cframe: CFrame,
  size: Vector3,
  normal: Enum.NormalId
)
  debug.profilebegin("getPointWithinSphere")

  local rng = Random.new(seed)

  local u = rng:NextNumber()
  local v = rng:NextNumber()

  local theta = u * 2 * math.pi
  local phi = math.acos(2 * v - 1) * partial
  local r = rng:NextNumber(min_radius, 1) ^ (1 / 3)

  local sinTheta = math.sin(theta)
  local cosTheta = math.cos(theta)
  local sinPhi = math.sin(phi)
  local cosPhi = math.cos(phi)

  local n = Vector3.FromNormalId(normal)

  if normal == Enum.NormalId.Left or normal == Enum.NormalId.Right then
    size = Vector3.new(size.Z, size.Y, size.X)
  elseif normal == Enum.NormalId.Top or normal == Enum.NormalId.Bottom then
    size = Vector3.new(size.X, size.Z, size.Y)
  end

  local half = size / 2
  local cf = shape.getSurfaceCFrame(cframe, n, Vector3.zero)

  -- stylua: ignore
  local pos = Vector3.new(
    r * sinPhi * cosTheta,
    r * sinPhi * sinTheta,
    r * cosPhi
  ) * half

  local tangent = Vector3.new(-sinPhi * sinTheta, sinPhi * cosTheta, 0) * half

  local up = if tangent.Magnitude > 0.001 then tangent.Unit else Vector3.new(1, 0, 0)
  local res = cf * CFrame.Angles(0, math.pi, 0) * CFrame.new(pos) * CFrame.lookAt(Vector3.zero, pos, up)

  debug.profileend()

  return res
end

function shape.getPointWithinDisc(
  seed: number,
  min_depth: number,
  partial: number,
  cframe: CFrame,
  size: Vector3,
  normal: Enum.NormalId
)
  debug.profilebegin("getPointWithinDisc")

  local rng = Random.new(seed)

  local n = Vector3.FromNormalId(normal)
  local axes = Vector3.one - n:Abs() * min_depth

  local half = size / 2

  local z = rng:NextNumber(min_depth, 1)
  local d = utility.lerp(1, 0.5, partial ^ 4)

  local t = z

  local r = rng:NextNumber(1 - partial, 1) ^ d
  local theta = rng:NextNumber(0, 2 * math.pi)

  -- stylua: ignore
  local s = Vector3.new(
    t * 2 - 1,
    r * math.sin(theta),
    r * math.cos(theta)
  )

  if normal == Enum.NormalId.Bottom or normal == Enum.NormalId.Top then
    s = Vector3.new(s.Z, s.X, s.Y)
  elseif normal == Enum.NormalId.Front or normal == Enum.NormalId.Back then
    s = Vector3.new(s.Y, s.Z, s.X)
  end

  s *= half * axes

  local cf = shape.getSurfaceCFrame(cframe, n, s + n * min_depth * half)

  debug.profileend()

  return cf
end

return shape
