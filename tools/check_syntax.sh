#!/usr/bin/env bash
# Syntax-only check of every GDScript file, usable WITHOUT Godot (e.g. in the cloud session).
# Needs: pip install gdtoolkit. This catches parse errors only - it cannot run or type-check code.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for file in $(find src tests -name '*.gd'); do
  gdparse "$file" >/dev/null 2>&1 || { echo "PARSE ERROR: $file"; status=1; }
done
[[ $status -eq 0 ]] && echo "All GDScript files parse."
exit $status
