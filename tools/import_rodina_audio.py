#!/usr/bin/env python3
"""Copy Rodina 1.6.2 reference WAVs into Sol without conversion, and verify their hashes.

The source installation is never modified. Godot imports the copied PCM WAVs directly; no
resampling, renaming to another extension, or codec conversion happens here.

Usage:
  python3 tools/import_rodina_audio.py \
    --source "/Users/arielbowyer/Applications/Rodina-1.6.2/Data/Sounds" \
    --destination assets/sol/audio/rodina
  python3 tools/import_rodina_audio.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

DEST = Path("assets/sol/audio/rodina")
INVENTORY = Path("docs/N11_RODINA_AUDIO_INVENTORY.json")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_all(source: Path) -> None:
    if not source.is_dir():
        raise SystemExit(f"missing source directory: {source}")
    count = 0
    for original in sorted(source.rglob("*.wav")):
        relative = original.relative_to(source)
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            target.unlink()
        shutil.copy2(original, target)
        if digest(original) != digest(target):
            raise SystemExit(f"copy differs after write: {relative}")
        count += 1
    print(f"copied {count} byte-identical WAVs to {DEST}")


def check_all() -> None:
    rows = json.loads(INVENTORY.read_text())
    failures = 0
    for row in rows:
        source = Path(row["source"])
        target = Path(row["destination"])
        if not target.exists():
            print(f"MISSING {target}")
            failures += 1
            continue
        if digest(target) != row["sha256"]:
            print(f"HASH MISMATCH {target}")
            failures += 1
        if source.exists() and digest(source) != row["sha256"]:
            print(f"SOURCE CHANGED {source}")
            failures += 1
    print(f"checked {len(rows)} files, {failures} problems")
    raise SystemExit(1 if failures else 0)


def main() -> None:
    global DEST
    parser = argparse.ArgumentParser()
    parser.add_argument("--source")
    parser.add_argument("--destination", default=str(DEST))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    DEST = Path(args.destination)
    if args.check:
        check_all()
    elif args.source:
        copy_all(Path(args.source))
    else:
        parser.error("pass --source or --check")


if __name__ == "__main__":
    main()
