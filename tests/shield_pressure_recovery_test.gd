extends SceneTree

const SHIP := preload("res://scripts/ship_simulation.gd")
const COMBAT := preload("res://scripts/combat_simulation.gd")
const LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM := preload("res://scripts/resources/room_layout_data.gd")

class TestShip extends ShipSimulation:
	func get_room_efficiency(_room_id: StringName) -> float:
		return 1.0

func _init() -> void:
	var combat := COMBAT.new()
	var layout := LAYOUT.new()
	var room := ROOM.new()
	room.room_id = &"omni"
	room.type_name = "SHIELDS"
	room.module_facing_quarters = -1
	var rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	room.grid_rects = rects
	var rooms: Array[Resource] = [room]
	layout.rooms = rooms
	var enemy := {"layout": layout, "position": Vector2.ZERO, "rotation": 0.0, "shield": 80.0, "maximum_shield": 80.0, "hull": 100.0}
	combat.call("_ensure_enemy_shields", enemy)
	var banks: Dictionary = enemy["shield_banks"]
	assert(banks.size() == 4, "omni generator must supply four banks")
	combat.call("_apply_damage_to_enemy", enemy, {"damage": 20.0}, &"", Vector2.UP)
	assert(banks[0]["current"] == 0.0)
	assert(banks[0]["recovery_delay"] == 5.0)
	assert(banks[1]["current"] == 20.0 and banks[2]["current"] == 20.0 and banks[3]["current"] == 20.0)
	combat.call("_update_enemy_shields", enemy, 4.0)
	assert(banks[0]["current"] == 0.0)
	combat.call("_update_enemy_shields", enemy, 2.0)
	assert(is_equal_approx(float(banks[0]["current"]), 0.6), "only time after lockout contributes recovery")
	combat.call("_apply_damage_to_enemy", enemy, {"damage": 1.0}, &"", Vector2.RIGHT)
	combat.call("_update_enemy_shields", enemy, 1.0)
	assert(banks[1]["current"] == 19.0, "light hits must delay recovery")
	enemy["rotation"] = PI * 0.5
	combat.call("_apply_damage_to_enemy", enemy, {"damage": 20.0}, &"", Vector2.DOWN)
	assert(banks[1]["current"] == 0.0, "rotation must select the local facing")
	var ship := TestShip.new()
	ship.ship_layout = layout
	ship.call("_initialize_directional_shields")
	ship.apply_shield_damage(20.0, Vector2.UP)
	assert(ship.shield_bank_currents[0] == 0.0 and ship.shield_bank_currents[1] == 20.0)
	ship.call("_update_shield", 4.0)
	assert(ship.shield_bank_currents[0] == 0.0)
	ship.call("_update_shield", 2.0)
	assert(is_equal_approx(float(ship.shield_bank_currents[0]), 1.5))
	ship.apply_shield_damage(1.0, Vector2.RIGHT)
	ship.call("_update_shield", 1.0)
	assert(ship.shield_bank_currents[1] == 19.0)
	ship.free()
	combat.free()
	print("SHIELD PRESSURE TEST // PASS // INDEPENDENT OMNI BANKS + HIT/BREAK DELAYS + ROTATED IMPACT")
	quit(0)
