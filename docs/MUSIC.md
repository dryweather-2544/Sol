# Sol's adaptive soundtrack

Code: `src/audio/music_director.gd` (MusicDirector, a child of AudioService), `src/audio/soundtrack.gd` (data loader and
picker). Data: `data/music/soundtrack.json` (every track, pool, gap and fade lives there; no gameplay script names a track).
Files: `assets/sol/audio/mus/`, imported by `tools/import_music.py`; provenance and checksums in `data/music/SOURCES.md`;
licences in `ATTRIBUTION.md`. ADR 0014. Settings: "Music volume" (`GameSettings.music_volume`, the `Music` bus, default 0.7).

## How the tracks were judged

The tracks were **not listened to**: the cloud session has no audio output. Each one was decoded (all 34 audio files in the folder decode),
measured (length, integrated loudness and loudness range, intro/outro silence, loop seams) and split into harmonic and
percussive energy, with spectrograms checked for pulse, build-ups and drops. The publishers' own descriptions were also
used. The assignments below are provisional: **listen in game** (the debug overlay shows `music: <context> - <track>`) and
move tracks between pools in `soundtrack.json`.

| Track (file) | Measured character | Used for |
|---|---|---|
| Orion | 5:24, very quiet sparse opening, slow swell around 1:40, little percussion | **Title theme** (always first on the title page) |
| Zero G | almost no percussion, steady | title (alternate), deep space, approach, interior |
| 1 G (Ville Seppänen) | 10 min, near-zero percussion, slow drifting drone, 40 s fade to silence | deep space (highest weight) |
| Horizon, Shooting Stars, Unknown Ship | 5+ min each, sustained, low percussion | deep space |
| claimed by the void | dense pad, no beat; author compares it to Stellaris | deep space |
| Starfield, The Void | steady pads (The Void has a heavier low pulse) | deep space; The Void also on Pebble |
| Abyss | dark sustained drone, no percussion | deep space (rare), discovery, danger, Cinder |
| Discovery, Destination reached, Maneuvers, The Station | moderate, gently pulsing, more motion | approaching a world; also climbing back out (ascent) |
| Tricky Maneuver, The Galaxy | large dynamic swings, sections with strong low pulses | atmospheric entry |
| Exploration Theme (seamless loop) | synth + piano, gentle repeating pattern; author: seamless loop | planet surface (Verdant weighted up) |
| New Life | sparse plucked pulses, quiet | planet surface |
| Intimate, Out, Rising Star | calm, lighter textures | planet surface; Intimate also in the ship |
| Safe Space (seamless loop) | lo-fi shimmer, no percussion; author: "safe room feeling" | inside the ship; surface |
| Peace Keeper | low steady pulse, dark | surface (Cinder weighted up), danger |
| pulse, sector | very quiet cold drones (levels raised +10 dB), author: "cold, tense" | strange discovery |
| Pleading | almost silent for 80 s, then a swell | strange discovery |
| space echo | 38 s, short slow theme | **arrival cue** (first visit to each world) |
| Pitch Black, Nightmare | strongest regular percussion | combat |
| Crash Landing | quiet for 71 s, then driving drums | combat, started at 1:11 |
| Dead, Purple | heavy low end / dense, dark | danger (enemies near, low hull, oxygen critical); Dead also combat |

Not imported: `outer_space.mp3` (CC0, but a bright, busy retro loop with strong regular transients that fights the lonely
tone) and `safe_space.flac` (same piece as the loop version, with a fade). Both stay in the download folder.

Levels: each file gets a dB offset from its measured loudness (target about -20 LUFS), and each context a gain under the
engines (deep space -2 dB, surface -3, interior -5, combat 0). These are first guesses, not tuned by ear.

## Contexts (from real state, `MusicDirector.snapshot()`)

| Context | When | Behaviour |
|---|---|---|
| menu | title page (PauseMenu.Page.TITLE, or Settings opened from it) | title theme at once; fades out when play starts, then a quiet gap |
| deep_space | seated, open space between worlds (`WorldRuntime.active_frame` is the system frame) | long gaps (60-180 s), 15% chance a gap stays silent |
| approach | seated, in a world's frame, still in space | carries the deep-space piece on; next piece from the approach pool |
| atmosphere | regime ENTERING/ATMOSPHERE while coming down | crossfades to an entry piece |
| ascent | the same regimes while climbing out (sticky; flipped by a clear climb or dive of 40 m/s) | carries the surface piece on, then approach-type pieces |
| surface | landed, below 2 km, or on foot outside | per-world weights (`body_weights`) |
| interior | walking or sitting inside the ship | mostly quiet (40% start chance, 2-5 min gaps); carries on whatever was playing, 3 dB lower |
| discovery | a wreck, beacon or anomaly is discovered (`DiscoveryLog.poi_discovered`), after the existing sting | one piece, then back; 6 min cooldown |
| danger | an alive enemy target exists but is not engaging, hull below 25%, or suit oxygen at 10% | dark pieces |
| combat | an alive enemy within its engage range (ships 1.5 km, drones 108 m), or the player is hit while enemies exist | immediate; holds 10 s after the last sign; then fades to 15-40 s of silence |

A change must hold 6 s before it counts (menu, combat and discovery count at once), so regime or altitude flicker never
restarts anything. The pause page ducks the music by 10 dB and freezes the context.

The arrival cue plays once per world per session, on `WorldRuntime.frame_changed` into a planet or moon; it waits for the
current piece to fade first and is cut by a fight. Loading a save counts the loaded world as already visited.
