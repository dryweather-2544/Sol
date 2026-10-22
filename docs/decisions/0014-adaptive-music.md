# ADR 0014: Adaptive music director

Date: 2026-10-22. Status: accepted.

## Context
ARCHITECTURE.md planned a Music bus, but Sol had no music. The owner chose a set of CC0 / CC-BY tracks and asked for
music that follows play (title, deep space, approach, atmospheric entry and ascent, surface, ship interior, discovery,
danger, combat) without repetition and with silence as part of the mood.

## Decision
- One `MusicDirector` node, created by `AudioService` as its child when there is a game session. No autoload, no new
  event bus: it reads existing state (PauseMenu page, ShipState.regime/altitude/hull, WorldRuntime.active_frame,
  GameSession.mode, enemy_targets, suit) and listens to two existing signals (`WorldRuntime.frame_changed`,
  `DiscoveryLog.poi_discovered`).
- The soundtrack is data (`data/music/soundtrack.json`, loaded by `Soundtrack`): tracks, per-context pools and weights,
  gaps, fades, which contexts let a playing piece carry on, per-world weights.
- The director runs on its own clock and exposes `step(delta, snapshot)`, so tests drive it without frames.
- Two music voices plus one cue voice on the new `Music` bus (its volume is `GameSettings.music_volume`).
- MP3/OGG files are kept as delivered; WAV/FLAC masters are encoded to Ogg Vorbis (q6) by `tools/import_music.py`.
  The music is not listed in `assets/sol/SOURCE.txt` (that file is generated from Sol-Assets); its manifest is
  `data/music/SOURCES.md`.

## Consequences
- Changing what plays where is a JSON edit. New contexts need a line in `MusicDirector.classify`.
- Arrival memory is per session (not saved): after restarting the game, a world's first visit plays the cue again once.
- About 138 MB of music is added to the repository.
