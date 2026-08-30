extends SceneTree

const CREW_SIMULATION := preload("res://scripts/crew_simulation.gd")


func _initialize() -> void:
	var crew := CREW_SIMULATION.new()
	var first := {
		"id": 1,
		"door_crossing_id": "door:test",
		"dead": false,
		"ejected": false,
		"incapacitated": false,
	}
	var second := {
		"id": 2,
		"door_crossing_id": "door:test",
		"dead": false,
		"ejected": false,
		"incapacitated": false,
	}
	crew.crew_members.append(first)
	crew.crew_members.append(second)
	if not bool(crew.call("_claim_doorway", first, "door:test")):
		_fail("first arrival did not claim the doorway")
		crew.free()
		return
	if bool(crew.call("_claim_doorway", second, "door:test")):
		_fail("second arrival entered an occupied doorway")
		crew.free()
		return
	if int(crew.call("_doorway_queue_index", second, "door:test")) != 1:
		_fail("waiting crew did not receive a separate queue position")
		crew.free()
		return
	first.erase("door_crossing_id")
	crew.call("_sync_doorway_reservations")
	if not bool(crew.call("_claim_doorway", second, "door:test")):
		_fail("doorway ownership did not pass to the waiting crew member")
		crew.free()
		return
	crew.free()
	print("CREW DOOR TRAFFIC TEST - PASS - SINGLE-FILE CROSSING + CLEAN HANDOFF")
	quit(0)


func _fail(message: String) -> void:
	push_error("CREW DOOR TRAFFIC TEST - FAIL - %s" % message)
	quit(1)
