# Provenance, licensing and evidence boundary

## Original work in this repository

The Sol source, research notes, measurements, probes, tests and implementation are original project
work unless otherwise noted. They may be used under the repository's existing licensing.

## Rodina material

Rodina is proprietary software by Elliptic Games LLC. The extracted 1.6.2 Lua, shaders, data files,
models and textures were inspected locally as evidence. They are **not** included in this
repository or in the published research branch.

The extracted files are used only to establish observable behaviour and technical relationships:
state fields, timing, gear tables, atmosphere/lighting equations, coordinate conventions and
similar facts. Sol's implementation is an independent Godot reimplementation; no proprietary
Rodina source, shader, model, texture or audio file is copied into Sol.

## Public reference media

The visual research used:

- 13 official Steam screenshots for app 314230;
- the Steam 1.4.2 trailer;
- images from the Steam “Ultimate Rodina Guide”;
- five YouTube gameplay videos.

Those images/videos are not included in this repository. `rodina-visual-observations/sources.csv`
contains the source URLs and frame timestamps used by the local reference library. The local media
library is kept outside the Sol repository and is not redistributed.

## Existing third-party assets in Sol

The working Sol project already contains third-party assets with their own attribution files,
including the CC-BY Cargo Spaceship model and MIT-licensed atmosphere-shader adaptation. Refer to
`ATTRIBUTION.md` and the asset-specific license files for those; they are not relicensed by this
research archive.

## What other agents may rely on

- The textual findings, measurements and implementation notes in this repository.
- The public URLs recorded in `rodina-visual-observations/sources.csv`.
- The Sol implementation itself.

Do not infer that the proprietary Rodina engine has been decompiled completely. The exact
engine-side camera filter and some model-space conventions remain unresolved; those gaps are stated
in the research documents.
