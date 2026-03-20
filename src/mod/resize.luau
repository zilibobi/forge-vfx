local utility = require("@mod/utility")

local resize = {}

function resize.apply(obj: Instance, factor: number)
  if obj:IsA("ParticleEmitter") then
    obj.Size = utility.scaleNumberSequence(obj.Size, factor)
    obj.Speed = NumberRange.new(obj.Speed.Min * factor, obj.Speed.Max * factor)
    obj.Acceleration *= factor
  elseif obj:IsA("Beam") then
    utility.scaleAttribute(obj, factor, "Width0_Start")
    utility.scaleAttribute(obj, factor, "Width1_Start")
    utility.scaleAttribute(obj, factor, "Width0_End")
    utility.scaleAttribute(obj, factor, "Width1_End")

    utility.scaleAttribute(obj, factor, "CurveSize0_Start")
    utility.scaleAttribute(obj, factor, "CurveSize1_Start")
    utility.scaleAttribute(obj, factor, "CurveSize0_End")
    utility.scaleAttribute(obj, factor, "CurveSize1_End")

    utility.scaleAttribute(obj, factor, "Length_Scale_Start")
    utility.scaleAttribute(obj, factor, "Length_Scale_End")

    obj.Width0 *= factor
    obj.Width1 *= factor
    obj.CurveSize0 *= factor
    obj.CurveSize1 *= factor

    local a0, a1 = obj.Attachment0, obj.Attachment1
    utility.scaleAttachmentDistance(a0, a1, factor)
  elseif obj:IsA("Trail") then
    local a0, a1 = obj.Attachment0, obj.Attachment1
    utility.scaleAttachmentDistance(a0, a1, factor)
  elseif obj:IsA("Sound") then
    obj.RollOffMinDistance *= factor
    obj.RollOffMaxDistance *= factor

    utility.scaleAttribute(obj, factor, "RollOff_Start")
    utility.scaleAttribute(obj, factor, "RollOff_End")
  elseif obj:IsA("Model") then
    if utility.isMeshVFX(obj) then
      local start = obj:FindFirstChild("Start")
      local goal = obj:FindFirstChild("End")

      if start and goal then
        start.Size *= factor
        goal.Size *= factor

        local startMesh = start:FindFirstChildOfClass("SpecialMesh")
        local goalMesh = goal:FindFirstChildOfClass("SpecialMesh")

        if startMesh and goalMesh then
          startMesh.Scale *= factor
          goalMesh.Scale *= factor
        end
      end
    else
      utility.scaleAttribute(obj, factor, "Scale_Start")
      utility.scaleAttribute(obj, factor, "Scale_End")
    end
  elseif obj:IsA("Attachment") and obj:HasTag(utility.LIGHTNING_TAG) then
    utility.scaleAttribute(obj, factor, "OffsetScale")
    utility.scaleAttribute(obj, factor, "Width_Start")
    utility.scaleAttribute(obj, factor, "Width_End")
  elseif
    obj:IsA("BasePart")
    and obj.Parent
    and utility.findFirstClassWithTag(obj.Parent, "Attachment", utility.SHOCKWAVE_TAG)
  then
    utility.scaleAttribute(obj, factor, "Radius")
    utility.scaleAttribute(obj, factor, "Length")
    utility.scaleAttribute(obj, factor, "MinSize")
    utility.scaleAttribute(obj, factor, "MaxSize")

    if obj:GetAttribute("LinearMagnitude") then
      obj.Size *= factor
      utility.scaleAttribute(obj, factor, "LinearMagnitude")
      utility.scaleAttribute(obj, factor, "AngularMagnitude")
    end
  elseif obj:IsA("RayValue") and obj:HasTag(utility.SCREENSHAKE_TAG) then
    utility.scaleAttribute(obj, factor, "Falloff")
  end
end

function resize.batch(factor: number, ...: Instance)
  for _, instance in { ... } do
    resize.apply(instance, factor)

    for _, desc in instance:GetDescendants() do
      resize.apply(desc, factor)
    end
  end
end

return resize
