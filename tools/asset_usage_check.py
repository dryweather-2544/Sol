#!/usr/bin/env python3
"""Checks assets/sol/ without Godot (so it also runs in cloud sessions):
  1. integrity: every res:// path inside a copied .tres/.import resolves to a file; no lookdev paths (res://materials|decals|sky/) remain;
     SOURCE.txt hashes match the files; every .png has its .import and every .import still points at its own file.
  2. usage ("an asset is not integrated just because it exists"): every material folder, decal set and sound id under assets/sol must be
     referenced by game code (src/, scenes/, data/shaders/) -- or be listed on the `Deferred:` line of docs/N9_STATUS.md.
Exit 1 on an integrity problem or an unexplained orphan.   python3 tools/asset_usage_check.py [--allow-orphans]"""
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "sol"
HASHED_SUFFIXES = (".png", ".tres", ".wav", ".md")


def strip_comments(source: str) -> str:
    """Drops # (GDScript) and // (shader) comments so a mention in a comment cannot make an unused asset look integrated.
    A comment marker only counts when an even number of quotes precedes it (i.e. it is not inside a string)."""
    kept = []
    for line in source.splitlines():
        for marker in ("#", "//"):
            position = line.find(marker)
            while position != -1:
                if line[:position].count('"') % 2 == 0:
                    line = line[:position]
                    break
                position = line.find(marker, position + 1)
        kept.append(line)
    return "\n".join(kept)


def code_text() -> str:
    parts = []
    for folder, pattern in (("src", "**/*.gd"), ("scenes", "*.gd"), ("data", "**/*.gdshader")):
        for path in sorted((ROOT / folder).glob(pattern)):
            parts.append(strip_comments(path.read_text(errors="replace")))
    return "\n".join(parts)


def deferred_ids() -> set:
    status = ROOT / "docs" / "N9_STATUS.md"
    if not status.exists():
        return set()
    for line in status.read_text().splitlines():
        if line.startswith("Deferred:"):
            return {token.strip(" `") for token in line.split(":", 1)[1].split(",") if token.strip(" `")}
    return set()


def check_integrity() -> list:
    problems = []
    if not ASSETS.is_dir():
        return ["assets/sol does not exist"]
    for path in sorted(ASSETS.rglob("*")):
        if not path.is_file() or not path.name.endswith((".tres", ".import")):
            continue
        text = path.read_text(errors="replace")
        for old in re.findall(r"res://(?:materials|decals|sky)/[^\"']*", text):
            problems.append(f"{path.relative_to(ROOT)}: lookdev path left: {old}")
        for target in re.findall(r'(?:path|source_file)="res://(assets/sol/[^"]+)"', text):
            if not (ROOT / target).is_file():
                problems.append(f"{path.relative_to(ROOT)}: points at missing {target}")
        if path.name.endswith(".png.import"):
            own = re.search(r'source_file="res://([^"]+)"', text)
            if own is None or (ROOT / own.group(1)) != path.with_suffix(""):
                problems.append(f"{path.relative_to(ROOT)}: source_file does not name its own png")
            for name in re.findall(r"imported/[^\"]*-([0-9a-f]{32})\.", text):
                if own is not None and hashlib.md5(f"res://{own.group(1)}".encode()).hexdigest() != name:
                    problems.append(f"{path.relative_to(ROOT)}: imported-file md5 does not match its source path")
    for png in sorted(ASSETS.rglob("*.png")):
        if not Path(str(png) + ".import").is_file():
            problems.append(f"{png.relative_to(ROOT)}: no .png.import (it would import with default settings)")
    source = ASSETS / "SOURCE.txt"
    if not source.is_file():
        problems.append("assets/sol/SOURCE.txt missing")
    else:
        recorded = {}
        for line in source.read_text().splitlines():
            if re.match(r"^[0-9a-f]{64}  ", line):
                digest, name = line.split("  ", 1)
                recorded[name] = digest
        actual = {p.relative_to(ASSETS).as_posix(): p for p in ASSETS.rglob("*") if p.is_file() and p.name.endswith(HASHED_SUFFIXES)}
        for name in sorted(set(recorded) | set(actual)):
            if name not in actual:
                problems.append(f"SOURCE.txt lists {name} but the file is gone")
            elif name not in recorded:
                problems.append(f"{name} is in assets/sol but not in SOURCE.txt")
            elif hashlib.sha256(actual[name].read_bytes()).hexdigest() != recorded[name]:
                problems.append(f"{name}: sha256 differs from SOURCE.txt (hand-edited?)")
    return problems


def usage() -> list:
    code = code_text()
    deferred = deferred_ids()
    rows = []
    materials = ASSETS / "materials"
    if materials.is_dir():
        for folder in sorted(p for p in materials.iterdir() if p.is_dir()):
            for tres in sorted(folder.glob("*.tres")):
                rows.append(("material", tres.stem, tres.stem in code or folder.name in code and tres.stem == folder.name))
    decals = ASSETS / "decals"
    if decals.is_dir():
        for folder in sorted(p for p in decals.iterdir() if p.is_dir()):
            rows.append(("decal set", folder.name, folder.name in code and "DecalCatalog" in code and "decal_catalog" not in folder.name))
    audio = ASSETS / "audio"
    if audio.is_dir():
        ids = sorted({re.sub(r"_\d\d$", "", p.stem) for p in audio.rglob("*.wav")})
        for sound_id in ids:
            rows.append(("sound", sound_id, sound_id in code))
    sky = ASSETS / "sky"
    if sky.is_dir():
        rows.append(("sky", "tex_sky_starfield", "tex_sky_starfield" in code))
    return [(kind, name, used, name in deferred) for kind, name, used in rows]


def main() -> int:
    allow_orphans = "--allow-orphans" in sys.argv
    problems = check_integrity()
    for problem in problems:
        print("INTEGRITY", problem)
    rows = usage()
    orphans = [(kind, name) for kind, name, used, deferred in rows if not used and not deferred]
    for kind, name, used, deferred in rows:
        if not used:
            print(f"{'DEFERRED' if deferred else 'ORPHAN  '} {kind}: {name}")
    print(f"assets/sol: {len(rows)} usable items, {sum(1 for r in rows if r[2])} referenced by code, "
          f"{sum(1 for r in rows if not r[2] and r[3])} deferred, {len(orphans)} orphans, {len(problems)} integrity problems")
    return 1 if problems or (orphans and not allow_orphans) else 0


if __name__ == "__main__":
    sys.exit(main())
