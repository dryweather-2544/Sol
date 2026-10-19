class_name ShipHullShell
extends RefCounted
## Original, code-built exterior shell for the player ship. It is deliberately only visual:
## collision, walkable interior and flight code are unchanged. The shell encloses the existing
## 18 m interior, keeps the cockpit glass at the nose, and adds the silhouette/detail the old
## box hull lacked. All geometry is authored here; no third-party model is used.

const SECTIONS := [
	{"z": -6.80, "w": 2.02, "top": 1.45, "bottom": -0.82},
	{"z": -5.20, "w": 2.72, "top": 1.95, "bottom": -1.00},
	{"z": -2.00, "w": 3.18, "top": 2.42, "bottom": -1.22},
	{"z":  2.20, "w": 3.20, "top": 2.52, "bottom": -1.24},
	{"z":  6.10, "w": 3.04, "top": 2.30, "bottom": -1.12},
	{"z":  9.55, "w": 2.78, "top": 1.92, "bottom": -0.96},
	{"z": 10.90, "w": 2.18, "top": 1.35, "bottom": -0.78},
]


static func build(parent: Node3D, hull: Material, dark: Material, accent: Material, glass: Material, nozzle: Material, metal: Material, glow: Material) -> void:
	var shell := MeshInstance3D.new()
	shell.name = "HullShell"
	shell.mesh = _loft_mesh()
	shell.material_override = hull
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(shell)
	_build_wings(parent, hull, dark, accent, metal)
	_build_engines(parent, dark, nozzle, metal, accent, glow)
	_build_panel_details(parent, dark, metal, accent, glass)
	_build_cockpit(parent, dark, glass, accent, metal)
	_build_gear(parent, metal, dark)


static func _ring_points(section: Dictionary) -> Array[Vector3]:
	var w: float = section["w"]
	var top: float = section["top"]
	var bottom: float = section["bottom"]
	# Nine-point section with a raised centre ridge: the old flat top plane read as a white
	# rectangle from the chase camera. The ridge gives two lit facets and a strong highlight.
	return [
		Vector3(0.0, top + 0.16, section["z"]),
		Vector3( w * 0.52, top + 0.02, section["z"]),
		Vector3( w, top * 0.52, section["z"]),
		Vector3( w, bottom * 0.42, section["z"]),
		Vector3( w * 0.56, bottom, section["z"]),
		Vector3(-w * 0.56, bottom, section["z"]),
		Vector3(-w, bottom * 0.42, section["z"]),
		Vector3(-w, top * 0.52, section["z"]),
		Vector3(-w * 0.52, top + 0.02, section["z"]),
	]


static func _loft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for section in SECTIONS:
		rings.append(_ring_points(section))
	for i in range(rings.size() - 1):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for edge in a.size():
			var next := (edge + 1) % a.size()
			_quad(st, a[edge], b[edge], b[next], a[next])
	# Rear cap: triangle fan around the last ring, facing +z.
	var rear: Array = rings[rings.size() - 1]
	var rear_z: float = SECTIONS[SECTIONS.size() - 1]["z"]
	var rear_center := Vector3(0, (SECTIONS[SECTIONS.size() - 1]["top"] + SECTIONS[SECTIONS.size() - 1]["bottom"]) * 0.5, rear_z)
	for edge in rear.size():
		var next := (edge + 1) % rear.size()
		_tri(st, rear_center, rear[edge], rear[next], Vector3(0, 0, 1))
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var center := (a + b + c + d) * 0.25
	if n.dot(center - Vector3(0, center.y * 0.2, center.z)) < 0.0:
		n = -n
		var swap := b
		b = d
		d = swap
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2((p.x + 4.0) / 8.0, (p.z + 8.0) / 20.0))
		st.add_vertex(p)


