class_name CloseCombatOverlay
extends Node2D

const TACTICAL_CELL_SIZE := 10.0
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const IMPACT_SPRITE_BURST_SCENE := preload("res://scenes/projectiles/impact_sprite_burst.tscn")

var view_host: Control
var ship_layout: Resource
var canvas_origin := Vector2.ZERO
var view_cell_size := 36.0
var projectile_visuals: Dictionary = {}
var fragment_visuals: Dictionary = {}
var shield_impacts: Array[Dictionary] = []
var connected_combat: Node


func configure(host: Control, layout: Resource, origin: Vector2, cell_size: float) -> void:
	view_host = host
	ship_layout = layout
	canvas_origin = origin
	view_cell_size = cell_size
	set_process(true)


func refresh_layout(layout: Resource) -> void:
	ship_layout = layout


func _process(_delta: float) -> void:
	if not is_instance_valid(view_host) or ship_layout == null:
		return
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(combat) or not is_instance_valid(ship) or not is_instance_valid(ship.physics_body):
		_hide_all_visuals()
		return
	_ensure_combat_connection(combat)
	_update_shield_impacts(_delta)
	_sync_projectiles(combat, ship.physics_body)
	_sync_fragments(combat, ship.physics_body)


func _ensure_combat_connection(combat: Node) -> void:
	if connected_combat == combat:
		return
	if is_instance_valid(connected_combat) and connected_combat.is_connected("shield_impact_detected", _on_shield_impact_detected):
		connected_combat.disconnect("shield_impact_detected", _on_shield_impact_detected)
	if is_instance_valid(connected_combat) and connected_combat.is_connected("impact_effect_requested", _on_impact_effect_requested):
		connected_combat.disconnect("impact_effect_requested", _on_impact_effect_requested)
	connected_combat = combat
	if not connected_combat.is_connected("shield_impact_detected", _on_shield_impact_detected):
		connected_combat.connect("shield_impact_detected", _on_shield_impact_detected)
	if not connected_combat.is_connected("impact_effect_requested", _on_impact_effect_requested):
		connected_combat.connect("impact_effect_requested", _on_impact_effect_requested)


func _on_shield_impact_detected(collider: RigidBody2D, point: Vector2, normal: Vector2, strength: float) -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or collider != ship.physics_body:
		return
	shield_impacts.append({
		"local_point": collider.to_local(point),
		"local_normal": normal.rotated(-collider.global_rotation),
		"strength": strength,
		"age": 0.0,
	})
	queue_redraw()


func _on_impact_effect_requested(
	collider: RigidBody2D,
	point: Vector2,
	normal: Vector2,
	impact_color: Color,
	impact_scene: PackedScene
) -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or collider != ship.physics_body:
		return
	var effect_scene := impact_scene if impact_scene != null else IMPACT_SPRITE_BURST_SCENE
	var effect := effect_scene.instantiate() as Node2D
	add_child(effect)
	effect.position = _world_to_view(collider, point)
	var local_normal := normal.rotated(-collider.global_rotation)
	effect.call("configure", local_normal, impact_color, _scale_ratio())


