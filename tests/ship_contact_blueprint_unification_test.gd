extends SceneTree

const CAPITAL_SHIP_INSTANCE := preload("res://scripts/capital_ship_instance.gd")
const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const STRUCTURAL_MATERIAL := preload("res://resources/default_structural_material.tres")
const DOOR_DEFINITION := preload("res://resources/default_door_definition.tres")

const CONTACT_PATHS := [
	"res://resources/ship_contacts/escort_definition.tres",
	"res://resources/ship_contacts/broadside_cruiser_definition.tres",
	"res://resources/ship_contacts/lane_freighter_definition.tres",
	"res://resources/ship_contacts/mining_outpost_definition.tres",
	"res://resources/ship_contacts/orbital_station_definition.tres",
]


func _init() -> void:
	for contact_path: String in CONTACT_PATHS:
		var contact := load(contact_path) as Resource
		_assert(contact != null, "contact profile must load: %s" % contact_path)
		var layout := contact.get("ship_layout") as Resource
		_assert(layout != null, "contact must reference a Shipyard blueprint: %s" % contact_path)
		_assert(layout.resource_path.begins_with("res://resources/ship_designs/"), "contact layout must live in the blueprint archive")
		_assert(int(layout.get("lattice_version")) == 2, "contact blueprint must use the current quarter lattice")
		_assert(not layout.get("rooms").is_empty(), "contact blueprint must contain installed grids")
		_assert(_has_no_overlaps(layout), "contact blueprint grids may not overlap")
		_assert(_has_room_type(layout, "COMMAND"), "contact blueprint must have command control")

		var instance := CAPITAL_SHIP_INSTANCE.new()
		instance.configure(7, 1, layout, contact, 0, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
		var record: Dictionary = instance.make_combat_record(Vector2.ZERO, 0.0)
		_assert(float(record["maximum_hull"]) > 0.0, "hull durability must derive from installed grids")
		_assert(int(record["crew_count"]) == int(record["crew_capacity"]), "NPC contact must fill its blueprint berths")
		_assert(record.has("room_power_factors"), "NPC contact must carry its blueprint reactor coverage")
		instance.free()

	var outpost := load("res://resources/ship_designs/salvage_outpost.tres") as Resource
	var station := load("res://resources/ship_designs/morrow_proving_yard.tres") as Resource
	_assert(String(outpost.get("vessel_kind")) == "STATION", "salvage outpost must be a station blueprint")
	_assert(String(station.get("vessel_kind")) == "STATION", "Morrow must be a station blueprint")
	_assert(_has_room_type(outpost, "DOCKING"), "salvage outpost must expose a real docking grid")
	_assert(_room_type_count(station, "DOCKING") == 4, "Morrow must expose four blueprint docking grids")
	_assert(_room_type_count(station, "POWER") == 2, "Morrow must have twin reactor grids")
	_assert(_room_type_count(station, "CREW_QUARTERS") == 2, "Morrow must have two crew habitat grids")
	_assert(_room_type_count(station, "WEAPONS") == 8, "Morrow must mount eight finished weapon modules")
	_assert(_room_type_count(station, "SHIELDS") == 8, "Morrow must mount eight directional shield grids")
	_assert(_room_type_count(outpost, "SHIELDS") == 8, "salvage outpost must mount a directional shield perimeter")
	_assert(_room_rect(station, &"station_command") == Rect2i(6, 6, 2, 2), "Morrow's bridge must occupy the blueprint center")

	var station_contact := load("res://resources/ship_contacts/orbital_station_definition.tres") as Resource
	var station_instance := CAPITAL_SHIP_INSTANCE.new()
	station_instance.configure(8, 1, station, station_contact, 0, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	var station_record: Dictionary = station_instance.make_combat_record(Vector2.ZERO, 0.0)
	var combat := COMBAT_SIMULATION.new()
	root.add_child(combat)
	combat.call("_refresh_enemy_blueprint_operations", station_record)
	_assert(bool(station_record["station_operational"]), "powered and manned station must be operational")
	_assert(float(station_record["maximum_shield"]) > 0.0, "station shields must derive from installed shield grids")
	_assert(is_equal_approx(float(station_record["shield_operating_factor"]), 1.0), "healthy powered station shields must be fully operational")
	var hull_before_hit := float(station_record["hull"])
	# Reputation reporting belongs to the live sector tree; this focused combat
	# record only verifies the station's physical and defensive response.
	station_record["neutral_contact"] = false
	combat.call("_apply_damage_to_enemy", station_record, {
		"damage": 20.0,
		"shield_damage_multiplier": 1.0,
		"hull_damage_multiplier": 1.0,
		"system_damage_multiplier": 1.0,
	})
	_assert(is_equal_approx(float(station_record["hull"]), hull_before_hit), "station shields must absorb incoming fire before the hull")
	_assert(bool(station_record["defense_alert"]), "attacked neutral station must activate its defenses")
	_assert(bool(station_record["player_targetable"]), "attacked station must remain targetable for combat")
	station_record["healthy_crew_count"] = 0
	combat.call("_refresh_enemy_blueprint_operations", station_record)
	_assert(not bool(station_record["station_operational"]), "unmanned station must take services offline")
	station_record["healthy_crew_count"] = station_record["crew_capacity"]
	station_record["room_damage"] = {&"station_reactors": 240.0}
	combat.call("_refresh_enemy_blueprint_operations", station_record)
	_assert(not bool(station_record["station_operational"]), "destroyed station reactors must take services offline")
	_assert(is_zero_approx(float(station_record["shield_operating_factor"])), "destroyed station reactors must collapse powered shields")
	_assert(is_zero_approx(float(station_record["shield"])), "collapsed station shields may not retain charge")
	combat.call("_apply_damage_to_enemy", station_record, {
		"damage": float(station_record["maximum_hull"]) + 1.0,
		"shield_damage_multiplier": 1.0,
		"hull_damage_multiplier": 1.0,
		"system_damage_multiplier": 1.0,
	})
	_assert(is_zero_approx(float(station_record["hull"])), "station hull must be destructible after its shield collapses")
	combat.call("_begin_enemy_destruction", station_record)
	_assert(bool(station_record["destruction_active"]), "destroyed station must enter the staged breakup sequence")
	_assert(not bool(station_record["station_operational"]), "destroying a station must leave every service offline")
	combat.free()
	station_instance.free()
	print("SHIP CONTACT BLUEPRINT UNIFICATION TEST // PASS // %d CONTACTS" % CONTACT_PATHS.size())
	quit(0)


func _has_no_overlaps(layout: Resource) -> bool:
	var occupied: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var cell := Vector2i(x, y)
					if occupied.has(cell):
						return false
					occupied[cell] = true
	return true


func _has_room_type(layout: Resource, type_name: String) -> bool:
	return _room_type_count(layout, type_name) > 0


func _room_type_count(layout: Resource, type_name: String) -> int:
	var count := 0
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != type_name:
			continue
		for rect: Rect2i in room.get("grid_rects"):
			count += maxi(rect.size.x * rect.size.y / 4, 1)
	return count


func _room_rect(layout: Resource, room_id: StringName) -> Rect2i:
	for room: Resource in layout.get("rooms"):
		if room.get("room_id") == room_id:
			var rects: Array[Rect2i] = room.get("grid_rects")
			return rects[0] if not rects.is_empty() else Rect2i()
	return Rect2i()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("SHIP CONTACT BLUEPRINT UNIFICATION TEST // FAIL // %s" % message)
	quit(1)
