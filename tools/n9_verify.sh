#!/usr/bin/env bash
# N9 verification on the Mac: everything that could not be run in the cloud session that wrote the integration.
#   tools/n9_verify.sh                 tests + asset check + pictures + audio + performance (on vs off), one report
#   tools/n9_verify.sh --quick         tests + asset check only (no window, no sound; about a minute)
#   tools/n9_verify.sh --baseline      also measure the original PR #1 build (git worktree of ab3cdac) for the performance gate
# Needs a display and a sound device for everything except --quick. Writes tests/visual/out/N9_VERIFY_REPORT.md; the last line says PASS/CHECK.
# Does not change the game, does not push, and runs with HOME pointed at /tmp/sol_n9_verify_home so it never touches your settings.cfg or saves (the asset switches are driven by SOL_ASSETS=off).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/tests/visual/out"
mkdir -p "$OUT"
REPORT="$OUT/N9_VERIFY_REPORT.md"
QUICK=0; BASELINE=0
for argument in "$@"; do
  [[ "$argument" == "--quick" ]] && QUICK=1
  [[ "$argument" == "--baseline" ]] && BASELINE=1
done

if [[ -n "${GODOT:-}" ]]; then godot_bin="$GODOT"
elif command -v godot >/dev/null 2>&1; then godot_bin="godot"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="/Applications/Godot.app/Contents/MacOS/Godot"
elif [[ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]]; then godot_bin="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
else echo "Godot not found. Set GODOT=/path/to/Godot (4.7.2)." >&2; exit 2; fi

# Godot keeps user:// (settings.cfg, saves) under $HOME/Library/Application Support/Godot/app_userdata/Sol, shared with any other build of this project. Point HOME at a scratch dir
# (after the Godot lookup above) so a verification run starts from default settings and can never read or overwrite the player's preferences.
export GODOT="$godot_bin" # tools/run_tests.sh resolves Godot from $HOME too, which is about to change
export HOME="${N9_VERIFY_HOME:-/tmp/sol_n9_verify_home}"; mkdir -p "$HOME"

OVERALL=PASS
{
  echo "# N9 verification report"
  echo
  echo "- Date: $(date '+%Y-%m-%d %H:%M')"
  echo "- Commit: $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)"
  echo "- Godot: $("$godot_bin" --version 2>/dev/null | head -1)"
  echo "- Mode: $([[ $QUICK == 1 ]] && echo quick || echo full)$([[ $BASELINE == 1 ]] && echo ' + baseline')"
  echo
} > "$REPORT"

section() { printf '\n## %s\n\n' "$1" >> "$REPORT"; }
note_fail() { OVERALL=CHECK; }

# --- 1. import + asset checker + tests (headless) --------------------------------------------------------------------------
section "1. Asset files (no Godot)"
python3 tools/asset_usage_check.py > "$OUT/asset_usage.log" 2>&1 && echo "PASS: tools/asset_usage_check.py (0 integrity problems, orphans = deferred list)" >> "$REPORT" || { echo "CHECK: tools/asset_usage_check.py failed, see tests/visual/out/asset_usage.log" >> "$REPORT"; note_fail; }
tail -3 "$OUT/asset_usage.log" | sed 's/^/    /' >> "$REPORT"

section "2. Headless tests (tools/run_tests.sh)"
tools/run_tests.sh > "$OUT/tests.log" 2>&1
tests_status=$?
if [[ $tests_status == 0 ]]; then echo "PASS: all tests" >> "$REPORT"; else echo "CHECK: tests failed (exit $tests_status)" >> "$REPORT"; note_fail; fi
grep -E "^FAIL|FAILURE|RESULT|Godot .* \| files" "$OUT/tests.log" | sed 's/^/    /' >> "$REPORT"
echo "    full log: tests/visual/out/tests.log" >> "$REPORT"

if [[ $QUICK == 1 ]]; then
  echo >> "$REPORT"; echo "Quick mode: pictures, audio and performance were NOT run." >> "$REPORT"
  echo "N9 VERIFY (quick): $OVERALL - see $REPORT"; tail -n +1 "$REPORT" | tail -20; exit 0
fi

