# Attribution and Licence Register

Every third-party file in this repository must have a row here **before** it is committed.
No Rodina code, assets, or data files may ever be added.

Allowed licences without asking: CC0, CC-BY (with credit below), MIT, BSD, Apache-2.0, OFL (fonts).
Anything else: ask the project owner first.

| Date added | Item | Author / source URL | Licence | Licence checked at (URL or file) | Files / folder in repo | Modified? |
|---|---|---|---|---|---|---|
| 2026-10-20 | Rodina 1.6.2 reference sound effects | Elliptic Games LLC; local Rodina 1.6.2 installation at `/Users/arielbowyer/Applications/Rodina-1.6.2/Data/Sounds` | Reference use authorized for this local project by the project owner; proprietary, not for redistribution | `assets/sol/SOURCE.txt` + `docs/N11_RODINA_AUDIO_INVENTORY.csv` | `assets/sol/audio/rodina/` | No — byte-identical copies, no conversion |
| 2026-10-20 | Rodina 1.6.2 reference data: 16 particle materials, player-ship effect/camera constants, 3 planets' atmosphere colours (transcribed numbers, no files copied) | Elliptic Games LLC; Rodina 1.6.2 `Scripts/DataGameplay/EGDataParticles.lua`, `EGDataShipPlayer.lua`, `EGDataPlanets.lua`, `Gameplay/EGVehicle.lua`, `EGBehaviorPlayer.lua`, `EGWorldObject.lua`, `EGEffect.lua`, `EGUtility.lua`, `Render/MenuFonts.lua` (HUD font names, sizes, colours), `DataGameplay/EGOptions.lua` (CameraFOV 60), `Data/EGEditorData.lua` (JariloTerrain diffuse colours), `DataGameplay/EGDataItems.lua` (ceiling light colours) (owner's private `rodina` repository) | Reference use authorized for this local project by the project owner (N13 brief); proprietary, not for redistribution | `docs/N13_GRAPHICS_PORT.md`, ADR 0011 | `src/flight/rodina_particle_defs.gd`, `src/flight/ship_effects.gd`, `src/camera/limnal_warp_view.gd`, `src/camera/camera_vibration.gd`, `src/core/rodina_math.gd`, `src/world/visual_style.gd` (RODINA_ATMOSPHERES, RODINA_ROOM_LIGHTS, RODINA_HUD_FONTS, Jarilo ground colours) | Ported to GDScript; values unchanged, lengths scaled at runtime |
| 2026-10-21 | Orbitron font (variable weight) | The Orbitron Project Authors; https://github.com/google/fonts/tree/main/ofl/orbitron | OFL-1.1 | `assets/sol/fonts/OFL-Orbitron.txt` (from https://raw.githubusercontent.com/google/fonts/main/ofl/orbitron/OFL.txt) | `assets/sol/fonts/Orbitron-Variable.ttf` | No (renamed from `Orbitron[wght].ttf`) |
| 2026-10-21 | Michroma font | The Michroma Project Authors; https://github.com/google/fonts/tree/main/ofl/michroma | OFL-1.1 | `assets/sol/fonts/OFL-Michroma.txt` (from https://raw.githubusercontent.com/google/fonts/main/ofl/michroma/OFL.txt) | `assets/sol/fonts/Michroma-Regular.ttf` | No |
| 2026-10-21 | Audiowide font | Brian J. Bonislawsky (Astigmatic); https://github.com/google/fonts/tree/main/ofl/audiowide | OFL-1.1 | `assets/sol/fonts/OFL-Audiowide.txt` (from https://raw.githubusercontent.com/google/fonts/main/ofl/audiowide/OFL.txt) | `assets/sol/fonts/Audiowide-Regular.ttf` | No |

## Credits shown in-game (CC-BY and similar)

_(none yet)_
