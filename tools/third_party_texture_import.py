#!/usr/bin/env python3
"""Gives the PNG textures of a third-party glTF the same import settings N9's own textures use: VRAM compressed, mipmaps on,
normal maps flagged. Godot imports glTF textures lossless and without mipmaps when it runs headless (it only switches them when the
texture is first used in the editor), which cost about 0.5 GB of video memory for one ship.
    godot --headless --import            # creates the .png.import files
    python3 tools/third_party_texture_import.py assets/third_party/ships/cargo_spaceship/textures
    godot --headless --import            # re-imports with the new settings
Python 3 standard library only."""
import re
import sys
from pathlib import Path

for folder in sys.argv[1:]:
    for import_file in sorted(Path(folder).glob("*.png.import")):
        text = import_file.read_text()
        text = re.sub(r"^compress/mode=\d+", "compress/mode=2", text, flags=re.M)
        text = re.sub(r"^mipmaps/generate=\w+", "mipmaps/generate=true", text, flags=re.M)
        is_normal = "normal" in import_file.name.lower()
        text = re.sub(r"^compress/normal_map=\d+", "compress/normal_map=%d" % (1 if is_normal else 0), text, flags=re.M)
        import_file.write_text(text)
        print("patched", import_file.name, "(normal map)" if is_normal else "")
