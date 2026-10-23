class_name CockpitOverlay
extends CanvasLayer
## Draws the fighter's cockpit with its own short-range camera, laid over the world view.
##
## Why: the canopy, dash and screens sit a few centimetres to a metre from the eye, so drawing them needs a near plane of
## about 0.05 m. With one camera that near plane caps the far plane at ~200-400 km (CameraRange, float32 projection), and the
## planet's terrain / backdrop / impostor handoffs all follow the far plane, so in the fighter cockpit (and only there) the
## planet was sliced off, popped between its three forms, or vanished at some altitudes. Now the world camera keeps the same
## near/far as the chase view (no clipping there) and this camera draws only the cockpit layer, near 0.02 m / far 60 m.

const NEAR := 0.02
const FAR := 60.0

## The world camera this overlay follows (pose, field of view). The overlay draws only while it is the current camera.
var source: Camera3D
## Set every frame by FighterCockpit (true while the cockpit is shown).
var enabled := false

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _view := TextureRect.new()


func _init(mask: int) -> void:
	name = "CockpitOverlay"
	layer = -1 # over the 3D view, under every HUD and menu (they sit on layer 0 and up)
	process_priority = 1000 # after main.gd has turned and zoomed the cockpit camera this frame
	visible = false
	_viewport.name = "CockpitView"
	_viewport.transparent_bg = true # only the cockpit's own pixels cover the world
	_viewport.own_world_3d = false # same world (sun, environment, cockpit lights) as the main view
	_viewport.audio_listener_enable_3d = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera.name = "CockpitOverlayCamera"
	_camera.cull_mask = mask
	_camera.near = NEAR
	_camera.far = FAR
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # it copies the source's interpolated pose itself
	_viewport.add_child(_camera)
	add_child(_viewport)
	_view.name = "CockpitImage"
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_view)


func _ready() -> void:
	_view.texture = _viewport.get_texture()
	_camera.current = true # current inside its own viewport only


func _process(_delta: float) -> void:
	var on := enabled and source != null and source.is_inside_tree() and source.current
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var main_view := get_viewport()
	var size := Vector2i(main_view.get_visible_rect().size)
	if _viewport.size != size:
		_viewport.size = size
	_viewport.msaa_3d = main_view.msaa_3d
	_viewport.screen_space_aa = main_view.screen_space_aa
	_viewport.scaling_3d_scale = main_view.scaling_3d_scale
	_viewport.use_debanding = main_view.use_debanding
	_camera.global_transform = source.get_global_transform_interpolated() if source.is_physics_interpolated_and_enabled() else source.global_transform
	_camera.fov = source.fov
	_camera.keep_aspect = source.keep_aspect
	_camera.h_offset = source.h_offset
	_camera.v_offset = source.v_offset
	_camera.environment = source.environment
	_camera.attributes = source.attributes
