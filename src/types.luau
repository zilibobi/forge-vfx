local Promise = require("@pkg/Promise")
local ObjectCache = require("@obj/ObjectCache")

export type scope = { any } & {
  depth: number,
  effects: EffectsService,
  _context: { _promises: { any } }?,
  _onCancel: { () -> () }?,
}

export type EmitEnv = {
  Finished: typeof(Promise.resolve()),
  Clear: (self: EmitEnv) -> (),
  Pause: (self: EmitEnv) -> (),
  Resume: (self: EmitEnv) -> (),
  IsPaused: (self: EmitEnv) -> boolean,
}

export type ApiCaches = {
  shared_part: ObjectCache.ObjectCache,
}

export type EffectsService = {
  init: (api: Api) -> (),
  deinit: () -> (),

  emit: (depth: number, ...Instance) -> EmitEnv,
  emitNested: (part: Instance, depth: number, parentScope: scope?) -> EmitEnv,
  emitFromFolder: (folder: Folder?, targetParent: Instance, depth: number, parentScope: scope?) -> EmitEnv,
  emitOnFinish: (emitOnFinish: Folder?, targetParent: Instance, depth: number, parentScope: scope?) -> EmitEnv,

  prepareEmitFolder: (obj: Instance, folderName: string, scope: scope) -> Folder?,
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