static func _build_wings(parent: Node3D, hull: Material, dark: Material, accent: Material, metal: Material) -> void:
	for side in [-1.0, 1.0]:
		var root_le := Vector3(side * 3.02, 0.18, -1.60)
		var root_te := Vector3(side * 3.02, 0.08, 8.65)
		var tip_le := Vector3(side * 7.75, 0.58, 2.75)
		var tip_te := Vector3(side * 7.75, 0.46, 7.10)
		var top := 0.30
		var bottom := 0.02
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Top and bottom faces.
		var top_pts := [root_le + Vector3(0, top, 0), root_te + Vector3(0, top, 0), tip_te + Vector3(0, top + 0.28, 0), tip_le + Vector3(0, top + 0.28, 0)]
		var bot_pts := [root_le + Vector3(0, bottom, 0), tip_le + Vector3(0, bottom + 0.28, 0), tip_te + Vector3(0, bottom + 0.28, 0), root_te + Vector3(0, bottom, 0)]
		_quad(st, top_pts[0], top_pts[1], top_pts[2], top_pts[3])
		_quad(st, bot_pts[0], bot_pts[1], bot_pts[2], bot_pts[3])
		# A separate lighter top skin gives the delta a readable upper surface.
		var st_top := SurfaceTool.new()
		st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st_top, top_pts[0] + Vector3(0, 0.012, 0), top_pts[1] + Vector3(0, 0.012, 0), top_pts[2] + Vector3(0, 0.012, 0), top_pts[3] + Vector3(0, 0.012, 0))
		var top_node := MeshInstance3D.new()
		top_node.mesh = st_top.commit()
		top_node.material_override = metal
		parent.add_child(top_node)
		# Leading/trailing edge and tip.
		_quad(st, top_pts[0], top_pts[3], bot_pts[1], bot_pts[0])
		_quad(st, top_pts[1], bot_pts[3], bot_pts[2], top_pts[2])
		_quad(st, top_pts[3], top_pts[2], bot_pts[2], bot_pts[1])
		var wing := MeshInstance3D.new()
		wing.name = "Wing" + ("L" if side < 0.0 else "R")
		wing.mesh = st.commit()
		wing.material_override = hull
		parent.add_child(wing)
		# Broad delta wing: root fairing, trailing-edge control surfaces, wingtip nav light.
		_add_box(parent, Vector3(side * 3.15, 0.20, 3.5), Vector3(0.42, 0.18, 6.2), dark, Vector3.ZERO)
		for z in [1.0, 3.0, 5.0, 7.0]:
			_add_box(parent, Vector3(side * 5.35, 0.40, z), Vector3(4.6, 0.018, 0.035), dark, Vector3(0, 0, side * -7.0))
		_add_box(parent, Vector3(side * 6.1, 0.28, 7.45), Vector3(2.0, 0.035, 0.32), metal, Vector3(0, 0, side * -7.0))
		_add_box(parent, Vector3(side * 7.74, 0.56, 4.9), Vector3(0.18, 0.24, 4.0), accent, Vector3.ZERO)
		_add_box(parent, Vector3(side * 7.62, 0.60, 2.80), Vector3(0.22, 0.16, 0.22), _emissive(Color(1.0, 0.12, 0.08) if side < 0.0 else Color(0.1, 1.0, 0.25), 2.4), Vector3.ZERO)


static func _build_engines(parent: Node3D, dark: Material, nozzle: Material, metal: Material, accent: Material, glow: Material) -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 2.50
		# Box cowls read as engine pods, not submarine portholes. A dark core, a lighter upper
		# cowl, an intake lip and a recessed nozzle give the rear a layered silhouette.
		_add_box(parent, Vector3(x, -0.10, 8.55), Vector3(1.24, 1.18, 3.05), dark, Vector3.ZERO)
		_add_box(parent, Vector3(x, 0.44, 8.55), Vector3(1.02, 0.16, 2.85), metal, Vector3.ZERO)
		_add_box(parent, Vector3(x, -0.67, 8.55), Vector3(1.02, 0.12, 2.85), metal, Vector3.ZERO)
		_add_box(parent, Vector3(x, -0.10, 7.03), Vector3(1.34, 1.30, 0.18), metal, Vector3.ZERO)
		_add_box(parent, Vector3(x, -0.10, 7.12), Vector3(0.92, 0.88, 0.10), dark, Vector3.ZERO)
		_add_cylinder(parent, Vector3(x, -0.10, 10.22), 0.48, 0.40, 0.22, metal, Vector3(90, 0, 0))
		_add_cylinder(parent, Vector3(x, -0.10, 10.36), 0.36, 0.30, 0.08, dark, Vector3(90, 0, 0))
		var core := _add_cylinder(parent, Vector3(x, -0.10, 10.42), 0.20, 0.17, 0.035, nozzle, Vector3(90, 0, 0))
		core.add_child(_exhaust_disc(glow))
		for z in [7.9, 9.2]:
			_add_box(parent, Vector3(x, 0.12, z), Vector3(1.30, 0.06, 0.10), accent, Vector3.ZERO)
	# Central tail engine block and fin root.
	_add_box(parent, Vector3(0, -0.34, 9.75), Vector3(1.10, 0.94, 2.35), dark, Vector3.ZERO)
	for offset in [-0.28, 0.0, 0.28]:
		_add_cylinder(parent, Vector3(offset, -0.34, 10.88), 0.14, 0.12, 0.12, metal, Vector3(90, 0, 0))
	_add_box(parent, Vector3(0, 0.90, 9.55), Vector3(0.34, 1.6, 2.0), dark, Vector3(-12, 0, 0))
	_add_box(parent, Vector3(0, 1.55, 8.72), Vector3(0.12, 0.55, 1.2), accent, Vector3.ZERO)
	# Swept tail fins and a taller centre stabiliser: the old rear view was a flat wedge.
	for side in [-1.0, 1.0]:
		_fin(parent, side, dark, accent)
		_add_box(parent, Vector3(side * 7.52, 1.08, 5.35), Vector3(0.10, 0.85, 1.10), dark, Vector3(0, 0, side * -15.0))
		_add_box(parent, Vector3(side * 7.55, 1.54, 5.35), Vector3(0.08, 0.10, 0.42), _emissive(Color(1.0, 0.16, 0.10) if side < 0.0 else Color(0.15, 1.0, 0.30), 2.2), Vector3.ZERO)
	_add_box(parent, Vector3(0, 1.75, 10.05), Vector3(0.10, 1.05, 0.55), accent, Vector3.ZERO)
	# Dorsal vents / heat exchanger just behind the cockpit.
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.28, 1.98, -2.75), Vector3(0.78, 0.05, 1.05), metal, Vector3.ZERO)
		for slot in 4:
			_add_box(parent, Vector3(side * 1.28, 2.01, -3.18 + slot * 0.25), Vector3(0.62, 0.02, 0.06), dark, Vector3.ZERO)


