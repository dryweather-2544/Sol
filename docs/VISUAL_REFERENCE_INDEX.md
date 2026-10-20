# Visual reference index

Local reference archive: `/Users/arielbowyer/Documents/Deepseek workspace/rodina-visual-research/`.
This is research material outside the repository and is not shipped with Sol. All observations below
were made by inspecting the files, not by trusting their filenames.

## Source media

| File | Duration / format | What was inspected | Sol systems informed |
|---|---|---|---|
| `source/trailer.mp4` | 124.09 s, 1920×1080, 29.97 fps H.264/AAC, 3718 frames | Contact sheet every 3 s; 2 fps extraction of 78–92 s (combat-speed sequence) and 96–110 s (cruise/trails sequence); individual 1920×1080 frames | WARP/high-speed, exhaust trails, camera framing, entry, lighting |
| `source/video/T90Pw7FcJx8.webm` | 2299.9 s, 640×360 VP9, 30 fps | Full-video contact sheets (`frames/videos/T90_sheet_1..4`); selected gameplay/asteroid frames | ship scale, space, combat, terrain |
| `source/video/RdXAbinofDE.mkv` | 833.7 s, 640×360 VP9/AAC, 30 fps | Full-video contact sheets; selected frames | orbit, planets, interiors |
| `source/video/0Idoe7EjOZU.webm` | 1102.9 s, 640×360 VP9/Opus, 30 fps | Full-video contact sheets; selected frames | surface, ground, interiors |
| `source/video/oVyZD1wo0vs.mkv` | 3811.0 s, 640×360 VP9/AAC, 29.97 fps | Full-video contact sheets; selected frames | long-session visuals, planets, combat |
| `source/video/yLfsaJK63wo.webm` | 1252.0 s, 640×360 VP9/Opus, 30 fps | Full-video contact sheets; facecam-heavy, used sparingly | recent UI/interior/ground |
| `source/steam/*.jpg` | 13 official Steam screenshots | All inspected at full resolution through the master contact sheet | palette, ship silhouette, interiors, atmosphere |
| `source/guide/*.jpg` | 15 community-guide images (one corrupt, excluded) | Inspected in the master/selected sheets | ground, sky, ice/planet palettes |

Selected extracted frames are under `frames/selected/`; provenance is in `sources.csv`; contact
sheets are under `contact_sheets/`. Current Sol comparison captures are under `frames/sol/`.

## Trailer sequences inspected frame-by-frame

### 78–92 s — COMBAT SPEED

Extracted at 2 fps to `/tmp/n13_ref/trailer_speed` (28 frames; contact sheet). Direct observations:

- A huge bright blue/white streak mass occupies the left third of the frame and streams aft past a
  small, near-black player ship at centre. The streaks are chunky, stepped and additive, not a smooth
  cinematic motion blur.
- Fine green/yellow weapon trails curve away from the ship on the right; a large red/brown planet
  occupies the upper-right background.
- HUD reads `COMBAT SPEED`; the ship stays roughly centred while the environmental streaks convey
  speed. The effect continues across multiple seconds rather than being a single flash.
- Ship is far smaller relative to the frame than Sol's current 17 m chase camera composition.

Representative still: `frames/selected/effects/trailer029_combat_speed.jpg` (source `00:84`).

### 96–110 s — CRUISE SPEED / dark planet

Extracted at 2 fps to `/tmp/n13_ref/trailer_trails` (28 frames; contact sheet; later frames are title
cards). Direct observations:

- The ship is a black silhouette against a purple planet.
- Two long, dotted trails run from the ship toward the upper-right. Their colour is lime/yellow-green
  with a bright core and a few white/cyan accents. They persist over the sequence and follow the
  ship's direction, rather than being a single exhaust puff.
- HUD reads `CRUISE SPEED`.
- No thick atmospheric veil covers the planet; the limb is a thin coloured edge.

Representative still: `frames/selected/space/trailer035_dark_planet_trails.jpg` (source `00:102`).

## Other reference categories

- **Space/orbit:** `frames/selected/space/steam06_orbit_ochre.jpg` — ochre planet, near-black violet
  space, crisp star points, thin limb, no broad blue-white atmospheric shell.
- **Cockpit:** `frames/selected/cockpit/steam02_cockpit_sunset.jpg` — dark cockpit silhouette, cyan
  HUD, low ambient, large sun/horizon.
- **Entry:** `frames/selected/entry/trailer004_purple_entry_fire.jpg` and
  `trailer005_entry_fire.jpg` — screen-filling blocky purple/orange fire around the ship; smooth
  translucent plasma is not the reference look.
- **Surface/sky:** `steam01_salmon_sky_mountains.jpg`, `steam03_purple_battlefield.jpg`,
  `steam07_cyan_ice.jpg`, `guide09_ice_planet.jpg` — flat, highly saturated two-colour skies; hard
  sun; dark terrain silhouettes; visible stars in daylight.
- **Interiors/HUD:** `steam00_inventory_room.jpg`, `steam04_green_corridor.jpg`,
  `steam05_red_fire_room.jpg`, `video16_airlock_interior.jpg` — dark grey/green boxes, sparse props,
  strong coloured practicals, cyan angular bitmap HUD.

## WARP gap

The corpus contains no unambiguous long WARP jump sequence with a readable WARP HUD. The combat and
cruise sequences above are the only speed-effect evidence with clear labels. I searched the trailer
and all five full-video contact sheets; `newY_024`/`025`, `T90_014` and the trailer frames show
combat/cruise, not WARP. No WARP frame-by-frame claim is made here; WARP visual work must remain
labelled as inference until such a sequence is found or captured from the running Rodina build.

## Current Sol comparison captures

- `/tmp/n13_sol_rodina/rodina_planet_orbit.png` — current `rodina` style, orbit. Compared with
  `steam06_orbit_ochre.jpg`.
- `/tmp/n13_sol_effects/rodina_planet_effects.png` — current `rodina` style, held entry-speed shot.
- `/tmp/sol_n12_probe/frame_0120.png` — current N12 chase camera at action before this pass.
- Prior local comparison corpus: `Sol-canonical-merge/artifacts/visual_style_p23/` and
  `Sol-visual/artifacts/`.
- After the N13 high-speed pass: `/tmp/n13_final_cruise.png` (Rodina style, 5,000 m/s tangent over
  Aurelia) — small dark ship, two dotted lime trails; `/tmp/n13_assets_cruise.png` repeats it with
  the Sol-Assets switches temporarily enabled.
