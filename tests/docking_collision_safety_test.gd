extends SceneTree

const COMBAT_SCRIPT := preload("res://scripts/combat_simulation.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var combat := COMBAT_SCRIPT.new() as CombatSimulation
	var player_body := RigidBody2D.new()
	var station_body := RigidBody2D.new()
	root.add_child(player_body)
	root.add_child(station_body)
	player_body.global_position = Vector2(40.0, 0.0)
	station_body.global_position = Vector2.ZERO
	player_body.add_collision_exception_with(station_body)
	station_body.add_collision_exception_with(player_body)
	var contact := {
		"id": 77,
		"physics_body": station_body,
		"docking_clearance": true,
		"docking_player_body": player_body,
		"defense_alert": false,
		"player_targetable": false,
	}
	var contacts: Array[Dictionary] = [contact]
	combat.set("enemies", contacts)

	combat.call("complete_undocking", 77, player_body)
	var pending: Dictionary = combat.get("pending_docking_releases")
	if not pending.has(77):
		failures.append("undocking removed collision protection while hull bounds still overlapped")
	if not player_body.get_collision_exceptions().has(station_body):
		failures.append("player/station collision exception was removed inside the berth")
	if not bool((combat.get("enemies") as Array)[0].get("docking_clearance", false)):
		failures.append("docking-pair damage immunity ended before physical separation")

	player_body.global_position = Vector2(100.0, 0.0)
	combat.call("_update_pending_docking_releases")
	pending = combat.get("pending_docking_releases")
	if pending.has(77):
		failures.append("collision protection remained after the hulls reached safe separation")
	if player_body.get_collision_exceptions().has(station_body):
		failures.append("collision exception was not restored after safe separation")
	if bool((combat.get("enemies") as Array)[0].get("docking_clearance", true)):
		failures.append("station clearance record remained active after safe separation")
	var pair_key: String = combat.call("_collision_pair_key", player_body, station_body)
	if float((combat.get("collision_pair_cooldowns") as Dictionary).get(pair_key, 0.0)) < 0.99:
		failures.append("release did not provide a collision settling window")

	if failures.is_empty():
		print("DOCKING COLLISION SAFETY TEST // PASS // IMMUNE UNTIL HULLS CLEAR")
		quit(0)
		return
	for failure: String in failures:
		push_error("DOCKING COLLISION SAFETY TEST // FAIL // %s" % failure)
	quit(1)
