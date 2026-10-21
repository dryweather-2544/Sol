# Rodina audio comparisons (N14)

Status: **not yet human-auditioned in this branch**. Existing N11 integration is preserved.

Reference inventory: `docs/N11_RODINA_AUDIO_INVENTORY.csv` / `.json`, mapping in
`docs/N11_RODINA_AUDIO_MAPPING.md`, decision record `docs/decisions/0010-reference-audio.md`.

Tracked local-reference files: `assets/sol/audio/rodina/` (124 tracked files). They are byte-identical copies
of Rodina 1.6.2 sounds, authorized only for this local project and **not for redistribution**. The Sol repo is
public; do not push. See `ATTRIBUTION.md` and `docs/N11_REPORT.md`.

Known checks still required:

1. Audition engine crossfades and gear shifts in the real game.
2. Check WARP start/sustain/exit loop seams and gain.
3. Check atmospheric entry/wind and cockpit filtering.
4. Check weapon/impact/UI cues under rapid fire and pause.
5. Document any unsupported `.egu` music rather than claiming a port.

No audio changes were made in this pass.
