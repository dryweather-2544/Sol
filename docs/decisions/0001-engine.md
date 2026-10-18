# 0001 — Engine and project conventions

**Engine:** Godot 4.7.2, verified on the Mac mini M4: `Godot --version` prints `4.7.2.stable.official.ed1daf0bf`
(binary at `~/Downloads/Godot.app/Contents/MacOS/Godot`). Renderer Forward+ on Metal (Apple M4), Jolt selected
in project settings (no physics shapes are used for walking or terrain, see ADR 0002/0003).

**Autoloads:** none. ARCHITECTURE §2.4 listed `Sol`, `Events`, `SaveService`, `Settings`; in practice
`GameSettings.instance()` (static shared instance), `SaveManager`/`SaveGame` (plain classes) and `GameSession`
(owned by `scenes/main.gd`) cover them without global nodes, which keeps every system constructible in headless tests.

**Tests:** always through `tools/run_tests.sh` (imports first so new `class_name` scripts are registered).
