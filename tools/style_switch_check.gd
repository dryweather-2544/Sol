extends SceneTree
## Runtime visual-style switching in the real main scene (headless is fine):
##   godot --headless --path . -s res://tools/style_switch_check.gd
## Flies nothing: lets the scene start, then switches sol -> rodina -> sol at runtime and checks that the ship's state,
## the terrain height under it and the gameplay mode are unchanged and that the terrain was rebuilt. Prints PASS/FAIL.

var _main: Node
var _frames := 0
var _before := {}
var _failures: Array[String] = []


func _initialize() -> void:
	VisualStyle.set_active(VisualStyle.SOL)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 30:
		# Snapshot, switch and restyle within one frame, so no physics step runs in between: any change is the switch's.
		_before = _snapshot()
		VisualStyle.set_active(VisualStyle.RODINA)
		_main._restyle()
		_compare("after switching to rodina")
		_expect(_main.planet.look != null and _main.planet.look.family == &"ochre_steppe", "home planet uses the ochre steppe look")
		_expect(_main.terrain != _before["terrain"], "terrain was rebuilt for the new colours")
	if _frames == 60:
		_before = _snapshot()
		VisualStyle.set_active(VisualStyle.SOL)
		_main._restyle()
		_compare("after switching back to sol")
		_expect(_main.planet.look == null, "sol leaves the planet on the original colour rule")
	if _frames == 90:
		_expect(_main.terrain.displayed_chunk_count() > 0, "terrain chunks are shown again after the switches")
		print("STYLE SWITCH CHECK: ", "PASS" if _failures.is_empty() else "FAIL\n  " + "\n  ".join(_failures))
		quit(0 if _failures.is_empty() else 1)
	return false


func _snapshot() -> Dictionary:
	var ship: Ship = _main.ship
	var up := Vector3(ship.state.position.x, ship.state.position.y, ship.state.position.z).normalized()
	return {"position": ship.state.position.duplicate_position(), "basis": ship.state.basis, "velocity": ship.state.velocity,
		"landed": ship.state.landed, "mode": _main.session.mode, "terrain": _main.terrain, "frame": _main.runtime.active_frame,
		"height": _main.planet.terrain_height_xyz(up.x, up.y, up.z), "up": up}


func _compare(when: String) -> void:
	var ship: Ship = _main.ship
	_expect(ship.state.position.distance_to(_before["position"]) < 1e-6, "%s: ship position unchanged" % when)
	_expect(ship.state.basis.is_equal_approx(_before["basis"]), "%s: ship orientation unchanged" % when)
	_expect(ship.state.velocity == _before["velocity"], "%s: ship velocity unchanged" % when)
	_expect(ship.state.landed == _before["landed"], "%s: landed state unchanged" % when)
	_expect(_main.session.mode == _before["mode"], "%s: gameplay mode unchanged" % when)
	_expect(_main.runtime.active_frame == _before["frame"], "%s: same world" % when)
	var up: Vector3 = _before["up"]
	_expect(_main.planet.terrain_height_xyz(up.x, up.y, up.z) == _before["height"], "%s: terrain height under the ship unchanged" % when)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
