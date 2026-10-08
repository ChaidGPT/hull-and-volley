extends SceneTree

const MAIN_SCRIPT := preload("res://scripts/main.gd")


func _init() -> void:
	var main := MAIN_SCRIPT.new()
	var catalog: Array[Dictionary] = main.call("_combat_test_blueprints")
	var paths := PackedStringArray()
	var names := PackedStringArray()
	var kinds: Dictionary = {}
	for entry: Dictionary in catalog:
		paths.append(String(entry.get("path", "")))
		names.append(String(entry.get("name", "")))
		kinds[String(entry.get("path", ""))] = String(entry.get("kind", ""))
	_assert(
		paths.has("res://resources/ship_designs/small_ship.tres"),
		"original saved Small Ship is missing from combat testing"
	)
	_assert(
		paths.has("res://resources/ship_designs/small_ship_2.tres"),
		"new saved Small Ship 2 is missing from combat testing"
	)
	_assert(names.has("Small Ship"), "saved design name should be shown")
	_assert(names.has("Small Ship 2"), "second saved design name should be shown")
	_assert(
		kinds.get("res://resources/ship_designs/morrow_proving_yard.tres", "") == "STATION",
		"station blueprints must be identified for dedicated station selectors"
	)
	main.free()
	print("COMBAT TEST BLUEPRINT CATALOG TEST // PASS // %d DESIGNS" % catalog.size())
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBAT TEST BLUEPRINT CATALOG TEST // FAIL // %s" % message)
	quit(1)
