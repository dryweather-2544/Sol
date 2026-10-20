# Rodina visual profile — P0/P1 results

Branch: workspace clone of the known Sol checkout; active branch `play-combined`, synced to
`flight/canonical-rodina` after each commit. No push.

## P0 — controlled harness and reversible profile

Implemented a centralized `VisualStyle` (`src/world/visual_style.gd`) with two values:

- `sol` — the original Sol renderer, unchanged by default.
- `rodina` — the new alternate presentation profile.

Selection paths:

- `GameSettings.visual_style` persisted in `user://settings.cfg` (`video/visual_style`).
- **Pause menu → Settings → Visual style** toggles it live.
- `SOL_VISUAL_STYLE=sol|rodina` environment override for reproducible screenshot runs.
- `tools/visual_style_compare.sh` captures fixed orbit/50 km/5 km/500 m pairs.

The profile is presentation-only. `PilotCommand`, `FlightModel`, `ShipState`, saves, combat,
interaction and entry mechanics do not read it. `visual_style_test.gd` covers normalization,
persistence, both-way runtime switching, the Sol environment's original values, the Rodina
environment, the body palettes and the atmosphere shader selection.

Baseline before changes: **302 tests / 98,910 assertions / 0 failures**.
Final after P0/P1: **310 tests / 98,934 assertions / 0 failures**.

The Sol baseline screenshots are in `artifacts/visual_style_p0/`. Pixel-exact comparison between
two separate screenshot processes is not stable because clouds/weather and frame timing differ;
the no-op check is therefore covered by environment/shader assertions rather than a naive image
hash.

## P1 — what changed

### Palette and body data

- Added per-body Rodina palette fields to `BodyDef`: space, sky zenith, sky horizon, sun disc,
  surface light, ambient and impostor body colour.
- Authored distinct palettes for Aurelia (salmon/ochre/cyan), Cinder (ochre/orange), Verdant
  (teal/cyan) and the airless bodies (near-black purple).
- No terrain palette/material was changed in this pass.
- Rodina profile uses a warmer surface sun light for Aurelia, which shifts the existing green-grey
  terrain toward the reference's ochre/olive without editing the terrain.

### Space and sky

- `space_sky.gdshader` has a separate `rodina_mode` path:
  - near-black purple space (`#0a0311`-range) with the existing crisp starfield;
  - a flat two-colour zenith/horizon gradient driven by body colours;
  - stars remaining visible in the daylight sky;
  - a hard cyan sun disc with a restrained halo.
- The Sol sky path remains byte-for-byte the previous branch inside the `else` path.

### Atmosphere

- Added `data/shaders/rodina_atmosphere.gdshader`: a simple two-colour, altitude-free limb with a
  hard thin edge, based on the reference's flat atmosphere filter rather than Sol's Rayleigh/Mie
  integral.
- `AtmosphereShell` selects scatter/rim in Sol and the Rodina limb shader in Rodina mode. It removes
  the inside screen pass in Rodina mode; the sky shader supplies the inside-atmosphere sky.
- The orbital limb is cooled toward cyan/white while the ground sky remains salmon. This avoided the
  first version's broad brown/tan band.
- Clouds are hidden in Rodina mode, both local `CloudShell` and distant impostor clouds. The cloud
  system itself is untouched.

### Lighting and post

Rodina profile uses:

- linear tonemapping instead of ACES;
- no SSAO;
- lower ambient energy;
- a much lower glow/bloom contribution;
- no adjustment saturation boost (the per-body palette does the colour work);
- lower, coloured fog;
- a warm surface sun light and a per-body sky/sun disc.

Sol profile restores the original ACES exposure 0.70, SSAO, glow, adjustment, fog and sun.

## Evidence of improvement

Final contact sheets:

- `rodina-visual-research/contact_sheets/p1_space_final.jpg`
- `rodina-visual-research/contact_sheets/p1_surface_final.jpg`

Observed changes against the Rodina references:

- Orbit space is now near-black purple with crisp stars instead of a pale blue-white cloud/limb
  field.
- High-atmosphere sky is a salmon/teal graphic gradient with visible stars and a cyan sun disc,
  matching the reference's flat sky language much more closely.
- The hard white cloud shell is absent in Rodina mode.
- The orbital limb is a thin cool ring rather than the thick physical blue-white atmosphere.
- Ground-level ambient is darker and warmer; the existing green terrain shifts toward olive/brown.
- The Sol profile remains visually unchanged; the A/B screenshots show the original blue sky,
  white clouds and ACES appearance.

## What still looks wrong / deliberately deferred

- **Terrain is still Sol terrain**: green, grass-like and detail-dense. Rodina references use broad
  brown/ochre/purple landforms and sparse props. This is intentionally deferred to P3 because the
  task forbids changing terrain in this pass.
- **The cargo ship is still bright yellow/black and huge in frame**. Rodina's ship is a dark
  silhouette. Ship materials/camera framing are deferred to P2.
- **HUD/font is still modern Sol**. The cyan bitmap UI is deferred to P4.
- **Entry effects are still the smooth Sol plasma envelope**, not stepped fire/pixel overlays. Entry
  presentation is deferred to P5.
- The sun disc is a flat unlit star sphere with a hard edge; it lacks the reference's gentle painted
  halo. The sky shader provides a halo only where the sky is visible, not around the star model.
- The orbital limb is cyan/salmon and still somewhat wider than the reference's thinnest limbs.
- The sky uses the existing star panorama rather than a new painted Milky Way; the reference has a
  more prominent galaxy band.
- Body-specific palettes are authored, but only Aurelia has a released reference screenshot in this
  pass; Cinder/Verdant remain evidence-led approximations.
- No pixelated/retro presentation is applied. Rodina's RetroMode is optional and off by default,
  so that remains a player option, not the default identity.

## Performance

1600×900, merged build, same scene:

| Phase | Sol | Rodina |
|---|---|---|
| Orbit/atmosphere | ~99 fps, p95 11.8 ms | ~100 fps, p95 12.0 ms |
| Low descent | ~79 fps, p95 17.6 ms | ~81 fps, p95 17.8 ms |
| Ground | ~99 fps, p95 12.4 ms | ~99 fps, p95 12.0 ms |
| Draw calls | ~300 | ~286 |
| Max primitives | ~872k | ~811k |

Rodina mode is not more expensive; hiding clouds/scattering and the simpler limb reduce load.

## Files changed

- `src/world/visual_style.gd` (new)
- `src/core/game_settings.gd`
- `src/ui/pause_menu.gd`
- `src/world/body_def.gd`
- `src/world/star_system.gd`
- `src/world/space_environment.gd`
- `src/world/body_impostors.gd`
- `src/planet/atmosphere_shell.gd`
- `scenes/main.gd`
- `data/shaders/space_sky.gdshader`
- `data/shaders/rodina_atmosphere.gdshader` (new)
- `tests/unit/visual_style_test.gd` (new)
- `tools/visual_style_compare.sh` (new)

Not touched: flight model, atmospheric-entry mathematics, ship/interior materials, HUD, entry
particles, terrain meshes/materials, save schema.

## Next step

Stop at P1 as requested. P2/P3 should start with the ship silhouette and terrain colour/detail
budget; the current profile has the right sky/space/sun/atmosphere direction, but the ground and
ship still carry most of Sol's modern visual identity.