static func _build_panel_details(parent: Node3D, dark: Material, metal: Material, accent: Material, glass: Material) -> void:
	# Panel seams across the dorsal hull.
	for z in [-4.4, -1.0, 2.4, 5.8, 8.1]:
		_add_box(parent, Vector3(0, 1.985, z), Vector3(5.4, 0.025, 0.035), dark, Vector3.ZERO)
	# Side seams and access hatches.
	for side in [-1.0, 1.0]:
		for z in [-2.6, 1.1, 4.8, 7.6]:
			_add_box(parent, Vector3(side * 3.20, 0.45, z), Vector3(0.025, 0.72, 0.035), dark, Vector3.ZERO)
		for z in [0.2, 5.2]:
			_add_box(parent, Vector3(side * 3.235, 0.22, z), Vector3(0.025, 0.42, 0.78), metal, Vector3.ZERO)
			_add_box(parent, Vector3(side * 3.255, 0.22, z), Vector3(0.012, 0.30, 0.62), dark, Vector3.ZERO)
	# Dorsal spine, RCS pods and antenna.
	_add_box(parent, Vector3(0, 2.62, 3.8), Vector3(0.62, 0.32, 5.6), dark, Vector3.ZERO)
	# Light paint access plates on the dark hull top: readable panel rhythm and a value break.
	for z in [0.2, 2.8, 5.4]:
		for side in [-1.0, 1.0]:
			_add_box(parent, Vector3(side * 1.05, 2.60, z), Vector3(1.35, 0.035, 1.55), metal, Vector3.ZERO)
			_add_box(parent, Vector3(side * 1.05, 2.625, z), Vector3(1.15, 0.015, 1.30), dark, Vector3.ZERO)
			_add_box(parent, Vector3(side * 1.75, 2.60, z), Vector3(0.045, 0.025, 1.35), accent, Vector3.ZERO)
	_add_box(parent, Vector3(0, 2.72, 6.7), Vector3(0.28, 0.18, 1.2), metal, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		for z in [1.3, 5.6]:
			_add_box(parent, Vector3(side * 3.12, 0.92, z), Vector3(0.30, 0.24, 0.62), dark, Vector3.ZERO)
			_add_box(parent, Vector3(side * 3.30, 0.92, z), Vector3(0.10, 0.15, 0.34), metal, Vector3.ZERO)
	_add_cylinder(parent, Vector3(0.30, 2.55, 7.9), 0.035, 0.02, 1.2, metal, Vector3.ZERO)
	_add_cylinder(parent, Vector3(-0.52, 2.42, 7.3), 0.26, 0.26, 0.10, metal, Vector3(0, 0, 20))
	_add_box(parent, Vector3(0, -1.26, 3.2), Vector3(2.7, 0.10, 6.4), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, -1.31, -1.8), Vector3(1.7, 0.08, 2.0), accent, Vector3.ZERO)
	# Rear access door and engine deck: the chase camera looks at this face most of the time.
	_add_box(parent, Vector3(0, 0.02, 10.96), Vector3(2.15, 1.28, 0.08), dark, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.12, 0.02, 11.00), Vector3(0.10, 1.42, 0.12), metal, Vector3.ZERO)
	_add_box(parent, Vector3(0, 0.72, 11.00), Vector3(2.34, 0.10, 0.13), metal, Vector3.ZERO)
	_add_box(parent, Vector3(0, -0.68, 11.00), Vector3(2.34, 0.10, 0.13), metal, Vector3.ZERO)
	_add_box(parent, Vector3(0, 0.28, 11.02), Vector3(0.58, 0.28, 0.03), glass, Vector3.ZERO)
	for stripe in 5:
		_add_box(parent, Vector3(-0.80 + stripe * 0.40, -0.52, 11.02), Vector3(0.22, 0.10, 0.03), accent if stripe % 2 == 0 else metal, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 0.66, 1.02, 10.98), Vector3(0.62, 0.30, 0.20), dark, Vector3.ZERO)
		_add_box(parent, Vector3(side * 0.66, 1.02, 11.10), Vector3(0.40, 0.16, 0.04), _emissive(Color(0.18, 0.62, 1.0), 1.4), Vector3.ZERO)
	# Side chines, forward intakes, wing pylons and a raised canopy fairing give the silhouette
	# readable edges from the chase camera instead of a flat wedge.
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 2.83, 0.25, 2.4), Vector3(0.20, 0.42, 7.4), dark, Vector3(0, 0, side * -18.0))
		_add_box(parent, Vector3(side * 2.76, 0.64, -3.5), Vector3(0.46, 0.36, 1.35), dark, Vector3.ZERO)
		for slot in 3:
			_add_box(parent, Vector3(side * 2.99, 0.64, -4.05 + slot * 0.34), Vector3(0.03, 0.25, 0.14), metal, Vector3.ZERO)
		_add_box(parent, Vector3(side * 2.18, 0.02, 8.0), Vector3(1.45, 0.18, 2.0), metal, Vector3.ZERO)
		_add_box(parent, Vector3(side * 5.2, -0.06, 3.4), Vector3(0.55, 0.16, 1.5), dark, Vector3.ZERO)
		_add_box(parent, Vector3(side * 5.2, -0.20, 3.4), Vector3(0.28, 0.10, 0.9), accent, Vector3.ZERO)
	# Raised cockpit fairing: a dark frame with a glazed top, visible from outside.
	_add_box(parent, Vector3(0, 2.02, -5.0), Vector3(2.35, 0.10, 2.25), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, 2.11, -5.0), Vector3(2.02, 0.035, 1.86), glass, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.16, 2.09, -5.0), Vector3(0.08, 0.08, 2.10), dark, Vector3(0, 0, side * -8.0))
	_add_box(parent, Vector3(0, 2.09, -6.02), Vector3(2.20, 0.08, 0.10), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, 2.09, -3.96), Vector3(2.20, 0.08, 0.10), dark, Vector3.ZERO)


