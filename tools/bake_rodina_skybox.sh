#!/usr/bin/env bash
# Bake Rodina's skybox once per machine. Usage: tools/bake_rodina_skybox.sh [size]
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${GODOT:-}" ]]; then godot_bin="$GODOT"
elif command -v godot >/dev/null 2>&1; then godot_bin="godot"
elif [[ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
else echo "Godot not found. Set GODOT=/path/to/Godot." >&2; exit 2; fi
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true
"$godot_bin" --headless --path . -s res://tools/bake_rodina_skybox.gd -- "--size=${1:-1024}"
