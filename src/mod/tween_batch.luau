local RunService = game:GetService("RunService")

export type TweenData = {
  step: (deltaTime: number) -> boolean,
  cleanup: (() -> ())?,
}

local batch = {}

local batches: {
  [number?]: {
    tweens: { TweenData },
    conn: RBXScriptConnection?,
  },
} = {}

local defaultBatch: {
  tweens: { TweenData },
  conn: RBXScriptConnection?,
}?

local function stepBatch(b: { tweens: { TweenData } }, deltaTime: number)
  local tweens = b.tweens

  local i = 1

  while i <= #tweens do
    local tween = tweens[i]
    local done = tween.step(deltaTime)

    if done then
      local last = #tweens

      if i ~= last then
        tweens[i] = tweens[last]
      end

      tweens[last] = nil

      if tween.cleanup then
        tween.cleanup()
      end
    else
      i += 1
    end
  end
end

function batch.register(priority: number?, tweenData: TweenData): () -> ()
  local b

  if priority == nil then
    if not defaultBatch then
      defaultBatch = {
        tweens = {},
        conn = RunService.RenderStepped:Connect(function(dt)
          stepBatch(defaultBatch :: any, dt)
        end),
      }
    end

    b = defaultBatch
  else
    b = batches[priority]

    if not b then
      b = {
        tweens = {},
      }

      batches[priority] = b

      local id = "forge::TweenBatch_" .. priority

      RunService:BindToRenderStep(id, priority, function(dt)
        stepBatch(b, dt)
      end)
    end
  end

  table.insert(b.tweens, tweenData)

  local removed = false

  return function()
    if removed then
      return
    end

    removed = true

    local idx = table.find(b.tweens, tweenData)

    if idx then
      local last = #b.tweens

      if idx ~= last then
        b.tweens[idx] = b.tweens[last]
      end

      b.tweens[last] = nil
    end

    if tweenData.cleanup then
      tweenData.cleanup()
    end
  end
end

return batch
