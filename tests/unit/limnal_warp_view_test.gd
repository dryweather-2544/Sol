extends "res://tests/test_case.gd"
## Rodina warp camera port (LimnalWarpView, CameraVibration, RodinaMath). Expected values are worked by hand from the
## Lua formulas quoted in the scripts.

const DELTA := 1.0 / 60.0


func _run(view: LimnalWarpView, ticks: int, in_warp: bool, resistance: float = 0.0) -> void:
	for tick in ticks:
		view.update(in_warp, resistance, false, DELTA)


func test_rodina_math_helpers_match_the_lua() -> void:
	assert_near(RodinaMath.analogue(0.5, 0.0, 1.0, 10.0, 20.0), 15.0, 1e-6)
	assert_near(RodinaMath.analogue(-1.0, 0.0, 1.0, 10.0, 20.0), 10.0, 1e-6, "clamped low")
	assert_near(RodinaMath.analogue(2.0, 0.0, 1.0, 10.0, 20.0), 20.0, 1e-6, "clamped high")
	assert_near(RodinaMath.approach(0.0, 0.95, 0.25), 0.0, 1e-6, "approach starts at 0")
	assert_near(RodinaMath.approach(1.8, 0.95, 0.25), 0.95 - 3.8 / 5.8, 1e-6)
	# Jarilo AtmosphereScatterColor1 = EGHueSaturateValue(20, .6, 1): high 1, low 0.4, green = 0.4 + 20/60 * 0.6 = 0.6.
	var color := RodinaMath.hue_saturate_value(20.0, 0.6, 1.0)
	assert_near(color.r, 1.0, 1e-6)
	assert_near(color.g, 0.6, 1e-6)
	assert_near(color.b, 0.4, 1e-6)
	var teal := RodinaMath.hue_saturate_value(180.0, 0.8, 1.0) # Perun FilterColor2: exactly cyan-ish (low, high, high)
	assert_near(teal.r, 0.2, 1e-6)
	assert_near(teal.g, 1.0, 1e-6)
	assert_near(teal.b, 1.0, 1e-6)


func test_at_rest_the_camera_is_unchanged() -> void:
	var view := LimnalWarpView.new()
	_run(view, 120, false)
	assert_near(view.field_of_view(75.0), 75.0, 1e-6)
	assert_near(view.follow_distance(), 200.0, 1e-6, "EGVehicle.CameraFollowDistance")
	assert_near(view.follow_angle_degrees(), 10.0, 1e-6, "EGVehicle.CameraFollowAngle")
	assert_eq(view.shake, Vector2.ZERO)


func test_entering_warp_blends_toward_the_rodina_warp_camera() -> void:
	var view := LimnalWarpView.new()
	_run(view, 108, true) # 1.8 s
	assert_near(view.limnal_timer, 1.8, 1e-4)
	assert_near(view.activation, 1.0, 1e-3, "LimnalActivation reaches 1 at LimnalStartTime")
	var warp := 0.95 - 3.8 / (1.8 + 4.0)
	assert_near(view.spacewarp, warp, 1e-4)
	assert_near(view.field_of_view(75.0), 75.0 + 30.0 * warp, 1e-3)
	assert_near(view.follow_distance(), 200.0 - 75.0 * warp, 1e-3)
	assert_near(view.follow_angle_degrees(), 10.0 + 5.0 * warp, 1e-4)
	assert_true(view.shake != Vector2.ZERO, "Limnal warp vibration is on")


func test_sustained_warp_never_reaches_the_full_blend() -> void:
	# The Lua's "warp = 1" branch tests an undefined global, so the blend only ever approaches 0.95.
	var view := LimnalWarpView.new()
	var last := 0.0
	for tick in 60 * 120:
		view.update(true, 0.0, false, DELTA)
		assert_true(view.spacewarp >= last, "never falls while in warp")
		last = view.spacewarp
	assert_near(view.spacewarp, 0.95 - 3.8 / 124.0, 1e-3, "after 120 s")
	assert_true(view.spacewarp < 0.95)
	# With a 160 degree base the warp FOV is capped: base .. min(175, 190) = 160 + 15 * warp.
	assert_near(view.field_of_view(160.0), 160.0 + 15.0 * view.spacewarp, 1e-3, "FOV capped at 175")