# --- 2. pictures -------------------------------------------------------------------------------------------------------------
# name | screenshot.gd arguments after the output file.  Framing is approximate (no human has looked at these yet).
section "3. Pictures (asset on vs off)"
SHOTS=(
  "V01_cockpit|0 0 cockpit"
  "V02_cabin|40 0 inside 0 -1.8 0"
  "V03_engineering|40 0 inside 0 2.8 0"
  "V04_engineering_fire|40 0 inside 0 2.8 0 fire"
  "V05a_reactor_screen|40 0 inside -1.2 1.2 90"
  "V05b_engine_screen|40 0 inside 1.2 1.2 270"
  "V06_cargo_airlock|40 0 inside 0 7.0 180"
  "V08_chase_150m|150 20"
  "V09_ship_from_outside|40 0 outside 1 1 third"
  "V12_aurelia_ground|1.7 0"
  "V13_wreck|25 20 poi 0"
  "V14_outpost|25 20 poi 2"
  "V15_orbit_starfield|0 0"
)
compare_args=()
for shot in "${SHOTS[@]}"; do
  name="${shot%%|*}"; shot_args="${shot#*|}"
  for state in on off; do
    if [[ $state == off ]]; then export SOL_ASSETS=off; else unset SOL_ASSETS; fi
    # shellcheck disable=SC2086
    "$godot_bin" --path . -s res://tools/screenshot.gd -- "$OUT/${name}_$state.png" $shot_args > "$OUT/${name}_$state.log" 2>&1 || echo "    (screenshot run for $name/$state exited non-zero)" >> "$REPORT"
  done
  unset SOL_ASSETS
  compare_args+=("$name=$OUT/${name}_on.png,$OUT/${name}_off.png")
done
"$godot_bin" --headless --path . -s res://tools/image_compare.gd -- "${compare_args[@]}" > "$OUT/visual_metrics.log" 2>&1
grep -E "^VISUAL" "$OUT/visual_metrics.log" | sed 's/^/    /' >> "$REPORT"
grep -q "^VISUAL CHECK\|^VISUAL FAIL" "$OUT/visual_metrics.log" && note_fail
echo "    pictures are in tests/visual/out/*_on.png and *_off.png - the numbers do not replace looking at them." >> "$REPORT"

# --- 3. audio ----------------------------------------------------------------------------------------------------------------
section "4. Audio (needs a real sound device)"
unset SOL_ASSETS
"$godot_bin" --path . -s res://tools/audio_check.gd > "$OUT/audio_samples.log" 2>&1
grep -E "^AUDIO (mode|FAIL|RESULT)" "$OUT/audio_samples.log" | sed 's/^/    /' >> "$REPORT"
grep -q "AUDIO RESULT: PASSED" "$OUT/audio_samples.log" || note_fail
SOL_ASSETS=off "$godot_bin" --path . -s res://tools/audio_check.gd > "$OUT/audio_fallback.log" 2>&1
grep -E "^AUDIO (mode|FAIL|RESULT)" "$OUT/audio_fallback.log" | sed 's/^/    /' >> "$REPORT"
grep -q "AUDIO RESULT: PASSED" "$OUT/audio_fallback.log" || note_fail
echo "    per-sound lines: tests/visual/out/audio_*.log. A PASS means a player was playing on the right bus and the bus peak rose; it does not mean it sounds right." >> "$REPORT"