func _update_shield_impacts(delta: float) -> void:
	for index: int in range(shield_impacts.size() - 1, -1, -1):
		shield_impacts[index]["age"] = float(shield_impacts[index]["age"]) + delta
		if float(shield_impacts[index]["age"]) >= 0.75:
			shield_impacts.remove_at(index)
	if not shield_impacts.is_empty():
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(view_host) or ship_layout == null:
		return
	var bounds: Rect2i = view_host.call("_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, view_cell_size)
	var ship_center := canvas_origin + geometry_size * 0.5
	for impact: Dictionary in shield_impacts:
		var life_ratio := clampf(float(impact["age"]) / 0.75, 0.0, 1.0)
		var strength := float(impact["strength"])
		var point := ship_center + Vector2(impact["local_point"]) * _scale_ratio()
		var normal := Vector2(impact["local_normal"]).normalized()
		var center := point + normal * (3.0 + life_ratio * 5.0) * _scale_ratio()
		var color := Color(0.3, 0.95, 1.0, (1.0 - life_ratio) * strength)
		var radius := (4.0 + life_ratio * 16.0) * _scale_ratio()
		draw_arc(center, radius, 0.0, TAU, 24, color, maxf(1.0, 1.5 * _scale_ratio()), false)
		draw_arc(center, radius * 0.58, 0.0, TAU, 20, Color(color, color.a * 0.55), maxf(1.0, 0.7 * _scale_ratio()), false)


func _sync_projectiles(combat: Node, ship_body: RigidBody2D) -> void:
	var active_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for projectile: Dictionary in combat.projectiles:
		if bool(projectile.get("impacted", false)):
			continue
		var projectile_id: int = projectile["id"]
		var previous_world: Vector2 = projectile["previous_position"]
		var current_world: Vector2 = projectile["position"]
		var world_position := previous_world.lerp(current_world, interpolation)
		var local_position := _world_to_view(ship_body, world_position)
		if not _is_near_ship(local_position):
			continue
		active_ids[projectile_id] = true
		if not projectile_visuals.has(projectile_id):
			var visual_scene: PackedScene = projectile["visual_scene"]
			if visual_scene == null:
				continue
			var visual := visual_scene.instantiate() as Node2D
			add_child(visual)
			projectile_visuals[projectile_id] = visual
		var projectile_visual := projectile_visuals[projectile_id] as Node2D
		var local_velocity: Vector2 = Vector2(projectile["velocity"]).rotated(-ship_body.global_rotation)
		projectile_visual.position = local_position
		projectile_visual.rotation = local_velocity.angle()
		projectile_visual.scale = Vector2.ONE * _scale_ratio()
		if projectile_visual.has_method("set_travel_distance"):
			projectile_visual.call("set_travel_distance", float(projectile.get("travelled_distance", 0.0)))
	_remove_missing(projectile_visuals, active_ids)


func _sync_fragments(combat: Node, ship_body: RigidBody2D) -> void:
	var active_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for fragment: Dictionary in combat.impact_fragments:
		var fragment_id: int = fragment["id"]
		var previous_world: Vector2 = fragment["previous_position"]
		var current_world: Vector2 = fragment["position"]
		var local_position := _world_to_view(ship_body, previous_world.lerp(current_world, interpolation))
		if not _is_near_ship(local_position):
			continue
		active_ids[fragment_id] = true
		if not fragment_visuals.has(fragment_id):
			var line := Line2D.new()
			var half_length := float(fragment["length"]) * 0.5
			line.points = PackedVector2Array([Vector2(-half_length, 0.0), Vector2(half_length, 0.0)]) if bool(fragment.get("tumbling", false)) else PackedVector2Array([Vector2.ZERO, Vector2(-float(fragment["length"]), 0.0)])
			line.width = fragment["width"]
			line.default_color = fragment["color"]
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			add_child(line)
			fragment_visuals[fragment_id] = line
		var visual := fragment_visuals[fragment_id] as Line2D
		var local_velocity: Vector2 = Vector2(fragment["velocity"]).rotated(-ship_body.global_rotation)
		visual.position = local_position
		visual.scale = Vector2.ONE * _scale_ratio()
		if bool(fragment.get("tumbling", false)):
			visual.rotation = lerp_angle(float(fragment["previous_rotation"]), float(fragment["rotation"]), interpolation) - ship_body.global_rotation
		elif local_velocity.length_squared() > 0.01:
			visual.rotation = local_velocity.angle()
		var lifetime_ratio := float(fragment["remaining_lifetime"]) / maxf(float(fragment["maximum_lifetime"]), 0.001)
		visual.modulate.a = smoothstep(0.0, 0.35, lifetime_ratio)
	_remove_missing(fragment_visuals, active_ids)


func _world_to_view(ship_body: RigidBody2D, world_position: Vector2) -> Vector2:
	var bounds: Rect2i = view_host.call("_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, view_cell_size)
	return canvas_origin + geometry_size * 0.5 + ship_body.to_local(world_position) * _scale_ratio()


func _is_near_ship(view_position: Vector2) -> bool:
	var bounds: Rect2i = view_host.call("_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, view_cell_size)
	return Rect2(canvas_origin - Vector2.ONE * view_cell_size * 2.0, geometry_size + Vector2.ONE * view_cell_size * 4.0).has_point(view_position)


func _scale_ratio() -> float:
	return view_cell_size / TACTICAL_CELL_SIZE


func _remove_missing(visuals: Dictionary, active_ids: Dictionary) -> void:
	for id: Variant in visuals.keys().duplicate():
		if not active_ids.has(id):
			(visuals[id] as Node).queue_free()
			visuals.erase(id)


func _hide_all_visuals() -> void:
	_remove_missing(projectile_visuals, {})
	_remove_missing(fragment_visuals, {})
