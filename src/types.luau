local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

export type scope = { any } & {
  depth: number,
  effects: EffectsService,
}

export type EmitEnv = {
  Finished: typeof(Promise.resolve()),
}

export type ApiCaches = {
  shared_part: ObjectCache.ObjectCache,
}

export type EffectsService = {
  init: (api: Api) -> (),
  deinit: () -> (),

  emit: (depth: number, ...Instance) -> EmitEnv,
  emitNested: (part: Instance, depth: number) -> EmitEnv,
  emitOnFinish: (emitOnFinish: Folder?, targetParent: Instance, depth: number) -> EmitEnv,

  prepareEmitOnFinish: (obj: Instance, scope: scope) -> Folder?,
}

export type Api = {
  setup: boolean,

  scope: { unknown },
  caches: ApiCaches,

  init: (params: any?) -> (),
  deinit: () -> (),

  emit: (vfxOrScale: number | Instance, ...Instance) -> EmitEnv,
  emitWithDepth: (depth: number, ...Instance) -> EmitEnv,
}

return {}
