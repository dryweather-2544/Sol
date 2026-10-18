extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


class DummyTarget extends ProjectileSim.Target:
	var at: WorldPos
	var team := 1
	var health := 1.0

	func _init(position: WorldPos, team_value: int) -> void:
		at = position
		team = team_value

	func combat_position() -> WorldPos:
		return at

	func combat_radius() -> float:
		return 5.0

	func team_id() -> int:
		return team

	func apply_damage(amount: float, _source: Object) -> void:
		health -= amount

	func is_alive() -> bool:
		return health > 0.0


func test_projectile_hits_enemy_team_only() -> void:
	var sim := ProjectileSim.new()
	var enemy := DummyTarget.new(WorldPos.new(&"space", 0, 0, -100), 1)
	var friend := DummyTarget.new(WorldPos.new(&"space", 0, 0, -50), 0)
	sim.spawn(WorldPos.new(&"space"), Vector3(0, 0, -300), 0, 0.25)
	var total_hits := 0
	for tick in 60:
		total_hits += sim.step(DELTA, [friend, enemy])
	assert_eq(total_hits, 1)
	assert_near(enemy.health, 0.75, 1e-9)
	assert_near(friend.health, 1.0, 1e-9, "same team is never hurt, even when in the way")
	assert_eq(sim.projectiles.size(), 0, "a projectile is spent on its hit")


func test_fast_projectile_does_not_tunnel_through_a_small_target() -> void:
	var sim := ProjectileSim.new()
	var target := DummyTarget.new(WorldPos.new(&"space", 0, 0, -1000), 1)
	sim.spawn(WorldPos.new(&"space"), Vector3(0, 0, -60000), 0, 0.5) # 1000 m per tick
	assert_eq(sim.step(DELTA, [target]), 1, "swept hit test catches a shot that jumps past the target in one tick")


func test_misses_expire_and_dead_targets_are_ignored() -> void:
	var sim := ProjectileSim.new()
	var target := DummyTarget.new(WorldPos.new(&"space", 500, 0, -100), 1)
	sim.spawn(WorldPos.new(&"space"), Vector3(0, 0, -100), 0, 0.5, null, 1.0)
	for tick in 90:
		sim.step(DELTA, [target])
	assert_eq(sim.projectiles.size(), 0, "expired after its lifetime")
	assert_near(target.health, 1.0, 1e-9)
	target.health = 0.0
	sim.spawn(WorldPos.new(&"space", 500, 0, 0), Vector3(0, 0, -100), 0, 0.5)
	assert_eq(sim.step(DELTA, [target]), 0, "dead targets cannot be hit again")


func test_weapon_respects_fire_rate_and_inherits_shooter_velocity() -> void:
	var sim := ProjectileSim.new()
	var weapon := Weapon.pistol()
	assert_true(weapon.try_fire(sim, WorldPos.new(&"space"), Vector3(0, 0, -1), Vector3(5, 0, 0), 0, null))
	assert_true(not weapon.try_fire(sim, WorldPos.new(&"space"), Vector3(0, 0, -1), Vector3.ZERO, 0, null), "cooling down")
	weapon.update(1.0 / weapon.shots_per_second + 0.001)
	assert_true(weapon.try_fire(sim, WorldPos.new(&"space"), Vector3(0, 0, -1), Vector3.ZERO, 0, null))
	assert_eq(sim.projectiles[0].velocity, Vector3(5, 0, -weapon.projectile_speed))


func test_face_direction_turns_the_ship_onto_the_target_and_settles() -> void:
	var ship := Ship.new()
	var command := PilotCommand.new()
	command.face_direction = Vector3(1, 0.3, -0.2).normalized()
	var commands: Array[PilotCommand] = []
	for tick in 600:
		commands.append(command)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	for tick in 600:
		ship.simulate_tick(DELTA)
	var forward := -ship.state.basis.z
	assert_true(forward.dot(command.face_direction) > 0.9995, "pointing within 2 degrees: %f" % forward.dot(command.face_direction))
	assert_true(ship.state.angular_velocity.length() < 0.05, "and settled rather than spinning")
	ship.free()


func test_face_direction_also_works_for_a_target_directly_behind() -> void:
	var ship := Ship.new()
	var command := PilotCommand.new()
	command.face_direction = Vector3(0, 0, 1)
	var commands: Array[PilotCommand] = []
	for tick in 900:
		commands.append(command)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	for tick in 900:
		ship.simulate_tick(DELTA)
	assert_true((-ship.state.basis.z).dot(Vector3(0, 0, 1)) > 0.99, "turned all the way round")
	ship.free()


func test_ai_attacker_flies_to_range_and_destroys_a_target_that_cannot_shoot_back() -> void:
	var sim := ProjectileSim.new()
	var victim := Ship.new()
	victim.state.position = WorldPos.new(&"space", 0.0, 0.0, -2500.0)
	victim.team_id = 0
	var attacker := Ship.new()
	attacker.projectiles = sim
	attacker.team_id = 1
	var ai := AIPilotSource.new(AIPilotSource.Mode.ATTACK)
	ai.target_provider = func(): return victim.state.position
	ai.target_velocity_provider = func(): return victim.state.velocity
	attacker.controller.request_control(ai, &"ai_seat")
	var victim_combatant := ShipCombatant.new(victim, 0)
	var destroyed := [false]
	victim.destroyed.connect(func(): destroyed[0] = true)
	var closest := INF
	for tick in 60 * 90:
		attacker.simulate_tick(DELTA)
		victim.simulate_tick(DELTA)
		sim.step(DELTA, [victim_combatant])
		closest = minf(closest, attacker.state.position.distance_to(victim.state.position))
		if destroyed[0]:
			break
	assert_true(destroyed[0], "target destroyed (hull %f, distance %f)" % [victim.state.hull, attacker.state.position.distance_to(victim.state.position)])
	assert_true(closest > 100.0, "the AI kept its distance: %f" % closest)
	attacker.free()
	victim.free()
