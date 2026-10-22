#!/usr/bin/env python3
"""Copy Sol's selected soundtrack from the owner's download folder into assets/sol/audio/mus/.

Usage: python3 tools/import_music.py "/Users/arielbowyer/Downloads/SOL MUSIC TO ADD"

The originals are never modified or moved. MP3 and OGG files are copied byte for byte; WAV and FLAC
masters are encoded to Ogg Vorbis (quality 6, bit-exact so a re-run gives the same bytes) because Godot does not import FLAC and the WAVs are
~30-57 MB each. Every source and output is listed with its SHA-256 in assets/sol/audio/mus/SOURCE.md.
Licences and authors: ATTRIBUTION.md and data/music/soundtrack.json.
"""
import hashlib
import os
import shutil
import subprocess
import sys

# output id -> source path relative to the download folder
TRACKS = {
    "mus_abyss.mp3": "Abyss.mp3",
    "mus_crash_landing.mp3": "Crash Landing.mp3",
    "mus_dead.mp3": "Dead.mp3",
    "mus_new_life.mp3": "New Life.mp3",
    "mus_nightmare.mp3": "Nightmare.mp3",
    "mus_peace_keeper.mp3": "Peace Keeper.mp3",
    "mus_pitch_black.mp3": "Pitch Black.mp3",
    "mus_pleading.mp3": "Pleading.mp3",
    "mus_purple.mp3": "Purple.mp3",
    "mus_claimed_by_the_void.mp3": "claimed_by_the_void.mp3",
    "mus_pulse.mp3": "pulse.mp3",
    "mus_sector.mp3": "sector.mp3",
    "mus_one_g.mp3": "ville_seppanen-1_g.mp3",
    "mus_space_echo.ogg": "space_echo.ogg",
    "mus_exploration_theme.ogg": "Exploration Theme.wav",
    "mus_safe_space_loop.ogg": "safe_space_loop.flac",
    "mus_destination_reached.ogg": "Space Tracks Vol.1/Destination reached.wav",
    "mus_discovery.ogg": "Space Tracks Vol.1/Discovery.wav",
    "mus_horizon.ogg": "Space Tracks Vol.1/Horizon.wav",
    "mus_intimate.ogg": "Space Tracks Vol.1/Intimate.wav",
    "mus_maneuvers.ogg": "Space Tracks Vol.1/Maneuvers.wav",
    "mus_orion.ogg": "Space Tracks Vol.1/Orion.wav",
    "mus_out.ogg": "Space Tracks Vol.1/Out.wav",
    "mus_rising_star.ogg": "Space Tracks Vol.1/Rising Star.wav",
    "mus_shooting_stars.ogg": "Space Tracks Vol.1/Shooting Stars.wav",
    "mus_starfield.ogg": "Space Tracks Vol.1/Starfield.wav",
    "mus_the_galaxy.ogg": "Space Tracks Vol.1/The Galaxy.wav",
    "mus_the_station.ogg": "Space Tracks Vol.1/The Station.wav",
    "mus_the_void.ogg": "Space Tracks Vol.1/The Void.wav",
    "mus_tricky_maneuver.ogg": "Space Tracks Vol.1/Tricky Maneuver.wav",
    "mus_unknown_ship.ogg": "Space Tracks Vol.1/Unknown Ship.wav",
    "mus_zero_g.ogg": "Space Tracks Vol.1/Zero G.wav",
}
# In the download folder but deliberately not imported (reason recorded in SOURCE.md).
NOT_IMPORTED = {
    "outer_space.mp3": "CC0, but a bright, busy retro-synth loop with strong regular transients; it fights Sol's lonely tone.",
    "safe_space.flac": "Same piece as safe_space_loop.flac with a fade in/out; the seamless-loop version is used instead.",
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    source_root = sys.argv[1]
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "sol", "audio", "mus")
    os.makedirs(out_dir, exist_ok=True)
    rows = []
    for out_name, rel in TRACKS.items():
        src = os.path.join(source_root, rel)
        dst = os.path.join(out_dir, out_name)
        if src.lower().endswith((".wav", ".flac")):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "6", dst], check=True)
            how = "encoded to Ogg Vorbis q6 (ffmpeg libvorbis), otherwise unchanged"
        else:
            shutil.copyfile(src, dst)
            how = "byte-identical copy"
        rows.append((out_name, rel, sha256(src), sha256(dst), how))
        print(out_name, how)
    manifest = os.path.join(os.path.dirname(__file__), "..", "data", "music", "SOURCES.md")
    with open(manifest, "w") as handle:
        handle.write("# Sol soundtrack files\n\nImported by `tools/import_music.py` from the owner's `~/Downloads/SOL MUSIC TO ADD/` "
                     "(originals left untouched there). Authors and licences: `ATTRIBUTION.md`; uses: `data/music/soundtrack.json`.\n\n"
                     "| File | Original | Original SHA-256 | File SHA-256 | Change |\n|---|---|---|---|---|\n")
        for row in rows:
            handle.write("| `%s` | `%s` | `%s` | `%s` | %s |\n" % row)
        handle.write("\n## In the download folder, not imported\n\n")
        for name, why in NOT_IMPORTED.items():
            handle.write("- `%s`: %s\n" % (name, why))


if __name__ == "__main__":
    main()
