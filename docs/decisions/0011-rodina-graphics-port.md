# 0011 — Rodina warp camera and ship particle effects (rodina style)

**Status:** accepted (N13).

**Context.** The project owner asked for Rodina's own visual behaviour (warp, speed camera, engine and entry effects,
sky colours) ported into Sol, from the recovered Rodina 1.6.2 scripts. Rodina sets the camera FOV, chase distance
and angle from a warp blend each physics frame (`EGShipPlayer:SetMovementEffects`), shakes the camera through named
modules (`SetCameraVibrate`), and attaches named particle materials to named slots every frame
(`Engine:AttachParticles`). Its particle and render engine is C++ and was not recovered.

**Decision.**
- Presentation only, and only in the `rodina` VisualStyle (ADR 0007): the `sol` style keeps its camera and shows no
  Rodina effects. Flight physics, gears, speeds and saves are untouched; nothing new is saved.
- `LimnalWarpView` (main scene) ports the warp clocks and the camera formulas; `ChaseCamera` takes a follow distance,
  angle and shake; `CameraVibration` ports the shake modules.
- `ShipEffects` ports the slot logic; `RodinaEmitter` (one `GPUParticles3D` + a particle shader per slot) plays
  Rodina's particle materials, transcribed by a converter into `RodinaParticleDefs`. Engine-side field meanings are
  an explicit, documented reading (docs/N13_GRAPHICS_PORT.md §4) kept data-driven so it can be corrected.
- Lengths scale by one inferred factor, `RodinaEmitter.SHIP_SCALE` (0.27), Sol hull length over Rodina's.

**Consequences.**
- Rodina numbers and particle tables are in source files: owner-authorised local reference use, recorded in
  ATTRIBUTION.md; like ADR 0010's audio they must not be published while the Sol repository is public. On 2026-10-20 the project owner chose to push the `n13-graphics-port` branch to the public
  repository anyway (asked and answered in the N13 session).
- In the `rodina` style the chase camera sits Rodina's (scaled) 54 m back instead of Sol's 17 m.
- The emitter reading of Size/Yaw/Pitch/default blend and the sky colour roles need checking against real Rodina
  frames on the Mac.
