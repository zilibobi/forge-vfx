type n = vector | number

local NEWTON_MIN_TOL = 0.001
local NEWTON_MAX_ITER = 5

local function cubicBezier(p0: n, p1: n, p2: n, p3: n, t: n): n
  -- stylua: ignore
  return (1-t)^3*p0+3*(1-t)^2*t*p1+3*(1-t)*t^2*p2+t^3*p3
end

local function cubicBezierDerivative(p0: n, p1: n, p2: n, p3: n, t: n): n
  -- stylua: ignore
  return 3*(1-t)^2*(p1-p0)+6*(1-t)*t*(p2-p1)+3*t^2*(p3-p2)
end

local bezier = {}
bezier.__index = bezier

type Bezier = typeof(bezier) & {
  points: { vector },
  cumulative_lengths: { number },

  length: number,
  accuracy: number,
  point_count: number,
}

function bezier.new(points: { vector }, samplingAccuracy: number?)
  local self = setmetatable({}, bezier)

  self.points = points
  self.accuracy = samplingAccuracy or 20

  self.point_count = 0
  self.cumulative_lengths = {}

  self:_recalculate()

  return self
end

function bezier.setPoints(self: Bezier, points: { vector })
  self.points = points
  self:_recalculate()
end

function bezier.getSegmentPoints(self: Bezier, index: number)
  if index < 1 or index > self.point_count - 1 then
    if index <= 0 then
      return vector.zero, vector.zero, vector.zero, vector.zero
    end

    error("attempt to get a non-existent segment at index " .. index)
  end

  local offset = (index - 1) * 4 - math.max(index - 2, 0)
  local start = math.max(offset, 1)

  local p0 = self.points[start]
  local p1 = self.points[start + 1]
  local p2 = self.points[start + 2]
  local p3 = self.points[start + 3]

  return p0, p1, p2, p3
end

function bezier.forSample(self: Bezier, size: number, callback: (pos: vector, i: number) -> ())
  local amount = self.length // size

  if amount == 0 then
    return
  end

  for i = 0, amount do
    local t = i / amount
    callback(self:getPositionArcSpace(t), i)
  end
end

function bezier.getPosition(self: Bezier, t: number)
  local i, u = self:getSegmentIndex(t)
  local p0, p1, p2, p3 = self:getSegmentPoints(i)

  return cubicBezier(p0, p1, p2, p3, u)
end

function bezier.getSegmentIndex(self: Bezier, t: number)
  t = math.clamp(t, 0, 1)

  local m = self.point_count - 1
  local s = t * m

  local i = math.min(math.floor(s) + 1, m)
  local u = s - math.floor(s)

  if t == 1 then
    u = 1
  end

  return i, u
end

-- Only works with beziers whose input is the X axis
function bezier.getEasedSegmentIndex(self: Bezier, t: number)
  local i = self.point_count - 1
  local u = 1

  for j = 1, i do
    local p0, _, _, p3 = self:getSegmentPoints(j)

    local start = p0.x
    local stop = p3.x

    if t >= start and t < stop then
      i = j
      u = (t - start) / (stop - start)

      break
    end
  end

  return i, u
end

function bezier.getEase(self: Bezier, t: number)
  local i, s = self:getEasedSegmentIndex(t)
  local p0, p1, p2, p3 = self:getSegmentPoints(i)

  for i = 1, NEWTON_MAX_ITER do
    local x = cubicBezier(p0.x, p1.x, p2.x, p3.x, s)
    local dx = cubicBezierDerivative(p0.x, p1.x, p2.x, p3.x, s)

    if dx == 0 then
      break
    end

    local ds = (x - t) / dx
    s = s - ds

    if s < 0 then
      s = 0
    elseif s > 1 then
      s = 1
    end

    if math.abs(ds) < NEWTON_MIN_TOL then
      break
    end
  end

  return cubicBezier(p0, p1, p2, p3, s)
end

function bezier.getPositionArcSpace(self: Bezier, t: number)
  if self.length <= 0 then
    return self.points[1] or vector.zero
  end

  t = math.clamp(t, 0, 1)

  local targetLength = t * self.cumulative_lengths[self.accuracy + 1]
  local low, high, index = 1, self.accuracy + 1, nil

  while low < high do
    index = low + (high - low) // 2

    if self.cumulative_lengths[index] < targetLength then
      low = index + 1
    else
      high = index
    end
  end

  if self.cumulative_lengths[index] > targetLength and index > 1 then
    index -= 1
  end

  local lengthBefore = self.cumulative_lengths[index]

  if lengthBefore == targetLength then
    return self:getPosition((index - 1) / self.accuracy)
  else
    return self:getPosition(
      ((index - 1) + (targetLength - lengthBefore) / (self.cumulative_lengths[index + 1] - lengthBefore))
        / self.accuracy
    )
  end
end

function bezier._recalculate(self: Bezier)
  table.clear(self.cumulative_lengths)
  table.insert(self.cumulative_lengths, 0)

  local count = math.ceil(#self.points / 3)

  self.point_count = count

  local total = 0

  local prev: vector

  for j = 1, self.accuracy do
    local p = self:getPosition(j / self.accuracy)

    if not prev then
      prev = self:getPosition(0)
    end

    total += vector.magnitude(p - prev)
    prev = p

    table.insert(self.cumulative_lengths, total)
  end

  self.length = total

  for i, len in self.cumulative_lengths do
    self.cumulative_lengths[i] = len / total
  end
end

return bezier
