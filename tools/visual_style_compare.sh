#!/bin/bash
# Reproducible P0/P1 visual A/B harness. Run from the Sol project root.
set -euo pipefail
GODOT="${GODOT:-/Users/arielbowyer/Downloads/Godot.app/Contents/MacOS/Godot}"
HOME_DIR="${SOL_TEST_HOME:-/Users/arielbowyer/Documents/Deepseek workspace/sol_home}"
OUT="${1:-artifacts/visual_style}"
mkdir -p "$OUT"
for style in sol rodina; do
  for scene in "300000 0 orbit" "50000 0 high" "5000 5 low" "500 8 ground"; do
    set -- $scene
    altitude=$1; pitch=$2; name=$3
    HOME="$HOME_DIR" SOL_VISUAL_STYLE="$style" "$GODOT" --path . --resolution 1280x720 \
      -s res://tools/screenshot.gd -- "$PWD/$OUT/${style}_${name}.png" "$altitude" "$pitch"
  done
done
