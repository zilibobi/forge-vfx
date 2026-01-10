local RunService = game:GetService("RunService")

local attr = require("@mod/attributes")
local types = require("@root/types")
local utility = require("@mod/utility")

local screen = {}

function screen.emit(ref: BasePart, scope: types.scope)
  if not ref:GetAttribute("Enabled") then
    return
  end

  local scale = attr.get(ref, "PartScale", vector.one)
  local distance = attr.get(ref, "PartDistance", 1.5)

  local pos = attr.get(ref, "OffsetPosition", vector.zero)
  local rot = attr.get(ref, "OffsetRotation", vector.zero) * utility.DEG_TO_RAD

  local originalCF = ref.CFrame
  local originalSize = ref.Size
  local originalColGroup = ref.CollisionGroup

  ref.CollisionGroup = "ForgeMouseIgnore"

  table.insert(scope, function()
    ref.Size = originalSize
    ref.CFrame = originalCF
    ref.CollisionGroup = originalColGroup ~= "" and originalColGroup or "Default"
  end)

  -- crazy how BindToRenderStep will always run before RenderStepped in studio
  local function frame()
    local camera = workspace.CurrentCamera

    local halfFovRad = math.rad(camera.FieldOfView / 2)
    local height = math.tan(halfFovRad) * distance * 2
    local width = (camera.ViewportSize.X / camera.ViewportSize.Y) * height

    local cf = camera.CFrame * CFrame.new(0, 0, -distance)

    ref.Size = Vector3.new(width, height, ref.Size.Z) * scale
    ref.CFrame = cf * CFrame.new(pos) * CFrame.fromOrientation(rot.x, rot.y, rot.z)
  end

  if not RunService:IsRunning() then
    table.insert(scope, RunService.RenderStepped:Connect(frame))
  else
    local id = utility.getRandomId()

    RunService:BindToRenderStep(id, Enum.RenderPriority.Last.Value + 2 + scope.depth, frame)

    table.insert(scope, function()
      RunService:UnbindFromRenderStep(id)
    end)
  end

  return true
end

return screen