# --- 4. performance ----------------------------------------------------------------------------------------------------------
section "5. Performance (p95 frame time; gate: asset-on p95 <= 1.15 x reference p95)"
perf_run() { # label, env, tree, extra perf_run args
  local label="$1" env_value="$2" tree="$3" window="$4"
  ( cd "$tree" && if [[ -n "$env_value" ]]; then export SOL_ASSETS="$env_value"; fi
    "$godot_bin" --path . -s res://tools/perf_run.gd -- "$window" > "$OUT/perf_${label}_${window}.log" 2>&1 )
}
interior_run() {
  local label="$1" env_value="$2" tree="$3"
  ( cd "$tree" && if [[ -n "$env_value" ]]; then export SOL_ASSETS="$env_value"; fi
    "$godot_bin" --path . -s res://tools/interior_perf.gd -- "$OUT/interior_${label}.png" > "$OUT/perf_interior_${label}.log" 2>&1 )
}
for window in 1152x648 1920x1080; do
  perf_run on "" "$ROOT" "$window"
  perf_run off off "$ROOT" "$window"
done
interior_run on "" "$ROOT"
interior_run off off "$ROOT"
if [[ $BASELINE == 1 ]]; then
  BASE_TREE="$ROOT/../Sol-n9-baseline"
  [[ -d "$BASE_TREE" ]] || git worktree add --detach "$BASE_TREE" ab3cdac > /dev/null 2>&1
  "$godot_bin" --headless --path "$BASE_TREE" --import > /dev/null 2>&1 || true
  perf_run base "" "$BASE_TREE" 1152x648
  interior_run base "" "$BASE_TREE"
fi
python3 - "$OUT" "$BASELINE" >> "$REPORT" <<'PY'
import re, sys, glob, os
out, baseline = sys.argv[1], sys.argv[2] == "1"
def phases(path):
    result = {}
    if not os.path.exists(path):
        return result
    for line in open(path, errors="replace"):
        match = re.match(r"^(\w+): (\d+) frames\s+avg ([\d.]+) ms.*?p95 ([\d.]+) ms\s+worst ([\d.]+) ms", line)
        if match:
            result[match.group(1)] = float(match.group(4))
        match = re.match(r"^interior\+fire: (\d+) frames avg ([\d.]+) ms p95 ([\d.]+) ms worst ([\d.]+) ms\s+max draw calls (\d+)", line)
        if match:
            result["interior_fire"] = float(match.group(3))
        match = re.match(r"^max draw calls (\d+)", line)
        if match:
            result["_draw_calls"] = float(match.group(1))
        match = re.match(r"^memory: .*video RAM ([\d.]+) MB", line)
        if match:
            result["_video_mb"] = float(match.group(1))
    return result
rows = []
verdict_ok = True
def compare(title, on_path, ref_path, ref_name):
    global verdict_ok
    on, ref = phases(on_path), phases(ref_path)
    if not on or not ref:
        rows.append(f"    {title}: NOT MEASURED (missing or unparsable log: {os.path.basename(on_path)} / {os.path.basename(ref_path)})")
        verdict_ok = False
        return
    for key in sorted(k for k in on if not k.startswith("_")):
        if key not in ref:
            continue
        ratio = on[key] / ref[key] if ref[key] else 0.0
        ok = ratio <= 1.15
        verdict_ok &= ok
        rows.append(f"    {'PASS' if ok else 'CHECK'}: {title} {key}: p95 {on[key]:.2f} ms vs {ref_name} {ref[key]:.2f} ms (x{ratio:.2f})")
    for key, label in (("_draw_calls", "max draw calls"), ("_video_mb", "video RAM MB")):
        if key in on and key in ref:
            rows.append(f"    info: {title} {label}: {on[key]:.0f} vs {ref_name} {ref[key]:.0f}")
for window in ("1152x648", "1920x1080"):
    compare(f"descent {window}", f"{out}/perf_on_{window}.log", f"{out}/perf_off_{window}.log", "assets off")
compare("interior+fire 1152x648", f"{out}/perf_interior_on.log", f"{out}/perf_interior_off.log", "assets off")
if baseline:
    compare("descent 1152x648 vs PR #1 build", f"{out}/perf_on_1152x648.log", f"{out}/perf_base_1152x648.log", "PR #1")
    compare("interior+fire vs PR #1 build", f"{out}/perf_interior_on.log", f"{out}/perf_interior_base.log", "PR #1")
print("\n".join(rows))
print("    (the average frame time is pinned at 10 ms by the 100 fps cap, so only p95 is compared)")
print("PERF_VERDICT=" + ("PASS" if verdict_ok else "CHECK"))
PY
grep -q "PERF_VERDICT=CHECK" "$REPORT" && note_fail
sed -i.bak '/PERF_VERDICT=/d' "$REPORT" && rm -f "$REPORT.bak"

echo >> "$REPORT"
echo "## Verdict" >> "$REPORT"
echo >> "$REPORT"
echo "N9 VERIFY: $OVERALL" >> "$REPORT"
echo "(CHECK means something above needs a look; it does not by itself mean the game is broken. Nothing here is a human 'looks/sounds right'.)" >> "$REPORT"
cat "$REPORT"
