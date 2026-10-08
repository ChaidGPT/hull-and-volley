extends SceneTree

const BUILDER_SCREEN := preload("res://scripts/ship_builder_screen.gd")
const STARTING_LAYOUT := preload("res://resources/starting_ship_layout.tres")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var builder := BUILDER_SCREEN.new() as ShipBuilderScreen
	root.add_child(builder)
	await process_frame
	builder.open_for_layout(STARTING_LAYOUT.duplicate(true), "STATION")
	await process_frame
	await process_frame

	var rail := builder.get("builder_resource_panel") as Control
	var dossier := builder.get("dossier_panel") as Control
	var power := builder.get("builder_power_meter") as Control
	var crew := builder.get("builder_crew_meter") as Control
	_check(rail != null and rail.size.x <= 369.0, "readiness HUD still stretches across the drydock", failures)
	_check(rail != null and rail.size.y <= 39.0, "readiness HUD is still taller than a compact status strip", failures)
	_check(power != null and bool(power.get("compact_hud")), "reactor readout is not using its compact HUD layout", failures)
	_check(crew != null and bool(crew.get("compact_hud")), "personnel readout is not using its compact HUD layout", failures)
	if rail != null and dossier != null:
		_check(
			not rail.get_global_rect().intersects(dossier.get_global_rect()),
			"readiness HUD overlaps the right-side grid dossier",
			failures
		)

	if failures.is_empty():
		print("SHIPYARD HUD LAYOUT TEST // PASS // COMPACT READOUTS KEEP CLEAR LANES")
		builder.free()
		quit(0)
		return
	for failure: String in failures:
		push_error("SHIPYARD HUD LAYOUT TEST // FAIL // %s" % failure)
	builder.free()
	quit(1)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
