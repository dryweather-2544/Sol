extends SceneTree
## Command-line wrapper for tools/n14_stream_probe.gd:
##   godot --headless --path . -s res://tools/n14_stream_probe_cli.gd -- <scenario|all> [planet_id] [out.json]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var probe: Node = load("res://tools/n14_stream_probe.gd").new()
	probe.which = args[0] if args.size() > 0 else "cruise20"
	probe.planet_id = StringName(args[1]) if args.size() > 1 else &"planet"
	probe.out_path = args[2] if args.size() > 2 else ""
	root.add_child(probe)
