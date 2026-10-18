# mat_ship_screen

Procedural vector layouts, original, IBM Plex Mono (OFL, `fonts/ibm_plex/`). Three greyscale (R=G=B) PNGs, one `.tres` each.

| layout | file | px | used on (ship_visuals.gd, read-only) | visible face |
|---|---|---|---|---|
| `nav` | `mat_ship_screen_nav.png` | 1024 x 232 (4.41:1, ~465 px/m) | cockpit console screen, box 2.2 x 0.05 x 0.5 m | +Y (top) |
| `reactor` | `mat_ship_screen_reactor.png` | 512 x 352 (1.455:1, 640 px/m) | reactor wall screen (west wall), box 0.06 x 0.55 x 0.8 m | +X |
| `generic` | `mat_ship_screen_generic.png` | 512 x 352 | engine station wall screen (east wall), same box; any later screen | -X |

The manifest's 512 x 256 was replaced by sizes matching the real faces. Background 30, lines/glyphs 150-235 (the albedo floor
is 30); mean 38-55 of 255. Thin 1-2 px lines, no baked glow, and no word that claims a state (the tint does that).

- **Bake:** `godot --path lookdev -s res://bake/bake_ship_screen.gd` (needs a window; text via `bake/canvas_capture.gd`), then
  `godot --headless --path lookdev --import`, `python3 tools/set_texture_imports.py materials/mat_ship_screen`, import again,
  `godot --headless --path lookdev -s res://tools/make_screen_materials.gd`. Validate: `-s res://validate/check_screen.gd`.
- **Material (`mat_ship_screen_<layout>.tres`)**: `StandardMaterial3D`, `albedo_texture` = `emission_texture` = the PNG,
  `emission_enabled`, `emission = white`, **`emission_operator = MULTIPLY`**, `emission_energy_multiplier = 1.5` (do not set it from
  code), roughness 0.2, metallic 0, object-space triplanar with `uv1_scale`/`uv1_offset` so exactly one copy fills the box face
  (nav (1/2.2, 1, 1/0.5) + (0.5, 0, 0.5); reactor (1, 1/0.55, 1/0.8) + (0, 0.5, 0.5); generic the same with z scale negated).
- **Finding (lookdev):** the brief assumed emission multiplies the texture. Godot's default operator is ADD, which showed the
  state colour as a flat glow behind the texture (screens looked washed out and inverted). MULTIPLY fixes it; the `.tres`
  sets it and `check_screen.gd` fails if it is not set.
- **Tinting contract (what the game keeps doing):** set `albedo_color` AND `emission` to the state colour every frame
  (`signal_teal #5FC9A0` -> `signal_red #D9442E`; shut down = grey 0.15). Screens are dark where the texture is dark, so a lower
  tint also dims the glyphs. Use `reactor` for the west box, `generic` for the east box; a screen on the opposite wall needs the
  other `.tres` (text is mirrored on the back face).
- **Orientation [V lookdev]:** all three read correctly, unmirrored, in the game's box orientation from the player's side
  (`shots/mat_ship_screen_<view>_<game|proposed>_light.png`: four tints per shot: teal, amber, red, shut-down grey).
- **Validation (2026-10-18):** `check_screen` PASS (greyscale, sizes, 30..235, means, `.tres` settings; self-tests included);
  `check_imports` passes for the three PNGs (mipmaps, VRAM compressed).
- **Concerns (claude only, stills):** the proposed-light environment's glow (threshold 1.2) produced no visible bloom on these
  screens; VRAM compression (BC) of thin 1-2 px lines was not judged by eye; real screens in the game are small, so glyph text
  (14-22 px) will not be legible at a distance - the layout reads as texture there.
- **Status:** review. Not seen by a human.
