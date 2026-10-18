#!/usr/bin/env python3
"""Copies final deliverables from a Sol-Assets checkout into assets/sol/ (N9 asset pipeline, one group per integration step).

    python3 tools/import_assets.py --assets ~/Documents/Sol-Assets-combined ship_materials screens_decals audio_p0 ...
    python3 tools/import_assets.py --assets <checkout> --list            # group names and what they contain

What it does (and why):
  * refuses to run on a dirty Sol-Assets checkout, so assets/sol/SOURCE.txt can name an exact commit;
  * copies only the whitelist of the named groups (never lookdev/, _masters/, synth/, shots/, review/);
  * rewrites res://materials|decals|sky/ to res://assets/sol/... inside .tres files, and inside .png.import files rewrites the
    source path AND the md5 in the imported-file names (Godot names them <file>-<md5 of the res:// source path>.<ext>), so the copied
    import settings (mipmaps, VRAM compression, normal-map flags) stay valid and Godot does not rewrite them on first import;
  * does NOT copy decals.csv (Godot would import a .csv as a translation): decals.csv is turned into src/flight/decal_catalog.gd;
  * rewrites assets/sol/SOURCE.txt: Sol-Assets commit + sha256 of every deliverable (png, tres, wav, SOURCE.md).
Never hand-edit anything under assets/sol/: fix the asset in Sol-Assets and run this again. Python 3 standard library only."""
import argparse
import csv
import hashlib
import re
import subprocess
import sys
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
DEST = GAME_ROOT / "assets" / "sol"

GROUPS = {
    "ship_materials": {"folders": ["materials/mat_ship_floor_plate", "materials/mat_ship_composite_dark", "materials/mat_ship_brushed_metal",
                                   "materials/mat_ship_glass", "materials/mat_ship_paint_panel", "materials/mat_ship_rubber_mat",
                                   "materials/mat_hull_plating", "materials/mat_hull_nozzle"]},
    "screens_decals": {"folders": ["materials/mat_ship_screen", "decals/dec_ship_markings", "decals/dec_ship_damage"]},
    "terrain": {"folders": ["materials/mat_terrain_regolith", "materials/mat_terrain_rock_fractured", "materials/mat_terrain_soil_dry"],
                "files": [("lookdev/shaders/terrain_detail.gdshader", "data/shaders/terrain_detail.gdshader")]},
    "poi": {"folders": ["materials/mat_poi_rusted_metal", "materials/mat_poi_concrete"]},
    "sky": {"folders": ["sky"]},
    "audio_p0": {"audio_packages": ["B0", "B1"]},
    "audio_p1": {"audio_packages": ["B2"]},
}
COPY_SUFFIXES = (".png", ".png.import", ".tres", ".md")
HASHED_SUFFIXES = (".png", ".tres", ".wav", ".md")


def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


def git(assets: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(assets), *args], capture_output=True, text=True, check=True).stdout.strip()


def rewrite_tres(text: str) -> str:
    for prefix in ("materials", "decals", "sky"):
        text = text.replace(f"res://{prefix}/", f"res://assets/sol/{prefix}/")
    return text


def rewrite_import(text: str, new_source: str) -> str:
    old_source = re.search(r'source_file="([^"]+)"', text).group(1)
    return text.replace(old_source, new_source).replace(md5(old_source), md5(new_source))


def expand_manifest_paths(assets: Path, packages: list) -> list:
    """Files named by the manifest rows of the given packages (same pattern rules as Sol-Assets tools/verify_manifest.py)."""
    found = []
    with open(assets / "docs" / "ASSET_MANIFEST.csv", newline="") as handle:
        for row in csv.DictReader(handle):
            if row["package"] not in packages:
                continue
            for pattern in row["workspace_path"].split(";"):
                pattern = re.sub(r"<[a-z]+>", "*", pattern.strip())
                if not pattern or pattern.startswith("—"):
                    continue
                options = [pattern]
                while any("{" in option for option in options):
                    expanded = []
                    for option in options:
                        match = re.search(r"\{([^}]+)\}", option)
                        if match:
                            expanded += [option[:match.start()] + alternative + option[match.end():] for alternative in match.group(1).split("|")]
                        else:
                            expanded.append(option)
                    options = expanded
                for option in options:
                    found += sorted(str(path.relative_to(assets)) for path in assets.glob(option))
    return sorted(set(found))


