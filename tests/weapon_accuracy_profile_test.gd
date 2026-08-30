extends SceneTree

const LASER := preload("res://resources/weapons/laser_emitter.tres")
const CANNON := preload("res://resources/weapons/longshot_cannon.tres")
const REPEATER := preload("res://resources/weapons/traverse_gun.tres")
const FIGHTER_AUTOCANNON := preload("res://resources/weapons/fighter_autocannon.tres")


func _init() -> void:
	var failures := PackedStringArray()
	var laser_spread := float(LASER.get("accuracy_degrees"))
	var cannon_spread := float(CANNON.get("accuracy_degrees"))
	var repeater_spread := float(REPEATER.get("accuracy_degrees"))
	var fighter_spread := float(FIGHTER_AUTOCANNON.get("accuracy_degrees"))

	_check(laser_spread < cannon_spread, "laser should be more precise than the cannon", failures)
	_check(cannon_spread < repeater_spread, "rapid repeater should spread wider than the cannon", failures)
	_check(repeater_spread < fighter_spread, "fighter autocannon should have the widest cone", failures)
	_check(repeater_spread >= 5.0, "rapid repeater spread is not visually meaningful", failures)
	_check(fighter_spread >= 7.0, "fighter autocannon spread is not visually meaningful", failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error("WEAPON ACCURACY PROFILE TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("WEAPON ACCURACY PROFILE TEST - PASS - PRECISION TO SUPPRESSION HIERARCHY")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
