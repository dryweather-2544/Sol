# N14 distribution risk and proprietary reference material

The Sol repository (`github.com/dryweather-2544/Sol`) is public. The N11 and N13 work contains
proprietary Rodina reference material that was authorized only for this local project:

- `assets/sol/audio/rodina/` — 124 tracked files, byte-identical Rodina 1.6.2 WAVs;
- transcribed particle constants/tables and HUD/particle material values;
- proprietary formulas and data transcribed into GDScript/docs;
- external-only player-ship `Ship1.ShipOpen.egm` / physics mesh, **not copied into the repo**.

**Do not push this branch or merge it into the public default branch until the owner explicitly decides
on a private repository or removes the reference material.** `ATTRIBUTION.md` now states this policy;
the earlier "no Rodina assets may ever be added" line contradicted the tracked N11/N13 rows.

The original ship mesh/textures are present locally in
`/Users/arielbowyer/Documents/Deepseek workspace/rodina-recovery/game-reference/Data/Models` and
`Data/Textures`. They are not integrated: converting `.egm` and committing its textures would materially
increase redistribution risk, and replacing Sol's collision/interior around a new mesh is a separate
engineering task. A local-only converter/recreation can be pursued after an explicit rights decision.
