/**
 * Result returned from emitting VFX effects
 */
export interface EmitResult {
  /**
   * Promise that resolves when the effect has finished playing
   */
  Finished: Promise<void>;

  /**
   * Clear all emitted effects
   */
  Clear(): void;

  /**
   * Pause the effect in place. Freezes particles, beams, sounds, mesh
   * animations, decal flipbooks, tweens, delays and other timed work
   * spawned by this emit call. Safe to call multiple times.
   */
  Pause(): void;

  /**
   * Resume a previously paused effect. Restores any state that was
   * captured at pause time and continues all frozen animations.
   * Safe to call multiple times.
   */
  Resume(): void;

  /**
   * Returns whether the effect is currently paused.
   */
  IsPaused(): boolean;
}

/**
 * Initialize the Forge VFX system.
 */
export function init(): void;

/**
 * Clean up and shut down the Forge VFX system.
 * Destroys all caches and disconnects event handlers.
 */
export function deinit(): void;

/**
 * Emit VFX effects from the provided instances.
 * Supports ParticleEmitters, Beams, Trails, Models, and tagged effects.
 * @param instances One or more Roblox instances to emit effects from
 * @returns Result object with a Finished promise
 */
export function emit(...instances: Instance[]): EmitResult;

/**
 * Emit VFX effects with a scale multiplier.
 * @param scale Scale multiplier for the effect
 * @param instances One or more Roblox instances to emit effects from
 * @returns Result object with a Finished promise
 */
export function emit(scale: number, ...instances: Instance[]): EmitResult;

/**
 * Emit VFX effects with a specific render depth.
 * @param depth Render priority depth for the effect
 * @param instances One or more Roblox instances to emit effects from
 * @returns Result object with a Finished promise
 */
export function emitWithDepth(
  depth: number,
  ...instances: Instance[]
): EmitResult;

/**
 * Enable a VFX instance and all its descendants.
 * For ParticleEmitters and Beams, sets the Enabled property directly.
 * For other instances, sets the "Enabled" attribute.
 * @param obj The instance to enable (propagates to descendants)
 */
export function enable(obj: Instance): void;

/**
 * Disable a VFX instance and all its descendants.
 * For ParticleEmitters and Beams, sets the Enabled property directly.
 * For other instances, sets the "Enabled" attribute.
 * @param obj The instance to disable (propagates to descendants)
 */
export function disable(obj: Instance): void;

/**
 * Scale the timing of VFX instances by a factor.
 * Adjusts speeds, lifetimes, durations, and rates across all effect types.
 * @param factor The time scale factor (>1 speeds up, <1 slows down)
 * @param instances One or more instances to retime (includes descendants)
 */
export function retime(factor: number, ...instances: Instance[]): void;

/**
 * Scale the size of VFX instances by a factor.
 * Adjusts particle sizes, beam widths, attachment distances, and more.
 * @param factor The size scale factor
 * @param instances One or more instances to resize (includes descendants)
 */
export function resize(factor: number, ...instances: Instance[]): void;

/**
 * Recolor VFX instances.
 * In "replace" mode, sets all colors to the given color (preserving HDR factor).
 * In "multiply" mode, blends the color with existing colors via HSV multiplication.
 * Skips BasePart descendants (only applies to directly passed BaseParts).
 * @param color The target color
 * @param mode "replace" to set colors directly, "multiply" to blend with existing
 * @param instances One or more instances to recolor (includes descendants)
 */
export function recolor(
  color: Color3,
  mode: "replace" | "multiply",
  ...instances: Instance[]
): void;

/**
 * Cache attributes for a VFX instance and optionally its descendants.
 * Strips attributes from instances and stores them in memory for faster access.
 * Only works on the client and for instances inside ReplicatedStorage.
 * @param obj The instance whose attributes to cache
 * @param shallow If true, only cache the instance itself (skip descendants)
 */
export function cacheAttributes(obj: Instance, shallow: boolean): void;

/**
 * Restore previously cached attributes back onto instances.
 * Only works on the client.
 * @param obj The instance whose attributes to restore
 * @param shallow If true, only restore the instance itself (skip descendants)
 */
export function restoreAttributes(obj: Instance, shallow?: boolean): void;
