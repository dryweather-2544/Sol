#!/usr/bin/env bash
# Deterministic entry evaluation: a controlled 6 km/s, -30 deg approach followed by a deliberate
# 12 km/s, -70 deg approach. Captures telemetry and review frames under artifacts/entry_run/.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${GODOT:-}" ]]; then godot_bin="$GODOT"
elif command -v godot >/dev/null 2>&1; then godot_bin="godot"
elif [[ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
else echo "Godot not found. Set GODOT=/path/to/Godot." >&2; exit 2; fi
mkdir -p artifacts/entry_run
out=artifacts/entry_run
# A writable HOME keeps user:// saves out of the macOS Library sandbox during the probe.
home="${SOL_TEST_HOME:-$PWD/../sol_home}"
mkdir -p "$home/Library/Application Support/Godot"
HOME="$home" "$godot_bin" --path . --resolution 1280x720 -s res://tools/entry_probe.gd -- 6000 -30 "$out/controlled" 2>&1 | tee "$out/controlled.log"
HOME="$home" "$godot_bin" --path . --resolution 1280x720 -s res://tools/entry_probe.gd -- 12000 -70 "$out/steep" 2>&1 | tee "$out/steep.log"
