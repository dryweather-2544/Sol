class_name CombatTargets
extends RefCounted
## Adapters that let the player on foot and ground enemies be hit by projectiles.


class OnFootTarget extends ProjectileSim.Target:
	var session: GameSession

	func _init(game_session: GameSession) -> void:
		session = game_session

	func combat_position() -> WorldPos:
		return session.exterior_body.position.offset_by(Vector3(session.exterior_body.position.x, session.exterior_body.position.y, session.exterior_body.position.z).normalized() * 1.0)

	func combat_radius() -> float:
		return 0.9

	func team_id() -> int:
		return 0

	func apply_damage(amount: float, _source: Object) -> void:
		if session.suit.health > 0.0:
			session.suit.health = maxf(0.0, session.suit.health - amount)
			if session.suit.health <= 0.0:
				session.suit.died.emit()

	func is_alive() -> bool:
		return session.mode == GameSession.Mode.OUTSIDE and session.suit.health > 0.0


class GroundEnemyTarget extends ProjectileSim.Target:
	var enemy: GroundEnemy

	func _init(ground_enemy: GroundEnemy) -> void:
		enemy = ground_enemy

	func combat_position() -> WorldPos:
		var position := enemy.body.position
		return position.offset_by(Vector3(position.x, position.y, position.z).normalized() * 1.0)

	func combat_radius() -> float:
		return 1.1

	func team_id() -> int:
		return enemy.team

	func apply_damage(amount: float, _source: Object) -> void:
		enemy.health = maxf(0.0, enemy.health - amount)

	func is_alive() -> bool:
		return enemy.is_alive()
