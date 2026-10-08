extends SceneTree

const CREW_SIMULATION := preload("res://scripts/crew_simulation.gd")
const LAYOUT := preload("res://resources/starting_ship_layout.tres")
const STRUCTURAL_MATERIAL := preload("res://resources/default_structural_material.tres")
const DOOR_DEFINITION := preload("res://resources/default_door_definition.tres")
const CREW_VISUAL := preload("res://resources/default_crew_visual.tres")


func _initialize() -> void:
	var failures := PackedStringArray()
	var structure := ShipStructuralState.new()
	structure.configure(LAYOUT.duplicate(true), STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	_check(not structure.doors.is_empty(), "Fixture ship has no doorway", failures)
	if structure.doors.is_empty():
		_finish(failures)
		return
	var door: Dictionary = structure.doors.values()[0]
	var door_id := String(door["id"])
	var cells: Array = door["cells"]
	var current_cell: Vector2i = cells[0]
	var next_cell: Vector2i = cells[1]

	var crew := CREW_SIMULATION.new()
	crew.crew_definition = CREW_VISUAL
	var member := {
		"id": 1,
		"position": structure.get_door_center(door_id),
		"current_cell": current_cell,
		"target_slot": {
			"room_id": structure.cell_rooms[next_cell],
			"cell": next_cell,
			"position": structure.get_door_approach_point(door_id, next_cell, 0.36),
		},
		"path": [next_cell],
		"path_index": 0,
		"assigned_room_id": &"",
		"door_crossing_id": door_id,
		"door_crossing_key": "%s:0" % door_id,
		"door_crossing_stage": 1,
		"door_crossing_hazard": false,
		"ejected": false,
	}
	crew.crew_members.append(member)
	crew.doorway_reservations = {door_id: 1}
	crew.crew_held_doors = {door_id: false}
	crew.call("_reconcile_crew_after_layout_change", structure)
	member = crew.crew_members[0]
	_check(not member.has("door_crossing_id"), "Refit retained stale doorway traversal state", failures)
	_check((crew.get("doorway_reservations") as Dictionary).is_empty(), "Refit retained a stale doorway reservation", failures)
	_check(Vector2(member["position"]).distance_to(structure.get_door_center(door_id)) > 0.10, "Refit left crew inside the doorway", failures)

	member["position"] = structure.get_door_center(door_id)
	member["current_cell"] = current_cell
	member["path"] = [next_cell]
	member["path_index"] = 0
	member["door_crossing_id"] = door_id
	member["door_crossing_stage"] = 1
	crew.doorway_reservations = {door_id: 1}
	crew.call(
		"_recover_stalled_door_crossing",
		member,
		structure,
		door_id,
		current_cell,
		next_cell,
		0,
		1,
		0.075
	)
	_check(member["current_cell"] == next_cell, "Live stall recovery did not finish the crossing", failures)
	_check(not member.has("door_crossing_id"), "Live stall recovery retained doorway ownership", failures)
	_check(Vector2(member["position"]).distance_to(structure.get_door_center(door_id)) > 0.20, "Live stall recovery left crew in the threshold", failures)

	crew.free()
	_finish(failures)


func _finish(failures: PackedStringArray) -> void:
	if not failures.is_empty():
		for failure: String in failures:
			push_error("CREW DOORWAY REFIT RECOVERY TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("CREW DOORWAY REFIT RECOVERY TEST // PASS // THRESHOLD ALWAYS CLEARED")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if condition:
		return
	failures.append(message)