static func _build_cockpit(parent: Node3D, dark: Material, glass: Material, accent: Material, metal: Material) -> void:
	# Glass and a real frame at the nose. The shell stops at z=-6.8 so the glass is the forward face.
	var glass_panel := _add_box(parent, Vector3(0, 0.48, -7.02), Vector3(3.55, 1.55, 0.045), glass, Vector3(-6, 0, 0))
	glass_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.84, 0.42, -6.99), Vector3(0.14, 1.62, 0.16), dark, Vector3(-6, 0, 0))
		_add_box(parent, Vector3(side * 1.76, -0.38, -6.92), Vector3(0.18, 0.30, 0.55), metal, Vector3.ZERO)
	_add_box(parent, Vector3(0, 1.24, -6.98), Vector3(3.75, 0.14, 0.20), dark, Vector3(-6, 0, 0))
	_add_box(parent, Vector3(0, -0.33, -6.97), Vector3(3.75, 0.18, 0.26), dark, Vector3(-6, 0, 0))
	# Interior dashboard and side consoles, placed below the eye line so the view stays open.
	_add_box(parent, Vector3(0, -0.30, -6.60), Vector3(2.65, 0.34, 0.46), dark, Vector3.ZERO)
	for x in [-0.82, 0.0, 0.82]:
		_add_box(parent, Vector3(x, -0.18, -6.84), Vector3(0.58, 0.16, 0.035), _emissive(Color(0.16, 0.62, 0.92), 1.4), Vector3(-6, 0, 0))
	_add_box(parent, Vector3(0, 1.18, -6.55), Vector3(2.5, 0.18, 0.34), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, 1.12, -6.73), Vector3(1.9, 0.035, 0.09), _emissive(Color(0.9, 0.45, 0.16), 1.2), Vector3.ZERO)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.48, -0.34, -6.35), Vector3(0.30, 0.24, 0.80), dark, Vector3.ZERO)
		_add_box(parent, Vector3(side * 1.48, -0.19, -6.35), Vector3(0.18, 0.03, 0.55), _emissive(Color(0.2, 0.75, 0.95), 1.1), Vector3.ZERO)
	# Glazed canopy fairing: a low bubble above the cockpit, framed by dark arcs. It is visual
	# only and sits outside the player camera's near plane.
	_add_sphere(parent, Vector3(0, 2.42, -5.05), Vector3(1.28, 0.46, 1.62), glass)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.22, 2.44, -5.05), Vector3(0.055, 0.075, 1.72), dark, Vector3(0, 0, side * -7.0))
	_add_box(parent, Vector3(0, 2.47, -6.60), Vector3(1.62, 0.06, 0.08), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, 2.47, -3.52), Vector3(1.62, 0.06, 0.08), dark, Vector3.ZERO)
	# A small nose sensor under the glass, a dark chin/brow to give the nose a profile, and
	# narrow side windows so the cockpit reads from a three-quarter view.
	_add_cylinder(parent, Vector3(0, -0.55, -7.02), 0.12, 0.10, 0.20, metal, Vector3(90, 0, 0))
	_add_box(parent, Vector3(0, -0.63, -7.45), Vector3(1.55, 0.30, 0.75), dark, Vector3(8, 0, 0))
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(side * 1.90, 0.42, -6.55), Vector3(0.035, 0.50, 0.95), glass, Vector3(0, side * 18.0, 0))
		_add_box(parent, Vector3(side * 1.94, 0.42, -6.55), Vector3(0.05, 0.58, 0.12), dark, Vector3(0, side * 18.0, 0))


