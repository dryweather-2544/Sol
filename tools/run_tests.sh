#!/usr/bin/env bash
# Run Sol's headless tests. Usage: tools/run_tests.sh   (from anywhere)
# Finds Godot via $GODOT, then `godot`, then the macOS app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${GODOT:-}" ]]; then godot_bin="$GODOT"
elif command -v godot >/dev/null 2>&1; then godot_bin="godot"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="/Applications/Godot.app/Contents/MacOS/Godot"
elif [[ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
else echo "Godot not found. Set GODOT=/path/to/Godot or install Godot 4.7.2." >&2; exit 2; fi

echo "Using: $godot_bin"; "$godot_bin" --version
# First run (or after deleting .godot/) needs an import so class_name scripts are registered.
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true
"$godot_bin" --headless --path . -s res://tests/run_tests.gd "$@"
