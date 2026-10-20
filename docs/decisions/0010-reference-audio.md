# 0010 — Rodina reference audio pack and event routing

**Status:** accepted (N11).

**Context.** Sol's `AudioLibrary`/`AudioService` already had an event-oriented, fail-safe audio API
and a switchable synth fallback. Rodina 1.6.2 ships ordinary PCM WAV SFX that can be imported by
Godot; its music is proprietary `.egu`. The project owner explicitly requested local reference-audio
integration for this project.

**Decision.**
- Keep the existing `AudioLibrary` table and `AudioService` API.
- Add a `rodina` content pack under `assets/sol/audio/rodina/`, byte-identical to the local
  reference installation (no resampling or extension spoofing).
- Add optional `file` paths to table rows so authored filenames (including spaces/subfolders) can
  be used directly; a row without `file` keeps the original `id.wav` convention.
- Use new stable Sol IDs (`rod_...`) for reference assets and route real gameplay events to them.
  Existing IDs and Sol-Assets fallback files remain available when the reference pack or the
  `sample_audio` switch is off.
- Use a fixed pool of `AudioStreamPlayer3D` for projectile impacts; keep interface/interior sounds
  non-positional.
- Record every source path/hash and mapping in `SOURCE.txt`, `ATTRIBUTION.md`,
  `docs/N11_RODINA_AUDIO_INVENTORY.csv` and `docs/N11_RODINA_AUDIO_MAPPING.md`.

**Consequences.**
- The game now uses the authored Rodina engine, warp, atmosphere, weapon, door and UI recordings,
  while the existing event architecture and fallback behavior remain.
- The reference copies are 34 MB and are proprietary; they must not be redistributed. This is a
  project-owner-authorized local use recorded in ATTRIBUTION.
- Music is still Sol/Sol-Assets; `.egu` remains unsupported.
- A reference asset can be replaced/added without editing gameplay scripts: add a row and, if its
  filename does not match the convention, a `file` value.