static func _build_gear(parent: Node3D, metal: Material, dark: Material) -> void:
	for side in [-1.0, 1.0]:
		for z in [-4.8, 7.8]:
			_add_cylinder(parent, Vector3(side * 2.55, -1.28, z), 0.09, 0.09, 0.78, metal, Vector3.ZERO)
			_add_box(parent, Vector3(side * 2.55, -1.68, z), Vector3(0.52, 0.12, 0.62), dark, Vector3.ZERO)
	_add_box(parent, Vector3(0, -1.63, 1.1), Vector3(0.42, 0.10, 0.55), dark, Vector3.ZERO)
	_add_cylinder(parent, Vector3(0, -1.27, 1.1), 0.07, 0.07, 0.72, metal, Vector3.ZERO)


static func _fin(parent: Node3D, side: float, dark: Material, accent: Material) -> void:
	var x: float = side * 1.62
	var thickness := 0.07
	var left := [
		Vector3(x - thickness, 1.22, 8.55),
		Vector3(x - thickness, 1.22, 10.15),
		Vector3(x - thickness, 3.25, 9.55),
	]
	var right := [
		Vector3(x + thickness, 1.22, 8.55),
		Vector3(x + thickness, 1.22, 10.15),
		Vector3(x + thickness, 3.25, 9.55),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, left[0], left[1], left[2], Vector3.LEFT)
	_tri(st, right[0], right[2], right[1], Vector3.RIGHT)
	for edge in [[0, 1], [1, 2], [2, 0]]:
		_quad(st, left[edge[0]], right[edge[0]], right[edge[1]], left[edge[1]])
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = dark
	parent.add_child(node)
	_add_box(parent, Vector3(x, 3.20, 9.55), Vector3(0.16, 0.12, 0.55), accent, Vector3.ZERO)


static func _add_box(parent: Node3D, position: Vector3, size: Vector3, material: Material, rotation_degrees_value: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.rotation_degrees = rotation_degrees_value
	parent.add_child(node)
	return node


static func _add_sphere(parent: Node3D, position: Vector3, scale_value: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.scale = scale_value
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _add_cylinder(parent: Node3D, position: Vector3, top_radius: float, bottom_radius: float, height: float, material: Material, rotation_degrees_value: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 16
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.rotation_degrees = rotation_degrees_value
	parent.add_child(node)
	return node


static func _exhaust_disc(material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 0.025
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	disc.material_override = material
	disc.position = Vector3(0, 0.028, 0)
	return disc


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