def copy_group(assets: Path, name: str) -> int:
    spec = GROUPS[name]
    copied = 0
    for folder in spec.get("folders", []):
        source_folder = assets / folder
        if not source_folder.is_dir():
            sys.exit(f"{name}: missing folder {source_folder}")
        for source in sorted(source_folder.iterdir()):
            if not source.is_file() or not source.name.endswith(COPY_SUFFIXES):
                continue
            relative = source.relative_to(assets)
            target = DEST / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.name.endswith(".tres"):
                target.write_text(rewrite_tres(source.read_text()))
            elif source.name.endswith(".png.import"):
                target.write_text(rewrite_import(source.read_text(), f"res://assets/sol/{relative.as_posix()[:-len('.import')]}"))
            else:
                target.write_bytes(source.read_bytes())
            copied += 1
    for source_name, target_name in spec.get("files", []):
        source = assets / source_name
        if not source.is_file():
            sys.exit(f"{name}: missing file {source}")
        target = GAME_ROOT / target_name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        copied += 1
    if "audio_packages" in spec:
        for relative in expand_manifest_paths(assets, spec["audio_packages"]):
            if not relative.endswith(".wav"):
                continue
            target = DEST / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((assets / relative).read_bytes())
            copied += 1
    return copied


def write_decal_catalog(assets: Path) -> None:
    """decals.csv -> GDScript constants (the csv itself is not copied; see the module docstring)."""
    lines = ["class_name DecalCatalog", "extends RefCounted",
             "## GENERATED by tools/import_assets.py from Sol-Assets decals/*/decals.csv. Do not edit by hand.",
             "## One entry per decal: size_x / size_z / depth in metres, px sizes, the maps it has, the modulate hex, albedo_mix, tiles_x.", "",
             "const SETS := {"]
    for set_id in ("dec_ship_markings", "dec_ship_damage"):
        lines.append(f'\t"{set_id}": {{')
        with open(assets / "decals" / set_id / "decals.csv", newline="") as handle:
            for row in csv.DictReader(handle):
                entry = ('{"size_x": %s, "size_z": %s, "depth": %s, "px_w": %s, "px_h": %s, "maps": "%s", "modulate": "%s", '
                         '"albedo_mix": %s, "tiles_x": %s}') % (row["size_m_x"], row["size_m_z"], row["depth_m"], row["px_w"], row["px_h"],
                                                                row["maps"], row["modulate"], row["albedo_mix"], row["tiles_x"])
                lines.append(f'\t\t"{row["name"]}": {entry},')
        lines.append("\t},")
    lines.append("}")
    (GAME_ROOT / "src" / "flight" / "decal_catalog.gd").write_text("\n".join(lines) + "\n")


def write_source_file(assets: Path, commit: str, branch: str) -> int:
    hashed = sorted(path for path in DEST.rglob("*") if path.is_file() and path.name.endswith(HASHED_SUFFIXES))
    lines = ["# GENERATED by tools/import_assets.py. Do not edit by hand (tests/unit/asset_source_test.gd checks these hashes).",
             "source_repo: dryweather-2544/Sol-Assets", f"source_branch: {branch}", f"source_commit: {commit}", f"files: {len(hashed)}"]
    lines += [f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(DEST).as_posix()}" for path in hashed]
    (DEST / "SOURCE.txt").write_text("\n".join(lines) + "\n")
    return len(hashed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--assets", required=True, help="path to a Sol-Assets checkout")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true", help="skip the clean-checkout guard (SOURCE.txt will say so)")
    parser.add_argument("groups", nargs="*", help="group names (see --list)")
    arguments = parser.parse_args()
    if arguments.list:
        for name, spec in GROUPS.items():
            print(name, spec)
        return 0
    unknown = [group for group in arguments.groups if group not in GROUPS]
    if unknown or not arguments.groups:
        sys.exit(f"name one or more groups from: {', '.join(GROUPS)}")
    assets = Path(arguments.assets).expanduser().resolve()
    if git(assets, "status", "--porcelain") and not arguments.allow_dirty:
        sys.exit("Sol-Assets checkout is not clean; commit or stash there first (or --allow-dirty).")
    commit = git(assets, "rev-parse", "HEAD") + (" (DIRTY)" if arguments.allow_dirty else "")
    branch = git(assets, "rev-parse", "--abbrev-ref", "HEAD")
    for group in arguments.groups:
        print(f"{group}: copied {copy_group(assets, group)} files")
    if (DEST / "decals").is_dir():
        write_decal_catalog(assets)
    print(f"SOURCE.txt: {write_source_file(assets, commit, branch)} hashed files, commit {commit[:12]} ({branch})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