func test_leaving_warp_resets_the_clock_and_decays_the_blend() -> void:
	var view := LimnalWarpView.new()
	_run(view, 600, true)
	var warp := view.spacewarp
	view.update(false, 0.0, false, DELTA)
	assert_eq(view.limnal_timer, 0.0, "LimnalTimer resets when the gear leaves warp")
	assert_eq(view.activation, 0.0)
	assert_near(view.spacewarp, warp * (1.0 - 1.5 * DELTA), 1e-6, "EGInterpolate(dt * 1.5, warp, 0)")
	_run(view, 119, false)
	assert_near(view.spacewarp, warp * pow(1.0 - 1.5 * DELTA, 120), 1e-5, "2 s later")
	_run(view, 60 * 20, false)
	assert_true(view.spacewarp < 1e-6)
	assert_near(view.field_of_view(75.0), 75.0, 1e-3)


func test_short_warp_drop_out_restarts_the_activation() -> void:
	# Losing the warp gear (power, tank, forced down-shift) for one tick restarts the 1.8 s activation, as in Rodina.
	var view := LimnalWarpView.new()
	_run(view, 300, true)
	var warp := view.spacewarp
	view.update(false, 0.0, false, DELTA)
	view.update(true, 0.0, false, DELTA)
	assert_near(view.activation, DELTA / 1.8, 1e-6)
	assert_true(view.spacewarp >= warp * (1.0 - 1.5 * DELTA) - 1e-6, "the blend keeps its max() memory, it does not restart")


func test_camera_vibration_holds_while_set_and_fades_in_a_quarter_second() -> void:
	var vibration := CameraVibration.new()
	vibration.set_vibrate(&"test", Vector2(0.1, 0.1), Vector2(18, 18), 0.0, 0.25)
	vibration.update(DELTA)
	assert_near(vibration.factor_of(&"test"), 1.0 - DELTA / 0.25, 1e-6, "Analogue(timer, set, set + .25, 1, 0)")
	for tick in 14:
		vibration.update(DELTA)
	assert_near(vibration.factor_of(&"test"), 0.0, 1e-6, "faded 0.25 s after the last set")
	assert_eq(vibration.update(DELTA), Vector2.ZERO)


func test_atmosphere_shake_follows_resistance() -> void:
	var calm := LimnalWarpView.new()
	_run(calm, 60, false, 0.0)
	assert_eq(calm.shake, Vector2.ZERO, "no resistance, no shake")
	var view := LimnalWarpView.new()
	var biggest := 0.0
	for tick in 600:
		view.update(false, 0.8, false, DELTA)
		biggest = maxf(biggest, maxf(absf(view.shake.x), absf(view.shake.y)))
	# Bound: amplitude 0.075 * 0.8, times CameraShake * 3, times factor^3 (< 1), times |perlin| (<= 1).
	assert_true(biggest > 0.0 and biggest <= 0.075 * 0.8 * 3.0, "shake %f within the Rodina bound" % biggest)


func test_warp_shake_is_never_stuck_at_zero_on_the_fixed_tick() -> void:
	# Rodina's noise arguments land on whole numbers every 2nd/8th tick at 60 Hz; the shake must still move every tick.
	var view := LimnalWarpView.new()
	var zero_ticks := 0
	for tick in 600:
		view.update(true, 0.0, false, DELTA)
		if tick > 120 and (view.shake.x == 0.0 or view.shake.y == 0.0):
			zero_ticks += 1
	assert_eq(zero_ticks, 0, "ticks with an axis exactly zero")
