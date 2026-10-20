# N11 — Rodina 1.6.2 reference audio integration

Branch `n11-rodina-audio`, based on `n10-warp` (`b1761aa`) and the latest remote base.

## What was integrated

The actual Rodina 1.6.2 WAV SFX were copied byte-for-byte from the local installation into
`assets/sol/audio/rodina/`. No music was copied: `Data/Music/*.egu` is a proprietary container and
Godot cannot import it; it was not renamed or guessed at.

The existing `AudioLibrary` / `AudioService` architecture is retained. Reference assets get stable
`rod_*` IDs and optional `file` paths in the library table. The old Sol IDs and synth fallback remain
available if the reference pack or `sample_audio` is off.

Integrated categories:

- four gear engines: PRECISION/DockEngine, COMBAT/combat loop, CRUISE/CruiseEngine,
  WARP/WarpEngine;
- responsive engine gain from throttle, speed load and the existing engine power/health factor;
- atmospheric entry fire, light/strong wind (only in atmosphere), RCS held loop and onset spurts;
- ship guns, projectile impact via a fixed pool of positional `AudioStreamPlayer3D`s, landing
  impacts, doors/airlock, alarms;
- UI: menu open/highlight/close, GUI click, inventory open/close and item pickup;
- jetpack and repair/extinguisher air loops.

WARP activation/exit is tied to the existing N10 gear transition: the authored gear-up/down cue
sounds and the warp loop crossfades; no second warp system was introduced. Engine loops are created
once and reused, faded at 4/s; power-starved/damaged engines lower their gain.

## Files

- `src/audio/audio_library.gd` — reference IDs, explicit source paths.
- `src/audio/audio_service.gd` — engine layers, warping/atmosphere/wind/RCS, event re-routing, 3D
  impact pool, lifecycle cleanup.
- `src/ui/{pause,inventory,workbench,reactor}_menu.gd` — optional reference UI audio.
- `scenes/main.gd` — injects the audio service into menus.
- `assets/sol/audio/rodina/` — 62 reference WAVs (34 MB), plus their Godot `.import` files.
- `assets/sol/SOURCE.txt` — hashes for every copied WAV.
- `docs/N11_RODINA_AUDIO_INVENTORY.csv` / `.json` — 62-file inventory with format/duration/rate/hash.
- `docs/N11_RODINA_AUDIO_MAPPING.md` — source/event mapping and inferred rows.
- `docs/decisions/0010-reference-audio.md` — architecture decision.
- `tools/n11_audio_check.gd` — live, display/audio-device playback check.
- `tools/import_rodina_audio.py` — reproducible copy and hash verification; no conversion.
- `ATTRIBUTION.md` — source/licence row.

## Verification

Headless suite:

```text
Godot 4.7.2 | files 60 | tests 320 | assertions 97,109 | failures 0
```

Live check (real main scene, CoreAudio, display):

```text
N11 AUDIO output=Default driver=CoreAudio
N11 AUDIO RESULT: PASSED (21 of 21 events passed)
```

It covered all four engine loops, atmosphere/wind, RCS loop and spurt, gear cues, gun fire/hit,
rock impact, door/airlock, pickup, menu highlight/click and alarm. The engine loop names/gear
mapping also have a unit test.

The legacy `tools/audio_check.gd` was not used as evidence: its loop-stop/restart harness reports
false negatives after it stops players. The new `tools/n11_audio_check.gd` tests the real service
paths and listens to the actual bus peaks.

## Not done / limits

- No human listening test; levels and loop seams are unjudged. The source WAVs have no loop metadata,
  so the full authored loop recordings are used as whole-file forward loops.
- Music is not integrated (`.egu` unsupported/proprietary).
- Footsteps, suit breath, helmet, seats, ramp motor and other events with no matching reference
  asset still use Sol's recordings/synth. They were not falsely mapped.
- Spatial audio is used for projectile impacts; engine/interior/UI sounds are intentionally 2D.
- Source assets are proprietary reference material authorized for this local project; they must not
  be redistributed. See `ATTRIBUTION.md`.
