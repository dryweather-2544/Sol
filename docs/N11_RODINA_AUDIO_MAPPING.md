# N11 — Rodina 1.6.2 reference audio mapping

**Source installation:** `/Users/arielbowyer/Applications/Rodina-1.6.2/Data/Sounds`
**Source evidence:** `/Users/arielbowyer/Applications/Rodina-1.6.2/Scripts/Gameplay/EGAudio.lua`,
`Scripts/DataGameplay/EGDataShipPlayer.lua`, `EGDataWeapons.lua`, `EGDataItems.lua`.
**Inventory:** `docs/N11_RODINA_AUDIO_INVENTORY.csv` (62 files; path, hash, size, format, channels,
sample rate, frames, duration).
**Copies:** `assets/sol/audio/rodina/` — byte-identical WAVs, no resampling or format conversion.
**Music:** `Data/Music/*.egu` is a proprietary container, not a WAV/OGG/MP3 Godot can import. It was
not renamed or guessed at; Sol's music is unchanged.

The table below is the integration mapping, not a filename-only guess. "Evidence" records the
authored Rodina name/context where it exists. Where a reference file has no surviving load table
entry, the mapping is marked **inferred**.

## Ship engine and flight loops

| Sol ID | Rodina source | Authored role / evidence | Behaviour in Sol |
|---|---|---|---|
| `rod_engine_dock_loop` | `DockEngine.wav` | `DockEngine`, loop, volume 1, `UpSpeed/DownSpeed=20`, `MinDistance=50` | PRECISION gear; gain from throttle, speed load, and engine power/health |
| `rod_engine_combat_loop` | `rodina_engine_combat.wav` | Reference engine loop; no `EGAudio.lua` load row — **inferred** combat engine | COMBAT gear; same responsive gain |
| `rod_engine_cruise_loop` | `rod_cruise1_v2.wav` | `CruiseEngine`, loop, volume .25, `MinDistance=50` | CRUISE gear; quiet sustained drive |
| `rod_engine_warp_loop` | `rod_warp1_v1.wav` | `WarpEngine`, loop, volume 1; `UpSpeed=5`, `DownSpeed=1` | WARP gear; gain rises with speed/load; gear-up/down cues mark entry/exit |
| `rod_atmos_entry_loop` | `rod_atmosentry.wav` | `AtmosphereFire`, loop, volume .75, `MinDistance=50` | atmosphere entry, driven by `ShipState.atmosphere_resistance`; silent in vacuum |
| `rod_wind_light_loop` | `rod_wind_light.wav` | atmospheric wind reference | light atmospheric wind outside/inside the ship, crossfaded |
| `rod_wind_strong_loop` | `rod_wind_super.wav` | `AtmosphereWind`, loop, volume .75 | stronger atmospheric wind; never played in vacuum |
| `rod_wind_sharp_loop` | `rod_wind_sharp.wav` | atmospheric wind reference | registered for the sharp-wind layer; currently not selected |
| `rod_rcs_loop` | `rod_rcs_loop.wav` | RCS/manoeuvring reference loop | **not wired** — removed after playtest (mouse-turn hiss) |
| `rod_rcs_spurt_2`, `rod_rcs_spurt_4` | `rod_rcs_spurt_2/4.wav` | `DoorOpen`/`DoorClose` in the original table, also RCS spurt material | **not wired** — removed after playtest |

Rodina's engine calls are in `EGDataShipPlayer.lua:423-432`: WARP gear plays `WarpEngine`, cruise
uses `CruiseEngine`, and dock uses `DockEngine`. Sol uses the same authored names but its own
continuous gain/crossfade logic, because its flight model and 3D listener differ.

## Weapons, impacts, doors, UI

