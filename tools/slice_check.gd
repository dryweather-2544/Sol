extends SceneTree
## Real-scene check of the Mayday ambush (needs a display): boots main.tscn, jumps the ship to 3 km above Selene with the
## mission at its first step, and verifies the raider spawns, the beacon is pinned and the ship takes the guaranteed hit.
##   godot --path . -s res://tools/slice_check.gd -- out.png
var _main: Node
var _frames := 0
var _jumped_at := -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 30:
		var session: GameSession = _main.session
		session.progress.current = 3
		session.progress.warp_installed = true
		var moon: PlanetBody = _main.runtime.planet_for(&"selene")
		var state := session.ship.state
		state.position = WorldPos.new(&"selene", 0.0, 0.0, moon.radius + 3000.0)
		state.velocity = Vector3.ZERO
		state.basis = Basis.looking_at(Vector3.RIGHT, Vector3(0, 0, 1))
		_main.runtime.force_frame(&"selene")
		_main.runtime.recentre_ship_after_restore()
		_main._on_frame_changed(&"planet", &"selene")
		_jumped_at = _frames
	if _jumped_at > 0 and _frames == _jumped_at + 600:
		var session: GameSession = _main.session
		var director: EnemyDirector = _main.enemy_director
		var pinned: bool = _main.poi_manager != null and _main.poi_manager.planner.pinned.has(ProgressTracker.BEACON_ID)
		print("ambush_started ", session.progress.ambush_started, "  encounters ", director.active_encounter_count() if director != null else -1,
			"  beacon pinned ", pinned, "  engines ", session.systems.subsystems.value(ShipSubsystems.Id.ENGINES), "  cap ", session.systems.subsystems.cap[0],
			"  enemy targets ", session.enemy_targets.size(), "  hull ", session.ship.state.hull, "  fire ", session.systems.hazards.any_fire(), "  alert '", session.alert_text(), "'")
		var path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "slice.png"
		root.get_viewport().get_texture().get_image().save_png(path)
		quit()
	return false
