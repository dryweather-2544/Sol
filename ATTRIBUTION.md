# Attribution and Licence Register

Every third-party file in this repository must have a row here **before** it is committed.
No Rodina code, assets, or data files may ever be added.

Allowed licences without asking: CC0, CC-BY (with credit below), MIT, BSD, Apache-2.0, OFL (fonts).
Anything else: ask the project owner first.

| Date added | Item | Author / source URL | Licence | Licence checked at (URL or file) | Files / folder in repo | Modified? |
|---|---|---|---|---|---|---|
| 2026-10-18 | Atmospheric scattering shader (adapted into data/shaders/atmosphere_scatter.gdshader) | Sean O'Neil (GPU Gems 2, 2004); Godot port by Cuberact, https://github.com/cuberact/godot-cuberact-planet-chunked-lod | MIT | repository LICENSE (checked via the GitHub API, licence MIT) | data/shaders/atmosphere_scatter.gdshader | Yes: normalised units, analytic entry/exit/planet hit, camera from the model matrix |
| 2026-10-18 | Cargo Spaceship (glTF, used as the player ship exterior in the hidden-interior prototype) | blaice (https://sketchfab.com/blaice), https://sketchfab.com/3d-models/cargo-spaceship-a53147cc2da943e7ae07f1e0b0a31518 | CC-BY 4.0 | Sketchfab download dialog ("CC Attribution") and license.txt in the zip | assets/third_party/ships/cargo_spaceship/ | Textures re-imported with VRAM compression and mipmaps (tools/third_party_texture_import.py); scaled and placed in code |

## Credits shown in-game (CC-BY and similar)

"Cargo Spaceship" by blaice, CC BY 4.0, https://sketchfab.com/3d-models/cargo-spaceship-a53147cc2da943e7ae07f1e0b0a31518 (needed in-game credits if this hull ships)