| Sol ID | Rodina source | Evidence / original role | Sol event |
|---|---|---|---|
| `rod_gun_fire` | `Blaster/Single Shot 1.wav` | `GunBlasterFire` | player ship gun |
| `rod_gun_hit` | `Blaster/Player Weapon Hit 2.wav` | `GunBlasterHit` (also `SlideAttackHit`) | projectile impact, 3D pool |
| `rod_gun_miss` | `Blaster/Player - Weapon Miss 3.wav` | `GunBlasterDud` | available for misses; no miss event currently |
| `rod_missile_fire` | `Missile/rod_missile_fire_5.wav` | `GunMissileFire` | registered for future missile gameplay |
| `rod_missile_impact` | `Missile/explosion_large_01.wav` | `GunMissileImpact` | registered for future missile impacts |
| `rod_impact_rock` | `rod_impact_rock.wav` | `ImpactTerrain` | landing on a planet (also touchdown cue) |
| `rod_impact_metal` | `rod_impact_metal.wav` | metal-impact reference | landing when no planet frame is active |
| `rod_door_open` | `rod_rcs_spurt_2.wav` | `DoorOpen` | normal ship doors |
| `rod_door_close` | `rod_rcs_spurt_4.wav` | `DoorClose` | normal ship doors |
| `rod_airlock_open` | `rodina_door_large_1.wav` | `AirlockDoorOpen` | airlock doors |
| `rod_airlock_close` | `rodina_door_large_3.wav` | `AirlockDoorClose` | airlock doors; seal |
| `rod_alarm_once` | `rod_alarm_missile_once.wav` | missile alarm one-shot | fire/reactor/hull alert schedule; one-shot avoids a stuck looped voice |
| `rod_alarm_loop` | `rod_alarm_missile_loop.wav` | `MissileAlarm`, loop | registered; the schedule uses the one-shot variant |
| `rod_menu_open` | `rod_menu_open.wav` | `OpenComputer` | workbench/reactor/menu open |
| `rod_menu_highlight` | `rod_menu_highlight.wav` | `MenuHighlight` | button hover/focus |
| `rod_menu_unhighlight` | `rod_menu_unhighlight.wav` | `MenuUnhighlight` | menu close |
| `rod_gui_click` | `rodina_gui_click_6.wav` | `ActivateLight`/GUI click | confirm/click |
| `rod_item_pickup` | `Inventory/ItemPickup.wav` | `ItemPickup` | inventory gain |
| `rod_inventory_open`, `rod_inventory_close` | `Inventory/InventoryOpen.wav` | `InventoryOpen`/`InventoryClose` | inventory screen |
| `rod_radio_active` | `rodina_radio_active.wav` | `FTLRadioIncoming`, loop | registered for future radio |

## Level and loop rules

- Godot treats every WAV as an `AudioStreamWAV`; looped IDs are marked by the `_loop` suffix in
  `AudioLibrary.is_loop()` and `_prepared()` sets the whole file as a forward loop. The source
  files have no loop metadata; the files selected are the authored loop recordings.
- One-shot reference sounds use the existing one-shot voice pool, so weapon/impact/UI overlaps are
  bounded and priority can steal a lower-priority tail.
- Engine, wind, entry, fire and repair loops each use one lazily created `AudioStreamPlayer`;
  no player is created per frame. Gain fades at `ENGINE_FADE_PER_SECOND = 4`.
- Engine gain is `(0.18 + 0.82 load) * engine_factor`: load is the smoothed throttle or
  speed/top-speed, and `engine_factor` is the existing reactor × engine-health satisfaction. A
  dead or power-starved drive is quieter and cannot reach its normal top speed.
- Projectile impacts use a fixed pool of eight `AudioStreamPlayer3D` players positioned in the
  current render frame; engine/UI/interior sounds stay 2D as they are heard from the player's
  position or interface.

## What was not replaced

- **Music:** `.egu` is unsupported/proprietary; no conversion was attempted.
- **Footsteps, suit breath, helmet, seat, ramp motor, repair, alarms other than the reference
  missile alarm, and cabin hum:** Rodina's shipped `Data/Sounds` contains no direct equivalent for
  several of these, so Sol's existing Sol-Assets recordings/synth fallbacks remain where they carry
  the event. Reference files were not falsely mapped to unrelated sounds.
- **Voice/radio:** no spoken Rodina dialogue is present in `Data/Sounds`; the loop reference is
  available for future radio events only.
