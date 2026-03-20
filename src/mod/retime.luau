local utility = require("@mod/utility")

local retime = {}

function retime.apply(obj: Instance, factor: number, invFactor: number)
  if obj:IsA("ParticleEmitter") then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "TimeScale_Duration")

    obj.Speed = NumberRange.new(obj.Speed.Min * factor, obj.Speed.Max * factor)
    obj.RotSpeed = NumberRange.new(obj.RotSpeed.Min * factor, obj.RotSpeed.Max * factor)
    obj.Lifetime = NumberRange.new(obj.Lifetime.Min / factor, obj.Lifetime.Max / factor)

    obj.Acceleration *= factor ^ 2
    obj.Drag *= factor
    obj.Rate *= factor
  elseif obj:IsA("Beam") then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "EffectDuration")
    utility.scaleAttribute(obj, invFactor, "Speed_Duration")
    utility.scaleAttribute(obj, invFactor, "Duration")

    obj.TextureSpeed *= factor
  elseif obj:IsA("Trail") then
    obj.Lifetime *= invFactor
  elseif obj:IsA("Sound") then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "EmitInterval")
    utility.scaleAttribute(obj, invFactor, "RepeatInterval")
    utility.scaleAttribute(obj, invFactor, "FadeOutTime")

    utility.scaleAttribute(obj, invFactor, "Volume_Duration")
    utility.scaleAttribute(obj, invFactor, "Speed_Duration")
    utility.scaleAttribute(obj, invFactor, "RollOff_Duration")
  elseif obj:IsA("Model") then
    if utility.isMeshVFX(obj) then
      utility.scaleAttribute(obj, invFactor, "EmitDelay")
      utility.scaleAttribute(obj, invFactor, "DestroyDelay")
      utility.scaleAttribute(obj, invFactor, "EmitDuration")
      utility.scaleAttribute(obj, invFactor, "EffectDuration")
      utility.scaleAttribute(obj, invFactor, "Speed_Duration")
      utility.scaleAttribute(obj, invFactor, "Duration")

      utility.scaleAttribute(obj, factor, "Rate")
      utility.scaleAttribute(obj, factor, "Part_RotSpeed_Start")
      utility.scaleAttribute(obj, factor, "Part_RotSpeed_End")
    else
      utility.scaleAttribute(obj, factor, "SpinRotation")

      utility.scaleAttribute(obj, invFactor, "EmitDelay")
      utility.scaleAttribute(obj, invFactor, "ResetDelay")

      utility.scaleAttribute(obj, invFactor, "SpinDuration")
      utility.scaleAttribute(obj, invFactor, "Scale_Duration")
      utility.scaleAttribute(obj, invFactor, "SpinSpeed_Duration")
    end
  elseif obj:IsA("Attachment") and obj:HasTag(utility.BEZIER_TAG) then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "DestroyDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "Duration")
    utility.scaleAttribute(obj, invFactor, "Speed_Duration")

    utility.scaleAttribute(obj, factor, "ProjectileSpeed")
    utility.scaleAttribute(obj, invFactor, "ProjectileLifetime")
    utility.scaleAttribute(obj, factor, "Rate")
    utility.scaleAttribute(obj, factor, "Part_RotSpeed_Start")
    utility.scaleAttribute(obj, factor, "Part_RotSpeed_End")
  elseif obj:IsA("Attachment") and obj:HasTag(utility.LIGHTNING_TAG) then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "DestroyDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "Duration")
    utility.scaleAttribute(obj, invFactor, "Speed_Duration")

    utility.scaleAttribute(obj, invFactor, "Color_Duration")
    utility.scaleAttribute(obj, invFactor, "Fill_Color_Duration")
    utility.scaleAttribute(obj, invFactor, "Fade_In_Duration")
    utility.scaleAttribute(obj, invFactor, "Fade_Out_Duration")
    utility.scaleAttribute(obj, invFactor, "Dissipate_Duration")

    utility.scaleAttribute(obj, factor, "ProjectileSpeed")
    utility.scaleAttribute(obj, invFactor, "ProjectileLifetime")
    utility.scaleAttribute(obj, factor, "Rate")
    utility.scaleAttribute(obj, factor, "RefreshRate")
  elseif
    obj:IsA("BasePart")
    and obj.Parent
    and utility.findFirstClassWithTag(obj.Parent, "Attachment", utility.SHOCKWAVE_TAG)
  then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "Size_Duration")
    utility.scaleAttribute(obj, invFactor, "Transparency_Duration")
    utility.scaleAttribute(obj, invFactor, "Lifetime")
    utility.scaleAttribute(obj, invFactor, "Duration")
    utility.scaleAttribute(obj, factor, "Rate_Start")
    utility.scaleAttribute(obj, factor, "Rate_End")
  elseif obj:IsA("RayValue") and obj:HasTag(utility.SCREENSHAKE_TAG) then
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
    utility.scaleAttribute(obj, invFactor, "EmitDuration")
    utility.scaleAttribute(obj, invFactor, "Scale_Duration")
  elseif obj:IsA("RayValue") then
    utility.scaleAttribute(obj, invFactor, "Duration")
    utility.scaleAttribute(obj, invFactor, "Speed_Duration")
    utility.scaleAttribute(obj, invFactor, "EmitDelay")
  end
end

function retime.batch(factor: number, ...: Instance)
  local invFactor = 1 / factor

  for _, instance in { ... } do
    retime.apply(instance, factor, invFactor)

    for _, desc in instance:GetDescendants() do
      retime.apply(desc, factor, invFactor)
    end
  end
end

return retime
