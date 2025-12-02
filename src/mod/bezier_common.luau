--!nolint LocalShadow
local CollectionService = game:GetService("CollectionService")

local shape = require("@mod/shape")
local tween = require("@mod/tween")
local utility = require("@mod/utility")

local Oklab = require("@mod/color/Oklab")
local Bezier = require("@obj/Bezier")

local bezierCommon = {}

bezierCommon.drawFuncMap = {
  Box = {
    Volume = shape.getPointWithinBox,
    Surface = shape.getPointOnBox,
  },

  Cylinder = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinCylinder(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinCylinder(seed, 1, partial, cframe, size, normal)
    end,
  },

  Sphere = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinSphere(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinSphere(seed, 1, partial, cframe, size, normal)
    end,
  },

  Disc = {
    Volume = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinDisc(seed, 0, partial, cframe, size, normal)
    end,

    Surface = function(seed, cframe, size, normal, partial)
      return shape.getPointWithinDisc(seed, 1, partial, cframe, size, normal)
    end,
  },
}

function bezierCommon.getColorAtTime(sequence: ColorSequence, time: number)
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

  if not closestBelow or not closestAbove then
    return keypoints[1].Value
  end

  local alpha = (time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)
  return closestBelow.Value:Lerp(closestAbove.Value, alpha)
end

function bezierCommon.getColorAtTimeOklab(sequence: ColorSequence, time: number)
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

  if not closestBelow or not closestAbove then
    return keypoints[1].Value
  end

  local alpha = (time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)

  local labA = Oklab.fromSRGB(closestBelow.Value)
  local labB = Oklab.fromSRGB(closestAbove.Value)

  local blendedLab = labA:Lerp(labB, alpha)

  return Oklab.toSRGB(blendedLab)
end

function bezierCommon.getColorWithEasingOklab(sequence: ColorSequence, time: number, easingBezier)
  local easedTime = 1 - easingBezier:getEase(math.clamp(time, 0, 1)).y
  return bezierCommon.getColorAtTimeOklab(sequence, math.clamp(easedTime, 0, 1))
end

export type HitboxConfig = {
  enabled: boolean,
  collisionGroup: string,
  filterTag: string,
  filterType: string,
  ignoreCanCollide: boolean,
}

function bezierCommon.createHitboxParams(config: HitboxConfig, parent: Instance, root: Attachment?): OverlapParams
  local params = OverlapParams.new()
  params.MaxParts = 1
  params.FilterType = Enum.RaycastFilterType[config.filterType]
  params.CollisionGroup = config.collisionGroup
  params.RespectCanCollide = not config.ignoreCanCollide

  params:AddToFilter(CollectionService:GetTagged(config.filterTag))

  if config.filterType == "Exclude" then
    local ancestorPart = root and root:FindFirstAncestorOfClass("Part")
    params:AddToFilter({ workspace.Terrain, parent, ancestorPart })
  end

  return params
end

export type EmissionConfig = {
  face: "InAndOut" | "Inward" | "Outward",
  spreadAngle: Vector3,
  mirror: boolean,
  mirrorRot: Vector3,
  partial: number,
  emissionDirection: Enum.NormalId,
}

function bezierCommon.calculateEmissionCFrame(
  originCFrame: CFrame,
  originSize: Vector3,
  config: EmissionConfig,
  drawFunc: ((...any) -> CFrame)?,
  rng: Random,
  endPoint: Attachment?,
  isAttachment: boolean
)
  local cf: CFrame

  if isAttachment then
    cf = originCFrame * CFrame.new(Vector3.zero, Vector3.FromNormalId(config.emissionDirection)).Rotation
  elseif drawFunc then
    cf = drawFunc(nil, originCFrame, originSize, config.emissionDirection, config.partial)
  else
    cf = originCFrame
  end

  local normal = Vector3.FromNormalId(config.emissionDirection)
  local pitchAxis = normal:Cross(originCFrame.LookVector)

  if pitchAxis.Magnitude < 0.001 then
    pitchAxis = normal:Cross(originCFrame.UpVector)
  end

  local spread = CFrame.fromAxisAngle(normal, math.rad(rng:NextNumber(-config.spreadAngle.X, config.spreadAngle.X)))
    * CFrame.fromAxisAngle(pitchAxis, math.rad(rng:NextNumber(-config.spreadAngle.Y, config.spreadAngle.Y)))

  cf *= spread

  if config.face == "Inward" or (config.face == "InAndOut" and rng:NextInteger(0, 1) == 1) then
    cf *= CFrame.fromOrientation(0, math.pi, 0)
  end

  if endPoint and config.mirror and (cf.Position - endPoint.WorldPosition).Unit:Dot(cf.RightVector) >= 0 then
    local rot = config.mirrorRot * utility.DEG_TO_RAD
    cf *= CFrame.fromOrientation(rot.X, rot.Y, rot.Z)
  end

  return cf
end

