# Visual fidelity reviews

## 2026-10-21 — high-speed ship, camera and exhaust

**Reference reviewed:** trailer 78–92 s (COMBAT SPEED, 28 frames at 2 fps) and 96–110 s (CRUISE
SPEED, 28 frames at 2 fps), plus official Steam orbit screenshot `steam06_orbit_ochre.jpg`.

**Current Sol captures:**

- `/tmp/n13_sol_rodina/rodina_planet_orbit.png` — Rodina style orbit.
- `/tmp/n13_sol_effects/rodina_planet_effects.png` — Rodina style entry/engine view.
- `Sol/app_userdata/Sol/n12_render_check/cruise.png` — Rodina style chase at 5,000 m/s.

**Observed discrepancies, in priority order:**

1. **High-speed exhaust/wake is missing.** Reference has two long lime trails and a huge blue/white
   speed-streak field at COMBAT/CRUISE. Sol has only short cyan-white plumes.
2. **Ship is too large in chase view.** Reference ship is a small dark silhouette; Sol's 17 m chase
   camera fills roughly half the frame with a bright hull.
3. **Ship value is too light.** Reference hull reads black; Sol's Rodina-style hull is tan/grey with
   large cyan exhaust discs.
4. **Orbit composition:** Sol's planet occupies a smaller part of the frame than the official orbit
   shot; stars lack the painted Milky Way band visible in reference.
5. **Entry effect** is smooth orange vs reference blocky purple/orange; not addressed in this pass.
6. **HUD** is a debug overlay, not the cyan bitmap reference; not addressed in this pass.

**Selected change this pass:** implement the high-speed identity gap with (a) a far Rodina-style
chase offset, (b) a darker Rodina-style hull tint, and (c) two state-driven lime exhaust trails.
No flight-model or save changes. Entry/HUD/starfield remain follow-up work.

**Verification plan:** capture Rodina-style chase at rest, COMBAT, CRUISE and WARP with the same
planet-behind setup; compare ship scale, trail length and camera stability; ensure trail emission is
zero at low speed and when the style is `sol`.

### Outcome after the first implementation (2026-10-21)

- Rodina chase offset: 17 m -> **85 m** (`VisualStyle.chase_camera_offset`). The ship now reads as a
  small dark silhouette with negative space, closer to the trailer's CRUISE/COMBAT framing.
- Rodina hull tint: `(0.74,0.77,0.84)` -> **`(0.28,0.30,0.34)`**. The silhouette is now dark; the
  small cyan engine points remain.
- Added two **dotted lime/yellow trail meshes** driven by actual speed/gear. They appear at and above
  COMBAT speed, are hidden below 180 m/s and in the `sol` style, and switch to blue/white for WARP
  (the WARP colour is an inference; no labelled WARP reference was found).
- Current verification capture: `/tmp/n13_final_cruise.png` (5,000 m/s, tangential motion over
  Aurelia, Rodina style). It shows the small dark ship and two separated dotted trails; this is a
  clear structural improvement over the previous large bright ship with only short plumes.
- A second capture with the user's asset switches temporarily enabled is
  `/tmp/n13_assets_cruise.png`; the textured terrain and hull remain subordinate to the dark ship
  silhouette. The user's persisted settings were restored after capture (`asset_materials=false`,
  `decals=false`, `terrain_detail=false`, `starfield=false`, `visual_style=rodina`).
- Remaining visual gap in that capture: trails are straighter/sparser than the reference's curved
  twin trails; the debug HUD dominates; the reference's painted galaxy band and blocky entry fire
  are still absent. Those are the next priorities, not reasons to undo this change.
- Tests: 324 tests / 97,129 assertions / 0 failures. The camera-rebase test from N12 still passes.

**Next iteration priority:** add the blue/white COMBAT-SPEED streak field or a galaxy/sky pass only
after checking the corresponding reference sequence; do not add invented WARP visuals.


### Second iteration — orbit sky (2026-10-21)

Reference: `frames/selected/space/steam06_orbit_ochre.jpg` (official orbit screenshot) and the
trailer orbit frames; both show a broad violet/brown dust band behind the crisp stars.

Current Sol with the user's asset switches off had only hash stars and a flat violet background.
Added a Rodina-only `galaxy_amount`/`galaxy_color`/`galaxy_normal` sky contribution. The first
version used per-cell hash dust and showed obvious block stair-steps; the second used a high-frequency
sine field and showed diagonal stripes. Both were rejected. The accepted version is a soft broad
exp(-angle²) band with a constant diffuse dust level.

Capture: `/tmp/n13_galaxy/rodina_planet_orbit.png`. It is closer in sky value and broad negative
space than the previous flat star sky, but the reference's actual painted galaxy texture is stronger
and more structured. The shipped `sky/tex_sky_starfield.png` is the intended texture; the user's
current `starfield=false` setting hides it, so this procedural band is only a fallback under that
setting. Sol style keeps `galaxy_amount=0` and is unchanged.

Tests after both iterations: 324 tests / 97,129 assertions / 0 failures.


### Third iteration — COMBAT-SPEED streak field (2026-10-21)

Reference: trailer 78–92 s COMBAT SPEED sequence. Added a Rodina-only additive screen layer with
long left-weighted blue/white streaks, gated by combat/cruise/warp speed and hidden in precision,
Sol style and menus. The first version read as short white rain; the accepted version uses longer
smears and lower intensity.

Capture: `/tmp/n13_streak_cruise2.png`.

### Fourth iteration — blocky entry fire (2026-10-21)

Reference: `trailer004_purple_entry_fire.jpg` and `trailer005_entry_fire.jpg`. Replaced the small
smooth orange entry sparks with large hard-edged additive orange/purple squares and added a purple
exposure wash driven by `ShipState.atmosphere_resistance`. The fire was enlarged and made orange-
dominant after the first capture. Speed trails and the blue speed-streak layer are suppressed during
atmospheric entry so the entry effect does not conflict with cruise effects.

Capture: `/tmp/n13_entry_probe/entry3.png`.

Remaining entry gap: reference fire mass is even larger and more screen-filling; current blocks are
still centred around the ship rather than spilling across the lower left. This is the next visual
iteration, not a completion claim.

Tests after all four visual passes: 326 tests / 97,138 assertions / 0 failures.
