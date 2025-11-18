local Promise = require("@pkg/Promise")

export type scope = { any } & {
  depth: number,
  effects: EffectsService,
}

export type EmitEnv = {
  Finished: typeof(Promise.resolve()),
}

export type ObjectCache = {
  get: (id: string) -> any,
  free: (id: string) -> (),
}

export type ApiCaches = {
  shared_part: ObjectCache,
}

export type EffectsService = {
  init: (api: Api) -> (),
  deinit: () -> (),
  emit: (depth: number, ...Instance) -> EmitEnv,
  prepareEmitOnFinish: (obj: Instance, scope: scope) -> Folder?,
  emitNested: (part: Instance, depth: number) -> EmitEnv,
  emitOnFinish: (emitOnFinish: Folder?, targetParent: Instance, depth: number) -> EmitEnv,
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