function bezierCommon.createBezierWithEndpoint(
  points: { vector },
  cf: CFrame,
  endPoint: Attachment?,
  endT1: Attachment?
)
  if not endPoint then
    return Bezier.new(points)
  end

  local pts = {}

  for j, pt in points do
    table.insert(
      pts,
      if j == (#points - 1)
        then endT1 and endT1.WorldPosition or endPoint.WorldPosition
        else if j == #points then endPoint.WorldPosition else cf * (pt - points[1])
    )
  end

  return Bezier.new(pts)
end

function bezierCommon.createPosGetter(
  bezier,
  points: { vector },
  cf: CFrame,
  endPoint: Attachment?,
  useArcSpace: boolean?
): (number) -> Vector3
  return function(alpha: number): Vector3
    local p = if useArcSpace ~= false then bezier:getPositionArcSpace(alpha) else bezier:getPosition(alpha)

    if endPoint then
      return p
    else
      return cf * (p - points[1])
    end
  end
end

function bezierCommon.readCommonAttributes(ref: Attachment)
  return {
    -- timing
    emitDelay = utility.getAttribute(ref, "EmitDelay", 0),
    emitCount = utility.getAttribute(ref, "EmitCount", 1),
    emitDuration = utility.getAttribute(ref, "EmitDuration", 0),
    destroyDelay = utility.getAttribute(ref, "DestroyDelay", 0),
    duration = utility.getRangeAttribute(ref, "Duration", NumberRange.new(1, 1), NumberRange.new(0, math.huge)),

    -- shape/emission
    shapeType = utility.getEnumAttribute(ref, "Shape", "Box", { "Box", "Cylinder", "Sphere", "Disc" }),
    shapeStyle = utility.getEnumAttribute(ref, "ShapeStyle", "Volume", { "Volume", "Surface" }),
    emissionDirection = Enum.NormalId[utility.getEnumAttribute(
      ref,
      "EmissionDirection",
      "Top",
      { "Top", "Bottom", "Left", "Right", "Front", "Back" }
    )],
    face = utility.getEnumAttribute(ref, "ShapeFace", "Outward", { "InAndOut", "Inward", "Outward" }),
    spreadAngle = utility.getAttribute(ref, "SpreadAngle", vector.zero),
    partial = utility.getAttribute(ref, "ShapePartial", 1),

    -- path
    syncPosition = utility.getAttribute(ref, "SyncPosition", false),
    mirror = utility.getAttribute(ref, "MirrorPaths", true),
    mirrorRot = utility.getAttribute(ref, "MirrorRotation", vector.create(0, 0, 180)),

    -- projectile
    projectileEnabled = utility.getAttribute(ref, "ProjectileEnabled", false),
    projectileMatchEnd = utility.getAttribute(ref, "MatchEndDirection", false),
    projectileSpeed = utility.getAttribute(ref, "ProjectileSpeed", 30),
    projectileLifetime = utility.getRangeAttribute(
      ref,
      "ProjectileLifetime",
      NumberRange.new(1, 1),
      NumberRange.new(0, math.huge)
    ),

    -- hitbox
    hitboxEnabled = utility.getAttribute(ref, "HitboxEnabled", false),
    hitboxCollisionGroup = utility.getAttribute(ref, "HitboxCollisionGroup", "Default"),
    hitboxFilterTag = utility.getAttribute(ref, "HitboxFilterTag", ""),
    hitboxFilterType = utility.getAttribute(ref, "HitboxFilterType", "Exclude"),
    hitboxIgnoreCanCollide = utility.getAttribute(ref, "HitboxIgnoreCanCollide", false),

    -- speed
    speedStart = utility.getAttribute(ref, "Speed_Start", 1),
    speedEnd = utility.getAttribute(ref, "Speed_End", 1),
  }
end

function bezierCommon.getCurrentOriginCFrame(parent: Instance, fallback: CFrame)
  if parent:IsA("BasePart") then
    return parent.CFrame
  elseif parent:IsA("Attachment") then
    return parent.WorldCFrame
  end

  return fallback
end

function bezierCommon.findEndAttachments(ref: Attachment): (Attachment?, Attachment?)
  local endPoint = ref:FindFirstChild("End")
  local endT1 = endPoint and endPoint:FindFirstChild("T1")

  if endPoint and not endPoint:IsA("Attachment") then
    endPoint = nil
  end

  if endT1 and not endT1:IsA("Attachment") then
    endT1 = nil
  end

  return endPoint, endT1
end

function bezierCommon.validateParent(ref: Attachment): Instance?
  local parent = ref.Parent

  if not parent then
    return nil
  end

  if not parent:IsA("BasePart") and not parent:IsA("Attachment") then
    parent = ref
  end

  return parent
end

function bezierCommon.getPerpendicularVectors(tangent: Vector3)
  local right = tangent:Cross(Vector3.yAxis)

  if right.Magnitude < 0.001 then
    right = tangent:Cross(Vector3.zAxis)
  end

  right = right.Unit

  local up = tangent:Cross(right).Unit

  return right, up
end

function bezierCommon.createPropertyTween(
  scope: any,
  ref: Attachment,
  attrName: string,
  tweenDuration: number,
  startVal: number,
  endVal: number,
  setter: (number) -> (),
  getSpeed: () -> number,
  speedTween: any?
)
  if startVal == endVal then
    return
  end

  table.insert(
    scope,
    tween.fromParams(
      utility.getAttribute(ref, attrName .. "_Curve", utility.default_bezier),
      tweenDuration,
      function(alpha, deltaTime)
        setter(utility.lerp(startVal, endVal, alpha))
        return deltaTime * getSpeed()
      end,
      speedTween
    )
  )
end

return bezierCommon
