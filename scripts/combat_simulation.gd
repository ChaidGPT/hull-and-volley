class_name CombatSimulation
extends Node

signal player_weapon_fired(trace_noise: float)

signal shield_impact_detected(collider: RigidBody2D, point: Vector2, normal: Vector2, strength: float)
signal impact_effect_requested(collider: RigidBody2D, point: Vector2, normal: Vector2, impact_color: Color, impact_scene: PackedScene)
signal player_ship_destroyed(world_position: Vector2)
signal grid_pickup_collected(room_type: String, display_name: String, world_position: Vector2)
signal training_target_armed(target_id: int)

const PHYSICS_SHIP_SCENE := preload("res://scenes/physics_ship_body.tscn")
const CAPITAL_SHIP_INSTANCE_SCENE := preload("res://scenes/ships/capital_ship_instance.tscn")
const PHYSICS_PROJECTILE_SCENE := preload("res://scenes/physics_projectile.tscn")
const PHYSICAL_FRAGMENT_SCENE := preload("res://scenes/physical_impact_fragment.tscn")
const AUTONOMOUS_FIGHTER_SCENE := preload("res://scenes/craft/autonomous_fighter.tscn")
const SHIP_DESTRUCTION_SMALL_SCENE := preload("res://scenes/projectiles/impact_sprite_small.tscn")
const SHIP_DESTRUCTION_HEAVY_SCENE := preload("res://scenes/projectiles/impact_sprite_heavy.tscn")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const WEAPON_MOUNT_SOCKET := preload("res://scripts/weapon_mount_socket.gd")
const SHIP_BUILDER_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const SHIELD_SIMULATION := preload("res://scripts/ship_simulation.gd")
@export var shield_hit_recovery_delay := 2.0
@export var shield_break_recovery_delay := 5.0

enum EnemyBehavior {
	HOLD_POSITION,
	APPROACH,
	ORBIT,
	RETREAT,
}

enum ProjectileFaction {
	PLAYER,
	ENEMY,
	TEST_CHARTERED_COMBINE,
	TEST_FREE_SYSTEMS,
}

enum WeaponFireMode {
	LINKED,
	TRIGGER,
	SENTRY,
}

const TACTICAL_CELL_SIZE := 10.0
## Authored explosive cannon geometry: the upper 2x2 16px tiles are centered
## on the room socket at (16,16); the barrel tip is at y=64. A standard room is
## 160px in the authored art and 20 tactical units in combat space.

@export_category("Enemy Handling")
## Shipyard-blueprint contacts available in development and training spawners.
@export var ship_contact_definitions: Array[Resource] = []
## Optional grid-built station spawned as a fixed world landmark to the player's starboard side.
@export var default_space_station_definition: Resource
## Where the default station appears relative to the player when the tactical world starts.
@export var default_space_station_offset := Vector2(880.0, 40.0)
@export_range(5.0, 100.0, 1.0) var enemy_speed := 24.0
@export_range(1.0, 100.0, 1.0) var enemy_acceleration := 8.0
@export_range(1.0, 90.0, 1.0) var enemy_turn_speed_degrees := 16.0
@export_range(0.5, 90.0, 0.5) var enemy_turn_acceleration_degrees := 10.0
@export_range(0.1, 8.0, 0.1) var enemy_steering_response := 1.8
@export_range(0.0, 40.0, 0.25) var enemy_lateral_stabilization_acceleration := 8.0
@export_range(100.0, 1200.0, 10.0) var approach_distance := 420.0
@export_range(100.0, 1600.0, 10.0) var orbit_distance := 560.0

@export_category("Combat")
## Practical alignment allowance for fixed capital weapons. Prevents tiny physics motion from interrupting valid broadside fire.
@export_range(0.5, 30.0, 0.5) var fixed_weapon_alignment_degrees := 8.0
## Time between mounts in a player-triggered volley. Manual batteries ripple
## from the bow toward the stern instead of producing one visually merged shot.
@export_range(0.02, 0.25, 0.01) var manual_volley_mount_interval := 0.08
## Fraction of a projectile's authored mass used for rigid-body impact response. Zero keeps
## only the tiny positive mass Godot requires for contact detection. Damage is unaffected.
@export_range(0.0, 0.1, 0.001) var projectile_knockback_mass_scale := 0.0
## Shield energy restored to each enemy ship every second while its shield is active.
@export_range(0.0, 20.0, 0.1) var enemy_shield_regeneration := 0.6
## Brief time a projectile remains available to the renderer after impact.
@export_range(0.01, 0.25, 0.01) var projectile_impact_linger := 0.06
## Recycled projectile bodies prevent scene/shape/material allocation bursts in fleet combat.
@export_range(32, 1024, 16) var maximum_pooled_projectiles := 384
## Editor-authored recipe controlling the amount, physics, appearance, and lifetime of impact fragments.
@export var impact_debris_definition: Resource
## Default wall durability and atmosphere rules used by spawned enemy hulls.
@export var default_structural_material: Resource
## Default door behavior shared by spawned capital ships.
@export var default_door_definition: Resource
## Editor-authored vector hull fragmentation used when a capital ship is destroyed.
@export var destruction_debris_definition: Resource
## Time a mortally damaged capital ship remains intact and drifting before breakup.
@export_range(0.5, 8.0, 0.1) var ship_destruction_sequence_seconds := 2.6
## Cadence of localized internal blasts during the destruction sequence.
@export_range(0.08, 1.0, 0.02) var ship_destruction_burst_interval := 0.26

@export_category("World Sound Effects")
## Fast burst used when a fighter or similarly small object is destroyed.
@export var small_explosion_sound: AudioStream
## Full burst used when a capital ship or other medium contact is destroyed.
@export var medium_explosion_sound: AudioStream
## Heavy burst reserved for the player ship, stations, and very large contacts.
@export var large_explosion_sound: AudioStream
## Positive capture chirp played where salvage enters the player ship.
@export var grid_pickup_sound: AudioStream
## Distance at which a world sound has faded out completely.
@export_range(100.0, 5000.0, 25.0) var world_audio_max_distance := 1800.0
## Shape of distance falloff; larger values make distant events fade faster.
@export_range(0.1, 8.0, 0.1) var world_audio_attenuation := 1.25

@export_category("World Audio Zoom")
## Ship-view zoom treated as the quietest, most distant tactical camera.
@export_range(0.05, 2.0, 0.05) var world_audio_minimum_zoom := 0.2
## Ship-view zoom treated as the loudest, closest tactical camera.
@export_range(1.0, 8.0, 0.1) var world_audio_maximum_zoom := 3.0
## Volume adjustment applied to weapon and world sounds at minimum zoom.
@export_range(-60.0, 0.0, 0.5) var world_audio_zoomed_out_db := -24.0
## Volume adjustment applied to weapon and world sounds at maximum zoom.
@export_range(-20.0, 12.0, 0.5) var world_audio_zoomed_in_db := 2.0
## Dense battles mix into a bounded voice budget instead of creating one audio node per shot.
@export_range(4, 128, 1) var maximum_world_audio_voices := 28

@export_category("Carrier Operations")
## Basic flight-wing behavior used by a plain Hangar grid before a specialized hangar recipe is installed.
@export var basic_hangar_definition: Resource

@export_category("Ship Collision Damage")
@export_range(0.0, 100.0, 0.5) var minimum_damaging_collision_speed := 5.0
@export_range(0.0, 10.0, 0.05) var collision_damage_per_energy_unit := 1.0
@export_range(1.0, 500.0, 1.0) var maximum_collision_damage := 60.0
@export_range(0.05, 2.0, 0.05) var collision_damage_cooldown := 0.4
## Asteroids are compact hazards: this keeps impacts meaningful after the normal body-mass split.
@export_range(0.0, 10.0, 0.1) var asteroid_collision_damage_multiplier := 2.5
## Minimum hull loss once an asteroid impact exceeds the damaging-speed threshold.
@export_range(0.0, 20.0, 0.5) var minimum_asteroid_collision_damage := 2.0

@export_category("Grid Salvage")
## Distance at which loose grid salvage begins homing toward the player ship.
@export_range(40.0, 400.0, 5.0) var grid_pickup_magnet_radius := 150.0
## Distance from the ship center at which a loose grid is transferred to inventory.
@export_range(10.0, 120.0, 2.0) var grid_pickup_collection_radius := 52.0
## Acceleration applied while salvage is inside the magnetic capture envelope.
@export_range(10.0, 500.0, 5.0) var grid_pickup_magnet_acceleration := 135.0
## Gentle drag applied to free-floating salvage outside magnetic capture.
@export_range(0.0, 2.0, 0.05) var grid_pickup_space_drag := 0.16

var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var impact_fragments: Array[Dictionary] = []
var fighters: Array[Dictionary] = []
var grid_pickups: Array[Dictionary] = []
## Persistent fighter records keyed by carrier and hangar. Records remain while craft are docked.
var craft_rosters: Dictionary = {}
var hangar_launch_cooldowns: Dictionary = {}
var next_fighter_id := 1
var next_craft_id := 1
## Shared live weapon activity consumed by all three visual scales.
var weapon_operation_states: Dictionary = {}
var default_behavior := EnemyBehavior.HOLD_POSITION
var next_enemy_id := 1
var next_projectile_id := 1
var next_fragment_id := 1
var next_grid_pickup_id := 1
var player_weapon_cooldowns: Dictionary = {}
var pending_manual_fire: Array[Dictionary] = []
var manual_fire_reservations: Dictionary = {}
var manual_fire_clock := 0.0
var weapon_mount_room_cache: Dictionary = {}
var mount_geometry_cache: Dictionary = {}
var propulsion_profile_cache: Dictionary = {}
var tracked_mount_layouts: Dictionary = {}
var weapon_scene_muzzle_offset_cache: Dictionary = {}
var registered_physics_ships: Dictionary = {}
var collision_pair_cooldowns: Dictionary = {}
## Docking collision exceptions remain active until both hull bounds have
## actually cleared one another. The fixed undock animation distance can be
## shorter than a large or unusually-shaped player hull.
var pending_docking_releases: Dictionary = {}
var tactical_audio_zoom := 1.0
var tactical_audio_listener: AudioListener2D
var default_space_station_spawned := false
var player_destroyed := false
var player_destruction_remaining := 0.0
var player_destruction_burst_clock := 0.0
var player_destruction_burst_index := 0
var player_destruction_finalized := false
var player_direct_fire_active := false
var projectile_body_pool: Array[RigidBody2D] = []
var active_world_audio_players: Array[AudioStreamPlayer2D] = []
var world_audio_player_pool: Array[AudioStreamPlayer2D] = []


func _ready() -> void:
	add_to_group("combat_simulation")
	call_deferred("_register_existing_physics_ships")
	call_deferred("_spawn_default_space_station")
	call_deferred("_connect_player_destruction_signal")
	call_deferred("_ensure_tactical_audio_listener")
	call_deferred("_prewarm_player_mount_geometry")
	call_deferred("_connect_player_module_signals")


func _connect_player_module_signals() -> void:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player) or not player.has_signal("module_detached"):
		return
	if not player.module_detached.is_connected(_on_player_module_detached):
		player.module_detached.connect(_on_player_module_detached)


func _on_player_module_detached(piece_key: String, condition: Dictionary, world_position: Vector2, initial_velocity: Vector2) -> void:
	spawn_grid_pickup(piece_key, world_position, initial_velocity, condition, 2.0)


func _prewarm_player_mount_geometry() -> void:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(player):
		_prewarm_layout_mount_geometry(player.get("ship_layout"))


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player):
		return
	manual_fire_clock += delta
	_update_manual_fire_sequence()
	_update_collision_cooldowns(delta)
	_update_pending_docking_releases()
	_update_weapon_operation_states(delta)

	for enemy: Dictionary in enemies:
		enemy["previous_position"] = enemy["position"]
		enemy["previous_rotation"] = enemy["rotation"]
		_refresh_enemy_blueprint_operations(enemy)
		if bool(enemy.get("destruction_active", false)):
			_sync_doomed_enemy_transform(enemy)
			continue
		if bool(enemy.get("combat_test_ship", false)):
			enemy["combat_target_commitment"] = maxf(
				float(enemy.get("combat_target_commitment", 0.0)) - delta,
				0.0
			)
		_update_enemy_shields(enemy, delta)
		var combat_target := _combat_target_for_enemy(enemy, player)
		var movement_target: Vector2 = combat_target.get("position", enemy["position"])
		_update_enemy_movement(enemy, movement_target, delta, combat_target)
		var enemy_structure := enemy.get("structural_state") as ShipStructuralState
		if enemy_structure != null and (not bool(enemy.get("stationary", false)) or enemy_structure.has_active_atmosphere_events()):
			enemy_structure.update_atmosphere(delta)

	if not bool(player.get("is_destroyed")):
		_update_player_weapons(player, delta)
		for enemy: Dictionary in enemies:
			if not _enemy_should_defend(enemy):
				continue
			var combat_target := _combat_target_for_enemy(enemy, player)
			if not combat_target.is_empty():
				_update_enemy_weapons(enemy, combat_target, delta)
		_update_hangar_wings(player, delta)
	_update_fighters()
	_update_projectiles(player, delta)
	_update_impact_fragments(delta)
	_update_grid_pickups(player, delta)
	_update_tactical_audio_listener(player.ship_position)
	if player_destroyed:
		_update_player_destruction(player, delta)

	for index: int in range(enemies.size() - 1, -1, -1):
		if float(enemies[index]["hull"]) <= 0.0:
			if bool(enemies[index].get("training_target", false)):
				_reset_training_target(enemies[index])
				continue
			if not bool(enemies[index].get("destruction_active", false)):
				_begin_enemy_destruction(enemies[index])
			if _update_enemy_destruction(enemies[index], delta):
				_finalize_enemy_destruction(index, player)


func spawn_grid_pickup(
	piece_key: String,
	world_position: Vector2 = Vector2.INF,
	initial_velocity: Vector2 = Vector2.ZERO,
	condition: Dictionary = {},
	capture_delay: float = 0.0
) -> int:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player):
		return -1
	if world_position == Vector2.INF:
		var spawn_angle := randf_range(0.0, TAU)
		world_position = player.ship_position + Vector2.RIGHT.rotated(spawn_angle) * 230.0
		if initial_velocity.is_zero_approx():
			initial_velocity = Vector2.RIGHT.rotated(spawn_angle + PI * 0.5) * 9.0
	var module_recipe := _grid_pickup_module_recipe(player.ship_layout, piece_key)
	var room_type := "WEAPONS" if module_recipe != null else piece_key
	var template := _grid_pickup_room_template(player.ship_layout, room_type)
	if template == null:
		return -1
	var display_name := _grid_pickup_display_name(room_type)
	var pickup_color: Color = template.get("color")
	if module_recipe != null:
		display_name = String(module_recipe.get("display_name"))
		var payload: Resource = module_recipe.get("payload_resource")
		if payload != null:
			pickup_color = Color(payload.get("visual_color")).darkened(0.18)
	var pickup_id := next_grid_pickup_id
	next_grid_pickup_id += 1
	grid_pickups.append({
		"id": pickup_id,
		"inventory_key": piece_key,
		"room_type": room_type,
		"module_recipe": module_recipe,
		"display_name": display_name,
		"color": pickup_color,
		"footprint": Vector2i.ONE,
		"position": world_position,
		"previous_position": world_position,
		"velocity": initial_velocity,
		"rotation": randf_range(-PI, PI),
		"previous_rotation": 0.0,
		"angular_velocity": randf_range(-0.45, 0.45),
		"magnetized": false,
		"condition": condition.duplicate(true),
		"capture_delay": maxf(capture_delay, 0.0),
	})
	grid_pickups[-1]["previous_rotation"] = grid_pickups[-1]["rotation"]
	return pickup_id


func spawn_random_grid_pickup() -> int:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player) or player.ship_layout == null:
		return -1
	var candidates: PackedStringArray = []
	for template: Resource in player.ship_layout.get("room_types"):
		var room_type := String(template.get("type_name"))
		if room_type in ["COMMAND", "CREW", "CARGO", "SUPPLY_STORAGE"]:
			continue
		if room_type != "WEAPONS":
			candidates.append(room_type)
	for recipe: Resource in player.ship_layout.get("module_recipes"):
		if (
			recipe != null
			and int(recipe.get("family")) == ModuleRecipeDefinition.ModuleFamily.WEAPON
			and int(recipe.call("footprint_cell_count")) == 1
		):
			candidates.append("WEAPON:%s" % String(recipe.get("module_id")))
	if candidates.is_empty():
		return -1
	return spawn_grid_pickup(candidates[randi() % candidates.size()])


func clear_grid_pickups() -> void:
	grid_pickups.clear()


func get_grid_pickup_transform(pickup_id: int) -> Dictionary:
	for pickup: Dictionary in grid_pickups:
		if int(pickup.get("id", -1)) == pickup_id:
			return {
				"position": Vector2(pickup["position"]),
				"rotation": float(pickup["rotation"]),
			}
	return {}


func _update_grid_pickups(player: Node, delta: float) -> void:
	for index: int in range(grid_pickups.size() - 1, -1, -1):
		var pickup: Dictionary = grid_pickups[index]
		pickup["previous_position"] = pickup["position"]
		pickup["previous_rotation"] = pickup["rotation"]
		var position: Vector2 = pickup["position"]
		var velocity: Vector2 = pickup["velocity"]
		var distance_to_ship := position.distance_to(player.ship_position)
		pickup["capture_delay"] = maxf(float(pickup.get("capture_delay", 0.0)) - delta, 0.0)
		var magnetized := float(pickup["capture_delay"]) <= 0.0 and distance_to_ship <= grid_pickup_magnet_radius
		if magnetized and distance_to_ship > 0.001:
			var capture_strength := 1.0 - clampf(
				distance_to_ship / maxf(grid_pickup_magnet_radius, 1.0),
				0.0,
				1.0
			)
			velocity += position.direction_to(player.ship_position) * grid_pickup_magnet_acceleration * (0.35 + capture_strength * 0.9) * delta
		else:
			velocity *= maxf(0.0, 1.0 - grid_pickup_space_drag * delta)
		position += velocity * delta
		pickup["position"] = position
		pickup["velocity"] = velocity
		pickup["rotation"] = float(pickup["rotation"]) + float(pickup["angular_velocity"]) * delta
		pickup["magnetized"] = magnetized
		if position.distance_to(player.ship_position) > grid_pickup_collection_radius:
			continue
		var room_type := String(pickup["room_type"])
		var inventory_key := String(pickup.get("inventory_key", room_type))
		if float(pickup.get("capture_delay", 0.0)) > 0.0:
			continue
		var added_ids: Array = player.call("add_grid_piece", inventory_key, 1, pickup.get("condition", {}))
		if added_ids.is_empty():
			# A full cargo case is physical: salvage remains in the world instead
			# of silently deleting an existing part or overflowing the UI.
			var rejection_direction: Vector2 = Vector2(player.ship_position).direction_to(position)
			if rejection_direction == Vector2.ZERO:
				rejection_direction = Vector2.RIGHT.rotated(float(pickup["rotation"]))
			pickup["position"] = position + rejection_direction * 8.0
			pickup["velocity"] = rejection_direction * 48.0
			pickup["magnetized"] = false
			continue
		_play_world_sound(grid_pickup_sound, position, -1.0, 0.025)
		grid_pickup_collected.emit(
			room_type,
			String(pickup["display_name"]),
			position
		)
		grid_pickups.remove_at(index)


func _spawn_destroyed_ship_grid_salvage(enemy: Dictionary) -> void:
	var layout: Resource = enemy.get("layout")
	if layout == null:
		return
	var candidates: Array[Resource] = []
	for room: Resource in layout.get("rooms"):
		var room_type := String(room.get("type_name"))
		if room_type in ["COMMAND", "CREW", "CARGO", "SUPPLY_STORAGE"]:
			continue
		if _grid_pickup_room_template(layout, room_type) != null:
			candidates.append(room)
	if candidates.is_empty():
		return
	var salvaged_room := candidates[randi() % candidates.size()]
	var outward := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var salvage_key := String(salvaged_room.get("type_name"))
	var salvaged_recipe: Resource = salvaged_room.get("module_recipe")
	if (
		salvage_key == "WEAPONS"
		and salvaged_recipe != null
		and int(salvaged_recipe.get("family")) == ModuleRecipeDefinition.ModuleFamily.WEAPON
	):
		salvage_key = "WEAPON:%s" % String(salvaged_recipe.get("module_id"))
	spawn_grid_pickup(
		salvage_key,
		enemy.get("position", Vector2.ZERO) + outward * 35.0,
		outward * randf_range(8.0, 18.0)
	)


func _grid_pickup_room_template(layout: Resource, room_type: String) -> Resource:
	if layout == null:
		return null
	for template: Resource in layout.get("room_types"):
		if String(template.get("type_name")) == room_type:
			return template
	return null


func _grid_pickup_module_recipe(layout: Resource, piece_key: String) -> Resource:
	if layout == null or not piece_key.begins_with("WEAPON:"):
		return null
	var module_id := StringName(piece_key.trim_prefix("WEAPON:"))
	for recipe: Resource in layout.get("module_recipes"):
		if recipe != null and recipe.get("module_id") == module_id:
			return recipe
	return null


func _grid_pickup_display_name(room_type: String) -> String:
	match room_type:
		"POWER":
			return "REACTOR GRID"
		"PROPULSION":
			return "THRUSTER GRID"
		"WEAPONS":
			return "WEAPON GRID"
		"SHIELDS":
			return "SHIELD GENERATOR"
		"CREW_QUARTERS":
			return "CREW QUARTERS"
		"WORKSHOP":
			return "ENGINEERING BAY"
		"MEDICAL":
			return "MEDICAL BAY"
		"SECURITY":
			return "SECURITY GRID"
		"HANGAR":
			return "HANGAR GRID"
		"UNASSIGNED":
			return "OPEN GRID"
	return room_type.capitalize()


func spawn_enemy() -> int:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	return _spawn_enemy_with_definition(player.ship_layout, null)


func spawn_blueprint_contact(definition_index: int) -> int:
	if definition_index < 0 or definition_index >= ship_contact_definitions.size():
		return -1
	var definition: Resource = ship_contact_definitions[definition_index]
	var layout: Resource = definition.get("ship_layout")
	if layout == null:
		return -1
	return _spawn_enemy_with_definition(layout, definition)


func spawn_training_target(
	definition_index: int,
	world_position: Vector2,
	display_name: String
) -> int:
	if definition_index < 0 or definition_index >= ship_contact_definitions.size():
		return -1
	var definition: Resource = ship_contact_definitions[definition_index]
	var layout: Resource = definition.get("ship_layout")
	if layout == null:
		return -1
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var player_position := Vector2(player.get("ship_position")) if is_instance_valid(player) else Vector2.ZERO
	var target_id := _spawn_enemy_with_definition(
		layout,
		definition,
		world_position - player_position,
		PI,
		false
	)
	var target := _enemy_by_id(target_id)
	if target.is_empty():
		return -1
	target["display_name"] = display_name
	target["combat_active"] = false
	target["player_targetable"] = false
	target["defense_alert"] = false
	target["neutral_contact"] = false
	target["training_target"] = true
	target["training_aggressive"] = false
	target["training_spawn_position"] = world_position
	target["behavior"] = EnemyBehavior.HOLD_POSITION
	target["faction_id"] = &"UNAFFILIATED"
	target["civilian_role"] = &"PROVING_TARGET"
	var ship_instance := target.get("instance") as Node
	if is_instance_valid(ship_instance):
		ship_instance.set("display_name", display_name)
		ship_instance.set("combat_active", false)
	var target_body := target.get("physics_body") as RigidBody2D
	if is_instance_valid(target_body):
		target_body.linear_velocity = Vector2.ZERO
		target_body.angular_velocity = 0.0
		target_body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		target_body.freeze = true
	return target_id


func set_training_target_aggression(target_id: int, is_aggressive: bool) -> bool:
	var target := _enemy_by_id(target_id)
	if target.is_empty() or not bool(target.get("training_target", false)):
		return false
	if not is_aggressive:
		_reset_training_target(target)
		return true
	var was_aggressive := bool(target.get("training_aggressive", false))
	target["training_aggressive"] = is_aggressive
	target["combat_active"] = is_aggressive
	target["player_targetable"] = is_aggressive
	target["defense_alert"] = is_aggressive
	target["behavior"] = EnemyBehavior.APPROACH
	var target_body := target.get("physics_body") as RigidBody2D
	if is_instance_valid(target_body):
		target_body.freeze = false
	var ship_instance := target.get("instance") as Node
	if is_instance_valid(ship_instance):
		ship_instance.set("combat_active", is_aggressive)
	if not was_aggressive:
		training_target_armed.emit(target_id)
	return true


func _restore_training_target(target: Dictionary) -> void:
	target.erase("shield_banks")
	target["hull"] = float(target.get("maximum_hull", 1.0))
	target["shield"] = float(target.get("maximum_shield", 0.0))
	target["room_damage"] = {}
	target["velocity"] = Vector2.ZERO
	var body := target.get("physics_body") as RigidBody2D
	if is_instance_valid(body):
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0


func _reset_training_target(target: Dictionary) -> void:
	target["combat_active"] = false
	target["player_targetable"] = false
	target["defense_alert"] = false
	target["training_aggressive"] = false
	target["behavior"] = EnemyBehavior.HOLD_POSITION
	_restore_training_target(target)
	var reset_position := Vector2(target.get("training_spawn_position", target.get("position", Vector2.ZERO)))
	target["position"] = reset_position
	target["previous_position"] = reset_position
	target["rotation"] = PI
	target["previous_rotation"] = PI
	var body := target.get("physics_body") as RigidBody2D
	if is_instance_valid(body):
		body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		body.freeze = true
		body.global_position = reset_position
		body.global_rotation = PI
		body.set_deferred("global_position", reset_position)
		body.set_deferred("global_rotation", PI)
	var ship_instance := target.get("instance") as Node
	if is_instance_valid(ship_instance):
		ship_instance.set("combat_active", false)


func _spawn_default_space_station() -> void:
	if default_space_station_spawned or default_space_station_definition == null:
		return
	var layout: Resource = default_space_station_definition.get("ship_layout")
	if layout == null:
		return
	var station_id := _spawn_enemy_with_definition(
		layout,
		default_space_station_definition,
		default_space_station_offset,
		0.0,
		true
	)
	default_space_station_spawned = station_id >= 0
	if station_id >= 0:
		var station := _enemy_by_id(station_id)
		station["display_name"] = "MORROW PROVING YARD"
		var ship_instance := station.get("instance") as Node
		if is_instance_valid(ship_instance):
			ship_instance.set("display_name", "MORROW PROVING YARD")


func _spawn_enemy_with_definition(
	layout: Resource,
	definition: Resource,
	spawn_offset: Vector2 = Vector2.INF,
	spawn_rotation: float = PI,
	force_stationary: bool = false,
	combat_faction: int = ProjectileFaction.ENEMY,
	overrides: Dictionary = {}
) -> int:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var player_position := Vector2.ZERO
	if is_instance_valid(player):
		player_position = player.ship_position
	# The first test duplicate begins broadside to the player so fixed side-mounted
	# cannons and carrier engagement can both be observed immediately.
	if spawn_offset == Vector2.INF:
		spawn_offset = Vector2(620.0 + enemies.size() * 70.0, enemies.size() * 90.0)
	var enemy_id := next_enemy_id
	next_enemy_id += 1
	var ship_instance := CAPITAL_SHIP_INSTANCE_SCENE.instantiate()
	add_child(ship_instance)
	ship_instance.configure(
		enemy_id,
		combat_faction,
		layout,
		definition,
		default_behavior,
		default_structural_material,
		default_door_definition,
		force_stationary
	)
	for property_name: String in overrides:
		ship_instance.set(property_name, overrides[property_name])
	var physics_world := get_tree().get_first_node_in_group("physics_world")
	var spawn_position := player_position + spawn_offset
	var enemy_body: RigidBody2D = null
	if is_instance_valid(physics_world):
		enemy_body = ship_instance.spawn_physics_body(physics_world, spawn_position, spawn_rotation)
		_register_physics_ship(enemy_body)
	enemies.append(ship_instance.make_combat_record(spawn_position, spawn_rotation))
	_prewarm_layout_mount_geometry(layout)
	return enemy_id


func spawn_combat_test_ship(
	layout: Resource,
	political_faction_id: StringName,
	combat_faction: int,
	world_position: Vector2,
	world_rotation: float,
	display_name: String,
	tactical_tint: Color,
	hostile_to_player: bool,
	engage_npc_teams: bool = true
) -> int:
	if layout == null or combat_faction == ProjectileFaction.PLAYER:
		return -1
	var layout_stats: Dictionary = SHIP_BUILDER_ANALYZER.analyze(layout)
	var crew_capacity := int(layout_stats.get("crew_capacity", 0))
	var authored_shield_capacity := float(layout_stats.get("shield_capacity", 0.0))
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var player_position := Vector2(player.get("ship_position")) if is_instance_valid(player) else Vector2.ZERO
	var is_station := String(layout.get("vessel_kind")).to_upper() == "STATION"
	var ship_id := _spawn_enemy_with_definition(
		layout,
		null,
		world_position - player_position,
		world_rotation,
		is_station,
		combat_faction,
		{
			"display_name": display_name,
			"tactical_tint": tactical_tint,
			"political_faction_id": political_faction_id,
			"behavior": EnemyBehavior.APPROACH,
			"maximum_shield": authored_shield_capacity,
		}
	)
	var ship := _enemy_by_id(ship_id)
	if not ship.is_empty():
		ship["combat_test_ship"] = true
		ship["hostile_to_player"] = hostile_to_player
		ship["player_targetable"] = hostile_to_player
		ship["combat_test_engage_npcs"] = engage_npc_teams
		# NPC ships use an aggregate crew model rather than individual walking
		# agents. Test ships begin with every berth filled and therefore receive
		# full staffing performance from the existing NPC weapon simulation.
		ship["crew_capacity"] = crew_capacity
		ship["crew_count"] = crew_capacity
		ship["healthy_crew_count"] = crew_capacity
		ship["minimum_crew"] = int(layout_stats.get("minimum_crew", 0))
		ship["optimal_crew"] = int(layout_stats.get("optimal_crew", 0))
		ship["fully_staffed"] = true
		ship["combat_personality"] = _combat_personality_for(ship_id, combat_faction)
		ship["combat_target_id"] = -1
		ship["combat_target_commitment"] = 0.0
	return ship_id


func spawn_combat_test_neutral_station(
	layout: Resource,
	world_position: Vector2,
	world_rotation: float,
	display_name: String,
	hostile_to_player: bool = false,
	hostile_to_npcs: bool = false
) -> int:
	if layout == null or String(layout.get("vessel_kind")).to_upper() != "STATION":
		return -1
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var player_position := Vector2(player.get("ship_position")) if is_instance_valid(player) else Vector2.ZERO
	var station_id := _spawn_enemy_with_definition(
		layout, null, world_position - player_position, world_rotation, true,
		4,
		{"display_name": display_name, "tactical_tint": Color(0.68, 0.78, 0.76), "political_faction_id": &"UNAFFILIATED", "combat_active": false}
	)
	var station := _enemy_by_id(station_id)
	if station.is_empty():
		return -1
	station["combat_test_ship"] = true
	station["combat_test_neutral_station"] = true
	station["hostile_to_player"] = hostile_to_player
	station["combat_test_engage_npcs"] = hostile_to_npcs
	station["combat_test_neutral_prearmed"] = hostile_to_player or hostile_to_npcs
	station["combat_active"] = hostile_to_player or hostile_to_npcs
	station["player_targetable"] = hostile_to_player
	station["neutral_contact"] = true
	station["defense_alert"] = hostile_to_player or hostile_to_npcs
	station["behavior"] = EnemyBehavior.HOLD_POSITION
	station["combat_personality"] = _combat_personality_for(station_id, 4)
	station["combat_target_id"] = -1
	station["combat_target_commitment"] = 0.0
	return station_id


func _combat_personality_for(ship_id: int, combat_faction: int) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = int(ship_id * 7919 + combat_faction * 104729)
	var roles := ["BRAWLER", "FLANKER", "SKIRMISHER", "LINEBREAKER", "HUNTER"]
	var role := String(roles[abs(ship_id + combat_faction) % roles.size()])
	var range_factor := random.randf_range(0.58, 0.84)
	var aggression := random.randf_range(0.84, 1.18)
	var courage := random.randf_range(0.18, 0.42)
	var focus_fire := random.randf_range(0.15, 0.7)
	match role:
		"BRAWLER":
			range_factor = random.randf_range(0.44, 0.58)
			aggression = random.randf_range(1.05, 1.24)
		"SKIRMISHER":
			range_factor = random.randf_range(0.82, 0.94)
			courage = random.randf_range(0.32, 0.52)
		"FLANKER":
			focus_fire = random.randf_range(0.05, 0.3)
		"LINEBREAKER":
			courage = random.randf_range(0.1, 0.26)
		"HUNTER":
			focus_fire = random.randf_range(0.65, 0.9)
	return {
		"role": role,
		"range_factor": range_factor,
		"aggression": aggression,
		"courage": courage,
		"focus_fire": focus_fire,
		"orbit_sign": -1.0 if random.randf() < 0.5 else 1.0,
		"decision_interval": random.randf_range(0.45, 0.9),
		"target_commitment": random.randf_range(2.4, 5.5),
		"phase_offset": random.randf_range(0.0, TAU),
		"strafe_preference": random.randf_range(0.2, 0.82),
		"maneuver_persistence": random.randf_range(1.8, 4.5),
	}


func spawn_neutral_contact(
	definition: Resource,
	world_position: Vector2,
	world_rotation: float,
	display_name: String,
	civilian_role: StringName,
	navigation_route: Array,
	route_ping_pong: bool = true,
	waypoint_dwell_seconds: float = 3.0
) -> int:
	if definition == null:
		return -1
	var layout: Resource = definition.get("ship_layout")
	if layout == null:
		return -1
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var player_position := Vector2(player.get("ship_position")) if is_instance_valid(player) else Vector2.ZERO
	var contact_id := _spawn_enemy_with_definition(
		layout,
		definition,
		world_position - player_position,
		world_rotation,
		bool(definition.get("stationary_world_object"))
	)
	var contact := _enemy_by_id(contact_id)
	if contact.is_empty():
		return -1
	var ship_instance := contact.get("instance") as Node
	if is_instance_valid(ship_instance):
		ship_instance.set("display_name", display_name)
		ship_instance.set("combat_active", false)
	contact["display_name"] = display_name
	contact["combat_active"] = false
	contact["player_targetable"] = false
	contact["neutral_contact"] = true
	contact["civilian_role"] = civilian_role
	contact["civilian_route"] = navigation_route.duplicate()
	contact["civilian_route_index"] = 0
	contact["civilian_route_direction"] = 1
	contact["civilian_route_ping_pong"] = route_ping_pong
	contact["civilian_waypoint_dwell"] = maxf(waypoint_dwell_seconds, 0.0)
	contact["civilian_dwell_remaining"] = 0.0
	return contact_id


func clear_enemies() -> void:
	for enemy: Dictionary in enemies:
		var ship_instance := enemy.get("instance") as Node
		if is_instance_valid(ship_instance):
			ship_instance.call("destroy")
		else:
			var enemy_body := enemy.get("physics_body") as RigidBody2D
			if is_instance_valid(enemy_body):
				enemy_body.queue_free()
	enemies.clear()
	for projectile: Dictionary in projectiles:
		var projectile_body := projectile.get("physics_body") as RigidBody2D
		if is_instance_valid(projectile_body):
			_release_projectile_body(projectile_body)
	projectiles.clear()
	for fragment: Dictionary in impact_fragments:
		var fragment_body := fragment.get("physics_body") as RigidBody2D
		if is_instance_valid(fragment_body):
			fragment_body.queue_free()
	impact_fragments.clear()
	for fighter: Dictionary in fighters:
		var craft: Dictionary = fighter.get("craft", {})
		if not craft.is_empty():
			craft["state"] = "DOCKED" if int(craft["faction"]) == ProjectileFaction.PLAYER else "DESTROYED"
		var fighter_body_value: Variant = fighter.get("physics_body")
		if is_instance_valid(fighter_body_value):
			var fighter_body := fighter_body_value as RigidBody2D
			fighter_body.queue_free()
	fighters.clear()
	for roster_key_value: Variant in craft_rosters.keys().duplicate():
		if not String(roster_key_value).begins_with("%d:" % ProjectileFaction.PLAYER):
			craft_rosters.erase(roster_key_value)
	hangar_launch_cooldowns.clear()


func _update_hangar_wings(player: Node, delta: float) -> void:
	for cooldown_key: Variant in hangar_launch_cooldowns.keys().duplicate():
		hangar_launch_cooldowns[cooldown_key] = maxf(float(hangar_launch_cooldowns[cooldown_key]) - delta, 0.0)
	_update_carrier_hangars(player.ship_layout, player.physics_body, ProjectileFaction.PLAYER)
	for enemy: Dictionary in enemies:
		if not _enemy_should_defend(enemy):
			continue
		# The proving target begins as a gunnery test, not a four-fighter ambush.
		if bool(enemy.get("training_target", false)):
			continue
		var enemy_body := enemy.get("physics_body") as RigidBody2D
		var enemy_layout := enemy.get("layout") as Resource
		if enemy_layout != null:
			var enemy_faction := int(enemy_body.get_meta("ship_faction", ProjectileFaction.ENEMY)) if is_instance_valid(enemy_body) else ProjectileFaction.ENEMY
			_update_carrier_hangars(enemy_layout, enemy_body, enemy_faction)


func _update_carrier_hangars(layout: Resource, carrier_body: RigidBody2D, faction: int) -> void:
	if layout == null or not is_instance_valid(carrier_body):
		return
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "HANGAR":
			continue
		var recipe: Resource = room.get("module_recipe")
		var hangar: Resource = basic_hangar_definition
		if recipe != null and recipe.get("payload_resource") != null:
			hangar = recipe.get("payload_resource")
		if hangar == null:
			continue
		var behavior: Resource = hangar.get("default_craft_behavior")
		if behavior == null:
			continue
		var room_id: StringName = room.get("room_id")
		var room_efficiency := _carrier_room_efficiency(faction, carrier_body, room_id)
		if room_efficiency <= 0.0:
			continue
		var carrier_id: int = int(carrier_body.get_meta("ship_id", 0))
		var hangar_key := "%d:%d:%s" % [faction, carrier_id, String(room_id)]
		var roster: Array = _ensure_hangar_roster(hangar_key, faction, carrier_id, carrier_body, room_id, hangar, behavior)
		if float(hangar_launch_cooldowns.get(hangar_key, 0.0)) > 0.0:
			continue
		var docked_craft: Dictionary = {}
		for craft_value: Variant in roster:
			var craft: Dictionary = craft_value
			if String(craft["state"]) == "DOCKED":
				docked_craft = craft
				break
		if docked_craft.is_empty():
			continue
		var target_body := _nearest_hostile_ship(carrier_body.global_position, faction, float(hangar.get("operating_radius")))
		if not is_instance_valid(target_body):
			continue
		var launch_mount := _get_mount_data(layout, room, carrier_body.global_position, carrier_body.global_rotation)
		_launch_fighter(carrier_body, target_body, faction, room_id, hangar, behavior, launch_mount, docked_craft)
		hangar_launch_cooldowns[hangar_key] = float(hangar.get("deployment_interval")) * float(hangar.get("launch_cycle_multiplier")) / maxf(room_efficiency, 0.1)


func _carrier_room_efficiency(faction: int, carrier_body: RigidBody2D, room_id: StringName) -> float:
	if faction != ProjectileFaction.PLAYER:
		return 1.0
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player) or player.physics_body != carrier_body:
		return 1.0
	return float(player.call("get_room_efficiency", room_id))


func _active_fighter_count(carrier_body: RigidBody2D, room_id: StringName) -> int:
	var count := 0
	for fighter: Dictionary in fighters:
		if fighter.get("carrier") == carrier_body and fighter.get("hangar_room_id") == room_id:
			count += 1
	return count


func _ensure_hangar_roster(hangar_key: String, faction: int, carrier_id: int, carrier_body: RigidBody2D, room_id: StringName, hangar: Resource, behavior: Resource) -> Array:
	if not craft_rosters.has(hangar_key):
		craft_rosters[hangar_key] = []
	var roster: Array = craft_rosters[hangar_key]
	var capacity: int = int(hangar.get("craft_capacity"))
	while roster.size() < capacity:
		roster.append({
			"id": next_craft_id,
			"slot_index": roster.size(),
			"state": "DOCKED",
			"faction": faction,
			"carrier_id": carrier_id,
			"carrier": carrier_body,
			"hangar_room_id": room_id,
			"behavior": behavior,
			"current_hull": float(behavior.get("maximum_hull")),
		})
		next_craft_id += 1
	return roster


func get_hangar_craft(faction: int, carrier_id: int, room_id: StringName, docked_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var key := "%d:%d:%s" % [faction, carrier_id, String(room_id)]
	for craft_value: Variant in craft_rosters.get(key, []):
		var craft: Dictionary = craft_value
		if not docked_only or String(craft["state"]) == "DOCKED":
			result.append(craft)
	return result


func _nearest_hostile_ship(origin: Vector2, faction: int, maximum_distance: float) -> RigidBody2D:
	var nearest: RigidBody2D
	var nearest_distance := maximum_distance
	for ship_value: Variant in get_tree().get_nodes_in_group("physics_ships"):
		var ship := ship_value as RigidBody2D
		if not is_instance_valid(ship) or int(ship.get_meta("ship_faction", -1)) == faction:
			continue
		var target_enemy := _enemy_by_id(int(ship.get_meta("ship_id", -1)))
		if not target_enemy.is_empty() and not bool(target_enemy.get("combat_active", true)):
			continue
		var distance := origin.distance_to(ship.global_position)
		if distance <= nearest_distance:
			nearest = ship
			nearest_distance = distance
	return nearest


func _launch_fighter(carrier: RigidBody2D, target: RigidBody2D, faction: int, room_id: StringName, hangar: Resource, behavior: Resource, launch_mount: Dictionary, craft: Dictionary) -> void:
	var physics_world := get_tree().get_first_node_in_group("physics_world")
	if not is_instance_valid(physics_world):
		return
	var fighter := AUTONOMOUS_FIGHTER_SCENE.instantiate() as AutonomousFighter
	physics_world.add_child(fighter)
	var launch_direction: Vector2 = launch_mount["direction"]
	var launch_origin := _clear_launch_position(carrier, launch_mount["position"], launch_direction)
	fighter.global_position = launch_origin + launch_direction * 18.0
	fighter.global_rotation = Vector2.UP.angle_to(launch_direction)
	fighter.linear_velocity = carrier.linear_velocity + launch_direction * 35.0
	fighter.add_collision_exception_with(carrier)
	fighter.call(
		"configure",
		behavior,
		carrier,
		target,
		float(hangar.get("operating_radius")),
		faction,
		launch_origin,
		launch_direction
	)
	fighter.fire_requested.connect(_on_fighter_fire_requested)
	fighter.recovery_requested.connect(_on_fighter_recovery_requested)
	fighter.destroyed_in_combat.connect(_on_fighter_destroyed_in_combat)
	craft["state"] = "DEPLOYED"
	var fighter_id := next_fighter_id
	next_fighter_id += 1
	fighters.append({
		"id": fighter_id,
		"faction": faction,
		"carrier": carrier,
		"hangar_room_id": room_id,
		"behavior": behavior,
		"position": fighter.global_position,
		"previous_position": fighter.global_position,
		"rotation": fighter.global_rotation,
		"previous_rotation": fighter.global_rotation,
		"physics_body": fighter,
		"craft": craft,
	})


func _clear_launch_position(carrier: RigidBody2D, requested_position: Vector2, launch_direction: Vector2) -> Vector2:
	if not is_instance_valid(carrier) or launch_direction.is_zero_approx():
		return requested_position
	var direction := launch_direction.normalized()
	var space_state := carrier.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = carrier.collision_layer
	for step: int in range(0, 48):
		var candidate := requested_position + direction * float(step * 6)
		query.position = candidate
		var inside_carrier := false
		for hit: Dictionary in space_state.intersect_point(query, 16):
			if hit.get("collider") == carrier:
				inside_carrier = true
				break
		if not inside_carrier:
			return candidate
	return requested_position + direction * 288.0


func _update_fighters() -> void:
	for index: int in range(fighters.size() - 1, -1, -1):
		var fighter: Dictionary = fighters[index]
		var body_value: Variant = fighter.get("physics_body")
		if not is_instance_valid(body_value):
			var craft: Dictionary = fighter.get("craft", {})
			if not craft.is_empty() and String(craft["state"]) == "DEPLOYED":
				craft["state"] = "DESTROYED"
				craft["current_hull"] = 0.0
			fighters.remove_at(index)
			continue
		var body := body_value as RigidBody2D
		fighter["previous_position"] = fighter["position"]
		fighter["previous_rotation"] = fighter["rotation"]
		fighter["position"] = body.global_position
		fighter["rotation"] = body.global_rotation


func _on_fighter_fire_requested(fighter: AutonomousFighter, target_position: Vector2) -> void:
	var behavior: Resource = fighter.behavior
	var weapon: Resource = behavior.get("weapon") if behavior != null else null
	if weapon == null:
		return
	var forward := Vector2.UP.rotated(fighter.global_rotation)
	# The editable visual's nose/muzzle is nine tactical pixels forward at 0.5 scale.
	var mount := {"position": fighter.global_position + forward * 9.0, "direction": forward, "muzzle_clearance": 0.0}
	_fire_projectile(mount, target_position, weapon, fighter.faction, fighter.linear_velocity, fighter)


func _on_fighter_recovery_requested(fighter: AutonomousFighter) -> void:
	if is_instance_valid(fighter):
		for active_fighter: Dictionary in fighters:
			if active_fighter.get("physics_body") == fighter:
				var craft: Dictionary = active_fighter.get("craft", {})
				if not craft.is_empty():
					craft["state"] = "DOCKED"
					craft["current_hull"] = fighter.current_hull
				break
		fighter.queue_free()


func _on_fighter_destroyed_in_combat(_fighter: AutonomousFighter, world_position: Vector2) -> void:
	_play_world_sound(small_explosion_sound, world_position, -3.0, 0.08)


func set_all_enemy_behavior(behavior: int) -> void:
	default_behavior = behavior as EnemyBehavior
	for enemy: Dictionary in enemies:
		enemy["behavior"] = behavior


func _register_existing_physics_ships() -> void:
	for body_value: Variant in get_tree().get_nodes_in_group("physics_ships"):
		_register_physics_ship(body_value as RigidBody2D)


func _register_physics_ship(body: RigidBody2D) -> void:
	if not is_instance_valid(body) or registered_physics_ships.has(body.get_instance_id()):
		return
	registered_physics_ships[body.get_instance_id()] = true
	body.connect("ship_collision_detected", _on_ship_collision_detected)


func _update_collision_cooldowns(delta: float) -> void:
	for pair_key: Variant in collision_pair_cooldowns.keys().duplicate():
		collision_pair_cooldowns[pair_key] = float(collision_pair_cooldowns[pair_key]) - delta
		if float(collision_pair_cooldowns[pair_key]) <= 0.0:
			collision_pair_cooldowns.erase(pair_key)


func _on_ship_collision_detected(
	ship: RigidBody2D,
	other_body: RigidBody2D,
	point: Vector2,
	relative_velocity: Vector2
) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(other_body):
		return
	# Check clearance before classifying the other collider. This keeps docking
	# safe even if a future station body also belongs to an obstacle group.
	if _is_cleared_docking_pair(ship, other_body):
		return
	if other_body.is_in_group("sector_obstacles"):
		_apply_ship_obstacle_collision(ship, other_body, point, relative_velocity)
		return
	if not other_body.is_in_group("physics_ships"):
		return
	var pair_key := _collision_pair_key(ship, other_body)
	if collision_pair_cooldowns.has(pair_key):
		return
	var collision_speed := relative_velocity.length()
	if collision_speed < minimum_damaging_collision_speed:
		return
	collision_pair_cooldowns[pair_key] = collision_damage_cooldown
	var reduced_mass := ship.mass * other_body.mass / maxf(ship.mass + other_body.mass, 0.001)
	var damaging_speed := collision_speed - minimum_damaging_collision_speed
	var collision_energy := 0.5 * reduced_mass * damaging_speed * damaging_speed
	var base_damage := minf(
		collision_energy / 1000.0 * collision_damage_per_energy_unit,
		maximum_collision_damage
	)
	var total_mass := maxf(ship.mass + other_body.mass, 0.001)
	_apply_collision_damage_to_ship(ship, base_damage * 2.0 * other_body.mass / total_mass, point)
	_apply_collision_damage_to_ship(other_body, base_damage * 2.0 * ship.mass / total_mass, point)
	var surface_velocity := (ship.linear_velocity + other_body.linear_velocity) * 0.5
	_request_impact_sprite(
		ship,
		point,
		-relative_velocity.normalized(),
		Color(1.0, 0.48, 0.16)
	)


func _apply_ship_obstacle_collision(
	ship: RigidBody2D,
	obstacle: RigidBody2D,
	point: Vector2,
	relative_velocity: Vector2
) -> void:
	var pair_key := _collision_pair_key(ship, obstacle)
	if collision_pair_cooldowns.has(pair_key):
		return
	var collision_speed := relative_velocity.length()
	if collision_speed < minimum_damaging_collision_speed:
		return
	collision_pair_cooldowns[pair_key] = collision_damage_cooldown
	var total_mass := maxf(ship.mass + obstacle.mass, 0.001)
	var reduced_mass := ship.mass * obstacle.mass / total_mass
	var damaging_speed := collision_speed - minimum_damaging_collision_speed
	var collision_energy := 0.5 * reduced_mass * damaging_speed * damaging_speed
	var base_damage := minf(
		collision_energy / 1000.0 * collision_damage_per_energy_unit,
		maximum_collision_damage
	)
	var ship_damage := base_damage * 2.0 * obstacle.mass / total_mass
	if StringName(obstacle.get_meta("obstacle_type", &"")) == &"ASTEROID":
		ship_damage = maxf(
			ship_damage * asteroid_collision_damage_multiplier,
			minimum_asteroid_collision_damage
		)
	_apply_collision_damage_to_ship(ship, ship_damage, point)
	if obstacle.has_method("register_ship_impact"):
		obstacle.call("register_ship_impact", ship, point, relative_velocity, collision_energy)
	_request_impact_sprite(
		ship,
		point,
		-relative_velocity.normalized(),
		Color(0.72, 0.56, 0.38)
	)


func _collision_pair_key(first: RigidBody2D, second: RigidBody2D) -> String:
	var first_id := mini(first.get_instance_id(), second.get_instance_id())
	var second_id := maxi(first.get_instance_id(), second.get_instance_id())
	return "%d:%d" % [first_id, second_id]


func _apply_collision_damage_to_ship(body: RigidBody2D, damage: float, point: Vector2) -> void:
	if damage <= 0.0:
		return
	var room_id: StringName = body.call("get_room_id_nearest_world_point", point)
	var faction := int(body.get_meta("ship_faction", -1))
	if faction == ProjectileFaction.PLAYER:
		var player := get_tree().get_first_node_in_group("ship_simulation")
		if is_instance_valid(player):
			player.apply_hull_damage(damage, room_id)
			_destroy_player_ship_if_needed(player)
	elif faction != ProjectileFaction.PLAYER:
		var enemy := _enemy_by_id(int(body.get_meta("ship_id", -1)))
		if enemy.is_empty():
			return
		enemy["hull"] = maxf(float(enemy["hull"]) - damage, 0.0)
		if not room_id.is_empty():
			var room_damage: Dictionary = enemy.get("room_damage", {})
			room_damage[room_id] = float(room_damage.get(room_id, 0.0)) + damage
			enemy["room_damage"] = room_damage


func get_manual_target_status(player: Node) -> String:
	if player.manual_weapon_ids.is_empty():
		return "SELECT A FRIENDLY WEAPON"
	var target := _enemy_by_id(player.manual_target_enemy_id)
	if target.is_empty() or player.manual_target_room_id.is_empty():
		return "%d GUNS • SELECT ENEMY ROOM" % player.manual_weapon_ids.size()
	var room_name := String(player.manual_target_room_id).replace("_", " ").to_upper()
	var target_layout: Resource = target.get("layout", player.ship_layout)
	for room: Resource in target_layout.get("rooms"):
		if room.get("room_id") == player.manual_target_room_id:
			room_name = room.get("display_name")
			break
	var has_ready_weapon := false
	var has_in_range_weapon := false
	for room: Resource in player.ship_layout.get("rooms"):
		var room_id: StringName = room.get("room_id")
		if not player.manual_weapon_ids.has(room_id):
			continue
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		var target_position := _get_room_world_center(target_layout, player.manual_target_room_id, target["position"], target["rotation"])
		for mount_index: int in range(_weapon_mount_count(room)):
			var mount := _get_mount_data(player.ship_layout, _weapon_mount_room(room, mount_index), player.ship_position, player.ship_rotation)
			if _target_is_valid(mount, target_position, weapon):
				has_in_range_weapon = true
				if float(player_weapon_cooldowns.get(_weapon_mount_cooldown_key(room_id, mount_index), 0.0)) <= 0.0:
					has_ready_weapon = true
	if has_ready_weapon:
		return "%s • FIRING" % room_name
	if has_in_range_weapon:
		return "%s • RELOADING" % room_name
	return "%s • OUT OF RANGE OR ARC" % room_name


func _combat_target_for_enemy(enemy: Dictionary, player: Node) -> Dictionary:
	if not bool(enemy.get("combat_test_ship", false)):
		return {
			"position": Vector2(player.ship_position),
			"physics_body": player.physics_body,
			"is_player": true,
		}
	var source_body := enemy.get("physics_body") as RigidBody2D
	var source_faction := int(source_body.get_meta("ship_faction", ProjectileFaction.ENEMY)) if is_instance_valid(source_body) else ProjectileFaction.ENEMY
	var neutral_station := bool(enemy.get("combat_test_neutral_station", false))
	if neutral_station and not bool(enemy.get("defense_alert", false)):
		return {}
	var aggressor_faction := int(enemy.get("aggressor_combat_faction", -1))
	var neutral_prearmed := bool(enemy.get("combat_test_neutral_prearmed", false))
	var engage_npc_teams := bool(enemy.get("combat_test_engage_npcs", true))
	var source_position: Vector2 = enemy.get("position", Vector2.ZERO)
	var committed_id := int(enemy.get("combat_target_id", -1))
	if float(enemy.get("combat_target_commitment", 0.0)) > 0.0:
		if committed_id == 0 and bool(enemy.get("hostile_to_player", false)) and not bool(player.get("is_destroyed")):
			return {"position": Vector2(player.ship_position), "physics_body": player.physics_body, "is_player": true}
		var committed_enemy := _enemy_by_id(committed_id) if engage_npc_teams else {}
		if not committed_enemy.is_empty() and float(committed_enemy.get("hull", 0.0)) > 0.0:
			var committed_body := committed_enemy.get("physics_body") as RigidBody2D
			var committed_faction := int(committed_body.get_meta("ship_faction", -1)) if is_instance_valid(committed_body) else -1
			if is_instance_valid(committed_body) and committed_faction != source_faction and (not neutral_station or committed_faction == aggressor_faction):
				return {"position": Vector2(committed_enemy["position"]), "physics_body": committed_body, "enemy_id": committed_id}
	var nearest: Dictionary = {}
	var best_score := INF
	var personality: Dictionary = enemy.get("combat_personality", {})
	var focus_fire := float(personality.get("focus_fire", 0.5))
	for candidate: Dictionary in enemies:
		if not engage_npc_teams:
			continue
		if candidate == enemy or float(candidate.get("hull", 0.0)) <= 0.0:
			continue
		if not bool(candidate.get("combat_test_ship", false)):
			continue
		var candidate_body := candidate.get("physics_body") as RigidBody2D
		if not is_instance_valid(candidate_body):
			continue
		var candidate_faction := int(candidate_body.get_meta("ship_faction", -1))
		if candidate_faction == source_faction:
			continue
		if neutral_station and not neutral_prearmed and candidate_faction != aggressor_faction:
			continue
		if bool(candidate.get("combat_test_neutral_station", false)) and (
			not bool(candidate.get("defense_alert", false))
			or (
				not bool(candidate.get("combat_test_neutral_prearmed", false))
				and int(candidate.get("aggressor_combat_faction", -1)) != source_faction
			)
		):
			continue
		var distance := source_position.distance_squared_to(candidate["position"])
		var assigned_attackers := 0
		for ally: Dictionary in enemies:
			var ally_body := ally.get("physics_body") as RigidBody2D
			if is_instance_valid(ally_body) and int(ally_body.get_meta("ship_faction", -1)) == source_faction and int(ally.get("combat_target_id", -1)) == int(candidate["id"]):
				assigned_attackers += 1
		var saturation_penalty := float(assigned_attackers) * 180000.0 * (1.0 - focus_fire)
		var score := distance + saturation_penalty
		if score < best_score:
			best_score = score
			nearest = {
				"position": Vector2(candidate["position"]),
				"physics_body": candidate_body,
				"enemy_id": int(candidate["id"]),
			}
	if (bool(enemy.get("hostile_to_player", false)) or (neutral_station and aggressor_faction == ProjectileFaction.PLAYER)) and not bool(player.get("is_destroyed")):
		var player_distance := source_position.distance_squared_to(player.ship_position)
		if player_distance < best_score:
			nearest = {
				"position": Vector2(player.ship_position),
				"physics_body": player.physics_body,
				"is_player": true,
			}
	if not nearest.is_empty():
		enemy["combat_target_id"] = 0 if bool(nearest.get("is_player", false)) else int(nearest.get("enemy_id", -1))
		enemy["combat_target_commitment"] = float(personality.get("target_commitment", 3.5))
	return nearest


func _update_enemy_movement(
	enemy: Dictionary,
	player_position: Vector2,
	delta: float,
	combat_target: Dictionary = {}
) -> void:
	var physics_body := enemy.get("physics_body") as RigidBody2D
	if is_instance_valid(physics_body):
		enemy["position"] = physics_body.global_position
		enemy["rotation"] = physics_body.global_rotation
		enemy["velocity"] = physics_body.linear_velocity
		if bool(enemy.get("stationary", false)):
			physics_body.linear_velocity = Vector2.ZERO
			physics_body.angular_velocity = 0.0
			enemy["velocity"] = Vector2.ZERO
			return
	var enemy_position: Vector2 = enemy["position"]
	var to_player := player_position - enemy_position
	var distance_to_player := to_player.length()
	var direction_to_player := to_player.normalized()
	var desired_velocity := Vector2.ZERO
	var desired_rotation_override := INF

	var civilian_route: Array = enemy.get("civilian_route", [])
	if not civilian_route.is_empty():
		desired_velocity = _civilian_route_velocity(enemy, enemy_position, delta)
	elif bool(enemy.get("combat_test_ship", false)) and not combat_target.is_empty():
		var maneuver := _combat_test_maneuver(enemy, combat_target, delta)
		desired_velocity = maneuver.get("velocity", Vector2.ZERO)
		desired_rotation_override = float(maneuver.get("rotation", INF))
	else:
		match int(enemy["behavior"]):
			EnemyBehavior.APPROACH:
				if distance_to_player > approach_distance:
					desired_velocity = direction_to_player * enemy_speed
			EnemyBehavior.ORBIT:
				var tangent := direction_to_player.orthogonal()
				var radial_correction := direction_to_player * clampf((distance_to_player - orbit_distance) / orbit_distance, -0.75, 0.75)
				desired_velocity = (tangent + radial_correction).normalized() * enemy_speed
			EnemyBehavior.RETREAT:
				desired_velocity = -direction_to_player * enemy_speed

	var velocity: Vector2 = enemy["velocity"]
	if is_instance_valid(physics_body):
		var desired_angular_velocity := 0.0
		var forward_throttle := 0.0
		var brake_throttle := 1.0 if desired_velocity.is_zero_approx() else 0.0
		if not desired_velocity.is_zero_approx():
			var commanded_speed := desired_velocity.length()
			var desired_rotation := (
				desired_rotation_override
				if is_finite(desired_rotation_override)
				else Vector2.UP.angle_to(desired_velocity.normalized())
			)
			desired_angular_velocity = clampf(
				angle_difference(float(enemy["rotation"]), desired_rotation) * enemy_steering_response,
				-deg_to_rad(enemy_turn_speed_degrees),
				deg_to_rad(enemy_turn_speed_degrees)
			)
			var enemy_forward := Vector2.UP.rotated(float(enemy["rotation"]))
			var heading_alignment := enemy_forward.dot(desired_velocity.normalized())
			if heading_alignment > 0.55 and velocity.dot(enemy_forward) < commanded_speed:
				forward_throttle = clampf((heading_alignment - 0.55) / 0.45, 0.0, 1.0)
			if velocity.length() > commanded_speed + 0.5:
				brake_throttle = 1.0
		var propulsion_profile := _enemy_propulsion_profile(enemy.get("layout") as Resource)
		# A combat helm may ask for a travel vector that differs from the weapon
		# bearing. Honor that request only when installed side thrusters can produce
		# the lateral force; conventional hulls retain turn-then-drive handling.
		var can_strafe := (
			is_finite(desired_rotation_override)
			and bool(propulsion_profile.get("has_lateral_translation", false))
		)
		if can_strafe:
			var local_travel_direction := (
				desired_velocity.normalized().rotated(-float(enemy["rotation"]))
				if not desired_velocity.is_zero_approx()
				else Vector2.ZERO
			)
			physics_body.call(
				"set_translation_command",
				desired_velocity,
				desired_angular_velocity,
				deg_to_rad(enemy_turn_acceleration_degrees),
				enemy_lateral_stabilization_acceleration,
				float(propulsion_profile.get("translation_port_acceleration", 0.0)),
				float(propulsion_profile.get("translation_starboard_acceleration", 0.0)),
				float(propulsion_profile.get("translation_forward_acceleration", 0.0)),
				float(propulsion_profile.get("translation_reverse_acceleration", 0.0)),
				-local_travel_direction
			)
		else:
			physics_body.call(
				"set_propulsion_command",
				forward_throttle,
				brake_throttle,
				desired_angular_velocity,
				enemy_acceleration,
				enemy_acceleration,
				deg_to_rad(enemy_turn_acceleration_degrees),
				enemy_lateral_stabilization_acceleration
			)
	else:
		velocity = velocity.move_toward(desired_velocity, enemy_acceleration * delta)
		enemy["velocity"] = velocity
		enemy["position"] = enemy_position + velocity * delta
	if not is_instance_valid(physics_body) and velocity.length_squared() > 0.1:
		var desired_rotation := (
			desired_rotation_override
			if is_finite(desired_rotation_override)
			else Vector2.UP.angle_to(velocity.normalized())
		)
		enemy["rotation"] = rotate_toward(float(enemy["rotation"]), desired_rotation, deg_to_rad(enemy_turn_speed_degrees) * delta)


## Builds the physical translation authority of an enemy blueprint from the
## exhaust direction of every installed thruster. Values are normalized to the
## strongest bank so adding maneuvering thrusters changes available directions
## without making a blueprint arbitrarily faster because its rooms are larger.
func _enemy_propulsion_profile(layout: Resource) -> Dictionary:
	if layout == null:
		return {}
	var layout_id := layout.get_instance_id()
	if propulsion_profile_cache.has(layout_id):
		return propulsion_profile_cache[layout_id]
	_track_mount_layout(layout)
	var banks := {
		"bow": 0.0,
		"starboard": 0.0,
		"aft": 0.0,
		"port": 0.0,
	}
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "PROPULSION":
			continue
		var rects: Array[Rect2i] = room.get("grid_rects")
		var facings: Array = room.get("module_mount_facings")
		var mount_count := maxi(int(room.get("installed_piece_count")), 1)
		if mount_count > 1 and rects.size() >= mount_count:
			for mount_index: int in range(mount_count):
				var facing := (
					posmod(int(facings[mount_index]), 4)
					if mount_index < facings.size()
					else posmod(GRID_GEOMETRY.resolved_module_facing(layout, room), 4)
				)
				_add_enemy_thruster_bank(banks, facing, float(maxi(rects[mount_index].get_area(), 1)))
		else:
			var cell_count := 0
			for rect: Rect2i in rects:
				cell_count += rect.get_area()
			_add_enemy_thruster_bank(
				banks,
				posmod(GRID_GEOMETRY.resolved_module_facing(layout, room), 4),
				float(maxi(cell_count, 1))
			)
	var strongest_bank := maxf(
		maxf(float(banks["bow"]), float(banks["aft"])),
		maxf(float(banks["port"]), float(banks["starboard"]))
	)
	var acceleration_scale := enemy_acceleration / maxf(strongest_bank, 1.0)
	var profile := {
		"banks": banks,
		# Exhaust points aft for forward force, starboard for port force, etc.
		"translation_forward_acceleration": float(banks["aft"]) * acceleration_scale,
		"translation_reverse_acceleration": float(banks["bow"]) * acceleration_scale,
		"translation_starboard_acceleration": float(banks["port"]) * acceleration_scale,
		"translation_port_acceleration": float(banks["starboard"]) * acceleration_scale,
		"has_lateral_translation": (
			float(banks["port"]) > 0.001 or float(banks["starboard"]) > 0.001
		),
	}
	propulsion_profile_cache[layout_id] = profile
	return profile


func _add_enemy_thruster_bank(banks: Dictionary, facing: int, output: float) -> void:
	match posmod(facing, 4):
		0:
			banks["bow"] = float(banks["bow"]) + output
		1:
			banks["starboard"] = float(banks["starboard"]) + output
		2:
			banks["aft"] = float(banks["aft"]) + output
		3:
			banks["port"] = float(banks["port"]) + output


func _combat_test_maneuver(enemy: Dictionary, target: Dictionary, delta: float) -> Dictionary:
	var enemy_position: Vector2 = enemy.get("position", Vector2.ZERO)
	var target_position: Vector2 = target.get("position", enemy_position)
	var to_target := target_position - enemy_position
	if to_target.is_zero_approx():
		return {"velocity": Vector2.ZERO, "rotation": float(enemy.get("rotation", 0.0))}
	var target_direction := to_target.normalized()
	var personality: Dictionary = enemy.get("combat_personality", {})
	var aggression := float(personality.get("aggression", 1.0))
	var range_factor := float(personality.get("range_factor", 0.72))
	var orbit_sign := float(personality.get("orbit_sign", 1.0))
	var hull_ratio := float(enemy.get("hull", 0.0)) / maxf(float(enemy.get("maximum_hull", 1.0)), 1.0)
	if hull_ratio <= float(personality.get("courage", 0.25)):
		var retreat_direction := -target_direction
		return {
			"velocity": retreat_direction * enemy_speed * 1.12,
			"rotation": Vector2.UP.angle_to(retreat_direction),
		}
	var weapon_range := _layout_maximum_weapon_range(enemy.get("layout") as Resource)
	var engagement_distance := clampf(weapon_range * range_factor, 240.0, 780.0)
	var distance := to_target.length()
	# Outside practical range, close efficiently before beginning a broadside.
	if distance > maxf(weapon_range * 0.92, engagement_distance + 100.0):
		return {
			"velocity": target_direction * enemy_speed * aggression,
			"rotation": Vector2.UP.angle_to(target_direction),
		}

	var refresh := maxf(float(enemy.get("combat_helm_refresh", 0.0)) - delta, 0.0)
	enemy["combat_helm_refresh"] = refresh
	if refresh <= 0.0 or not enemy.has("combat_attack_rotation"):
		var preferred_orbit := target_direction.orthogonal() * orbit_sign
		enemy["combat_attack_rotation"] = _best_battery_attack_rotation(enemy, target_position, preferred_orbit)
		enemy["combat_helm_refresh"] = float(personality.get("decision_interval", 0.65))
	var attack_rotation := float(enemy.get("combat_attack_rotation", Vector2.UP.angle_to(target_direction)))
	var attack_forward := Vector2.UP.rotated(attack_rotation)
	var under_heavy_threat := _target_has_heavy_weapon_solution(target, enemy_position)
	var maneuver_refresh := maxf(float(enemy.get("combat_maneuver_refresh", 0.0)) - delta, 0.0)
	enemy["combat_maneuver_refresh"] = maneuver_refresh
	if maneuver_refresh <= 0.0 or not enemy.has("combat_maneuver_mode"):
		enemy["combat_maneuver_mode"] = _choose_combat_maneuver(
			enemy,
			under_heavy_threat
		)
		enemy["combat_maneuver_refresh"] = float(personality.get("maneuver_persistence", 2.8))
		var cycle := int(enemy.get("combat_maneuver_cycle", 0)) + 1
		enemy["combat_maneuver_cycle"] = cycle
		# Some captains reverse their circling direction between committed maneuvers;
		# others retain it. This prevents fleets from becoming synchronized rings.
		if posmod(cycle + int(enemy.get("id", 0)), 3) == 0:
			enemy["combat_orbit_sign"] = -float(enemy.get("combat_orbit_sign", orbit_sign))
	var active_orbit_sign := float(enemy.get("combat_orbit_sign", orbit_sign))
	var orbit_velocity := target_direction.orthogonal() * active_orbit_sign
	if attack_forward.dot(orbit_velocity) < 0.0:
		orbit_velocity = -orbit_velocity
	var radial_correction := target_direction * clampf(
		(distance - engagement_distance) / maxf(engagement_distance * 0.35, 1.0),
		-1.0,
		1.0
	)
	var maneuver_mode := String(enemy.get("combat_maneuver_mode", "ORBIT"))
	var desired_vector := orbit_velocity * (1.0 if under_heavy_threat else 0.58) + radial_correction
	match maneuver_mode:
		"PRESS":
			desired_vector = target_direction * 0.9 + orbit_velocity * 0.22
		"KITE":
			desired_vector = -target_direction * 0.72 + orbit_velocity * 0.38
		"HOLD":
			desired_vector = radial_correction if absf(distance - engagement_distance) > 45.0 else Vector2.ZERO
		"STRAFE":
			desired_vector = orbit_velocity + radial_correction * 0.48
		"EVADE":
			desired_vector = orbit_velocity * 1.2 - target_direction * 0.3
	var desired_direction := desired_vector.normalized()
	if desired_direction.is_zero_approx():
		return {"velocity": Vector2.ZERO, "rotation": attack_rotation}
	var propulsion_profile := _enemy_propulsion_profile(enemy.get("layout") as Resource)
	desired_direction = _best_supported_combat_direction(
		desired_direction,
		attack_rotation,
		propulsion_profile,
		target_direction,
		orbit_velocity
	)
	var maneuver_speed_factor := 1.0 if maneuver_mode in ["STRAFE", "EVADE"] else 0.72
	return {
		"velocity": desired_direction * enemy_speed * aggression * maneuver_speed_factor,
		"rotation": attack_rotation,
	}


func _choose_combat_maneuver(enemy: Dictionary, under_heavy_threat: bool) -> String:
	var personality: Dictionary = enemy.get("combat_personality", {})
	var profile := _enemy_propulsion_profile(enemy.get("layout") as Resource)
	var has_lateral := bool(profile.get("has_lateral_translation", false))
	var cycle := int(enemy.get("combat_maneuver_cycle", 0))
	var random := RandomNumberGenerator.new()
	random.seed = int(enemy.get("id", 0)) * 92821 + cycle * 68917 + 17
	var roll := random.randf()
	if under_heavy_threat and roll < 0.62:
		return "EVADE"
	var strafe_chance := float(personality.get("strafe_preference", 0.45)) if has_lateral else 0.0
	if roll < strafe_chance:
		return "STRAFE"
	roll = (roll - strafe_chance) / maxf(1.0 - strafe_chance, 0.001)
	var aggression := float(personality.get("aggression", 1.0))
	var range_factor := float(personality.get("range_factor", 0.72))
	if roll < clampf(0.22 + (aggression - 1.0) * 0.5, 0.12, 0.38):
		return "PRESS"
	if roll < clampf(0.34 + range_factor * 0.22, 0.42, 0.58):
		return "KITE"
	if roll > 0.9:
		return "HOLD"
	return "ORBIT"


## Selects a nearby tactical vector the installed thrust banks can execute while
## the hull retains its chosen weapon bearing. This is blueprint-agnostic: a
## broadside ship may orbit on aft thrust, a bow battery may press, and a hull
## with maneuvering jets may translate laterally or in reverse.
func _best_supported_combat_direction(
	desired_direction: Vector2,
	attack_rotation: float,
	profile: Dictionary,
	target_direction: Vector2,
	orbit_direction: Vector2
) -> Vector2:
	if profile.is_empty():
		return desired_direction
	var candidates: Array[Vector2] = [
		desired_direction,
		target_direction,
		-target_direction,
		orbit_direction,
		-orbit_direction,
	]
	var strongest := maxf(
		maxf(
			float(profile.get("translation_forward_acceleration", 0.0)),
			float(profile.get("translation_reverse_acceleration", 0.0))
		),
		maxf(
			float(profile.get("translation_port_acceleration", 0.0)),
			float(profile.get("translation_starboard_acceleration", 0.0))
		)
	)
	var best := desired_direction
	var best_score := -INF
	for candidate: Vector2 in candidates:
		var local_direction := candidate.rotated(-attack_rotation)
		var authority := _enemy_translation_authority(profile, local_direction) / maxf(strongest, 0.001)
		var intent_alignment := desired_direction.dot(candidate)
		var score := intent_alignment * 0.72 + authority * 1.05
		if score > best_score:
			best_score = score
			best = candidate
	return best.normalized()


func _enemy_translation_authority(profile: Dictionary, local_direction: Vector2) -> float:
	if local_direction.is_zero_approx():
		return 0.0
	var direction := local_direction.normalized()
	var horizontal := (
		float(profile.get("translation_starboard_acceleration", 0.0))
		if direction.x >= 0.0
		else float(profile.get("translation_port_acceleration", 0.0))
	)
	var vertical := (
		float(profile.get("translation_reverse_acceleration", 0.0))
		if direction.y >= 0.0
		else float(profile.get("translation_forward_acceleration", 0.0))
	)
	return absf(direction.x) * horizontal + absf(direction.y) * vertical


func _best_battery_attack_rotation(enemy: Dictionary, target_position: Vector2, preferred_forward: Vector2 = Vector2.ZERO) -> float:
	var layout := enemy.get("layout") as Resource
	if layout == null:
		return Vector2.UP.angle_to((target_position - Vector2(enemy["position"])).normalized())
	var best_rotation := float(enemy.get("rotation", 0.0))
	var best_score := -INF
	# Twelve headings are sufficient for authored weapon arcs and cut tactical
	# scoring work in half during large fleet actions.
	for step: int in range(12):
		var candidate_rotation := float(step) * TAU / 12.0
		var score := 0.0
		for room: Resource in layout.get("rooms"):
			if String(room.get("type_name")) != "WEAPONS":
				continue
			var weapon := room.get("weapon_definition") as Resource
			if weapon == null:
				continue
			var weapon_weight := maxf(float(weapon.get("damage")), 1.0) / maxf(float(weapon.get("reload_seconds")), 0.1)
			for mount_index: int in range(_weapon_mount_count(room)):
				var mount_room := _weapon_mount_room(room, mount_index)
				var mount := _get_mount_data(layout, mount_room, enemy["position"], candidate_rotation)
				if not _resolve_firing_mount(mount, target_position, weapon).is_empty():
					score += weapon_weight
		# Prefer the nearest equally useful bearing so ships do not reverse their
		# broadside selection every time two sampled headings tie.
		var reference_rotation := (
			Vector2.UP.angle_to(preferred_forward)
			if not preferred_forward.is_zero_approx()
			else float(enemy.get("rotation", 0.0))
		)
		score -= absf(angle_difference(reference_rotation, candidate_rotation)) * 0.035
		if score > best_score:
			best_score = score
			best_rotation = candidate_rotation
	return best_rotation


func _target_has_heavy_weapon_solution(target: Dictionary, threatened_position: Vector2) -> bool:
	var target_id := int(target.get("enemy_id", -1))
	if target_id < 0:
		return false
	var threat := _enemy_by_id(target_id)
	if threat.is_empty():
		return false
	var layout := threat.get("layout") as Resource
	if layout == null:
		return false
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "WEAPONS":
			continue
		var weapon := room.get("weapon_definition") as Resource
		if weapon == null or float(weapon.get("traverse_degrees")) >= 90.0:
			continue
		if float(weapon.get("damage")) < 12.0:
			continue
		for mount_index: int in range(_weapon_mount_count(room)):
			var mount := _get_mount_data(
				layout,
				_weapon_mount_room(room, mount_index),
				threat["position"],
				threat["rotation"]
			)
			if not _resolve_firing_mount(mount, threatened_position, weapon).is_empty():
				return true
	return false


func _layout_maximum_weapon_range(layout: Resource) -> float:
	var maximum := 420.0
	if layout == null:
		return maximum
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "WEAPONS":
			continue
		var weapon := room.get("weapon_definition") as Resource
		if weapon != null:
			maximum = maxf(maximum, float(weapon.get("maximum_range")))
	return maximum


func _civilian_route_velocity(enemy: Dictionary, current_position: Vector2, delta: float) -> Vector2:
	var route: Array = enemy.get("civilian_route", [])
	if route.is_empty():
		return Vector2.ZERO
	var dwell_remaining := maxf(float(enemy.get("civilian_dwell_remaining", 0.0)) - delta, 0.0)
	enemy["civilian_dwell_remaining"] = dwell_remaining
	if dwell_remaining > 0.0:
		return Vector2.ZERO
	var route_index := clampi(int(enemy.get("civilian_route_index", 0)), 0, route.size() - 1)
	var target: Vector2 = route[route_index]
	if current_position.distance_to(target) <= 34.0:
		enemy["civilian_dwell_remaining"] = float(enemy.get("civilian_waypoint_dwell", 3.0))
		var direction := int(enemy.get("civilian_route_direction", 1))
		var next_index := route_index + direction
		if next_index >= route.size() or next_index < 0:
			if bool(enemy.get("civilian_route_ping_pong", true)):
				direction *= -1
				enemy["civilian_route_direction"] = direction
				next_index = route_index + direction
			else:
				next_index = 0
		enemy["civilian_route_index"] = clampi(next_index, 0, route.size() - 1)
		return Vector2.ZERO
	var civilian_speed := float(enemy.get("civilian_speed", enemy_speed * 0.68))
	return current_position.direction_to(target) * civilian_speed


func _update_player_weapons(player: Node, delta: float) -> void:
	var layout: Resource = player.ship_layout
	var automatic_targets := _player_automatic_target_candidates()
	var primary_target := _nearest_enemy(player.ship_position, automatic_targets)
	var manual_target := _enemy_by_id(player.manual_target_enemy_id)
	for room: Resource in layout.get("rooms"):
		if room.get("type_name") != "WEAPONS":
			continue
		var room_id: StringName = room.get("room_id")
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		for mount_index: int in range(_weapon_mount_count(room)):
			var cooldown_key := _weapon_mount_cooldown_key(room_id, mount_index)
			var cooldown := maxf(float(player_weapon_cooldowns.get(cooldown_key, 0.0)) - delta, 0.0)
			player_weapon_cooldowns[cooldown_key] = cooldown
			if manual_fire_reservations.has(cooldown_key):
				continue
			var mount_efficiency := _player_weapon_mount_efficiency(player, room_id, mount_index)
			if cooldown > 0.0 or mount_efficiency <= 0.0:
				continue
			if not _weapon_mount_uses_automatic_fire(room, mount_index):
				continue
			var mount_room := _weapon_mount_room(room, mount_index)
			var mount := _get_mount_data(layout, mount_room, player.ship_position, player.ship_rotation)
			var target: Dictionary = {}
			var target_position := Vector2.ZERO
			var target_room_id: StringName = &""
			if player.targeting_doctrine == 2:
				if not player.manual_weapon_ids.has(room_id) or manual_target.is_empty():
					continue
				target = manual_target
				target_room_id = player.manual_target_room_id
				var enemy_layout: Resource = target.get("layout", layout)
				target_position = _get_room_world_center(enemy_layout, target_room_id, target["position"], target["rotation"])
			elif player.targeting_doctrine == 1:
				target = primary_target
			else:
				target = _nearest_valid_enemy(mount, weapon, automatic_targets)
			if target.is_empty():
				continue
			if target_position == Vector2.ZERO:
				target_position = target["position"]
			var firing_mount := _resolve_firing_mount(mount, target_position, weapon)
			if firing_mount.is_empty():
				continue
			if not _fire_projectile(firing_mount, target_position, weapon, ProjectileFaction.PLAYER, player.velocity, player.physics_body, target_room_id):
				continue
			var reload_time := float(weapon.get("reload_seconds")) / maxf(mount_efficiency, 0.1)
			player_weapon_cooldowns[cooldown_key] = reload_time
			_mark_weapon_fired(ProjectileFaction.PLAYER, 0, room_id, mount_index, reload_time)


func set_player_direct_fire_active(is_active: bool) -> void:
	player_direct_fire_active = is_active


func get_direct_fire_solution(player: Node, aim_direction: Vector2) -> Array[Dictionary]:
	var solution: Array[Dictionary] = []
	if not is_instance_valid(player) or player.ship_layout == null or aim_direction.is_zero_approx():
		return solution
	aim_direction = aim_direction.normalized()
	var battery_direction := _manual_battery_direction(float(player.ship_rotation), aim_direction)
	for room: Resource in player.ship_layout.get("rooms"):
		if room.get("type_name") != "WEAPONS":
			continue
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		var room_id: StringName = room.get("room_id")
		for mount_index: int in range(_weapon_mount_count(room)):
			if not _weapon_mount_accepts_manual_fire(room, mount_index):
				continue
			var mount_room := _weapon_mount_room(room, mount_index)
			var mount := _get_mount_data(player.ship_layout, mount_room, player.ship_position, player.ship_rotation)
			var firing_mount := _resolve_firing_mount_for_bearing(mount, battery_direction, aim_direction, weapon)
			var preview_mount := firing_mount if not firing_mount.is_empty() else _closest_preview_mount_for_bearing(mount, battery_direction)
			var visual_aim_direction := _closest_legal_mount_aim_direction(mount, aim_direction, weapon)
			if not firing_mount.is_empty():
				visual_aim_direction = firing_mount.get("fire_direction_override", visual_aim_direction)
			var cooldown_key := _weapon_mount_cooldown_key(room_id, mount_index)
			var status := &"BLOCKED"
			if _player_weapon_mount_efficiency(player, room_id, mount_index) <= 0.0:
				status = &"DISABLED"
			elif not firing_mount.is_empty():
				status = &"READY" if float(player_weapon_cooldowns.get(cooldown_key, 0.0)) <= 0.0 and not manual_fire_reservations.has(cooldown_key) else &"RELOADING"
			solution.append({
				"room_id": room_id,
				"mount_index": mount_index,
				"position": preview_mount.get("position", mount.get("position", player.ship_position)),
				"aim_direction": visual_aim_direction,
				"status": status,
				"battery_member": not firing_mount.is_empty(),
				"cooldown": float(player_weapon_cooldowns.get(cooldown_key, 0.0)),
			})
	return solution


func fire_direct_volley(player: Node, aim_direction: Vector2) -> int:
	if not is_instance_valid(player) or player.ship_layout == null or aim_direction.is_zero_approx():
		return 0
	aim_direction = aim_direction.normalized()
	var battery_direction := _manual_battery_direction(float(player.ship_rotation), aim_direction)
	var eligible_mounts: Array[Dictionary] = []
	var ship_forward := Vector2.UP.rotated(float(player.ship_rotation))
	for room: Resource in player.ship_layout.get("rooms"):
		if room.get("type_name") != "WEAPONS":
			continue
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		var room_id: StringName = room.get("room_id")
		for mount_index: int in range(_weapon_mount_count(room)):
			if not _weapon_mount_accepts_manual_fire(room, mount_index):
				continue
			var cooldown_key := _weapon_mount_cooldown_key(room_id, mount_index)
			if manual_fire_reservations.has(cooldown_key):
				continue
			var mount_efficiency := _player_weapon_mount_efficiency(player, room_id, mount_index)
			if float(player_weapon_cooldowns.get(cooldown_key, 0.0)) > 0.0 or mount_efficiency <= 0.0:
				continue
			var mount_room := _weapon_mount_room(room, mount_index)
			var mount := _get_mount_data(player.ship_layout, mount_room, player.ship_position, player.ship_rotation)
			var firing_mount := _resolve_firing_mount_for_bearing(mount, battery_direction, aim_direction, weapon)
			if firing_mount.is_empty():
				continue
			eligible_mounts.append({
				"player": player,
				"room": room,
				"room_id": room_id,
				"mount_index": mount_index,
				"cooldown_key": cooldown_key,
				"aim_direction": aim_direction,
				"bow_order": (Vector2(firing_mount["position"]) - Vector2(player.ship_position)).dot(ship_forward),
			})
	eligible_mounts.sort_custom(weapon_firing_order_before)
	if eligible_mounts.is_empty():
		return 0
	var sequence_start := manual_fire_clock
	if not pending_manual_fire.is_empty():
		sequence_start = maxf(sequence_start, float(pending_manual_fire.back()["ready_at"]) + manual_volley_mount_interval)
	var scheduled_count := eligible_mounts.size()
	for entry_index: int in range(eligible_mounts.size()):
		var entry := eligible_mounts[entry_index]
		var cooldown_key: String = entry["cooldown_key"]
		manual_fire_reservations[cooldown_key] = true
		if entry_index == 0 and pending_manual_fire.is_empty():
			_execute_manual_fire_entry(entry)
			continue
		entry["ready_at"] = sequence_start + float(entry_index) * manual_volley_mount_interval
		pending_manual_fire.append(entry)
	return scheduled_count


func weapon_firing_order_before(a: Dictionary, b: Dictionary) -> bool:
	var a_order := float(a["bow_order"])
	var b_order := float(b["bow_order"])
	if not is_equal_approx(a_order, b_order):
		return a_order > b_order
	if String(a["room_id"]) != String(b["room_id"]):
		return String(a["room_id"]) < String(b["room_id"])
	return int(a["mount_index"]) < int(b["mount_index"])


func _update_manual_fire_sequence() -> void:
	if pending_manual_fire.is_empty():
		return
	# Fire at most one queued mount per physics tick. Even after a slow frame,
	# individual shells remain visibly staggered instead of collapsing together.
	var entry: Dictionary = pending_manual_fire.front()
	if manual_fire_clock < float(entry["ready_at"]):
		return
	pending_manual_fire.pop_front()
	_execute_manual_fire_entry(entry)


func _execute_manual_fire_entry(entry: Dictionary) -> bool:
	var cooldown_key := String(entry.get("cooldown_key", ""))
	manual_fire_reservations.erase(cooldown_key)
	var player := entry.get("player") as Node
	var room := entry.get("room") as Resource
	if not is_instance_valid(player) or room == null or player.ship_layout == null:
		return false
	var room_id: StringName = entry["room_id"]
	var mount_index := int(entry["mount_index"])
	var mount_efficiency := _player_weapon_mount_efficiency(player, room_id, mount_index)
	if mount_efficiency <= 0.0:
		return false
	var weapon: Resource = room.get("weapon_definition")
	if weapon == null:
		return false
	var aim_direction: Vector2 = entry["aim_direction"]
	var battery_direction := _manual_battery_direction(float(player.ship_rotation), aim_direction)
	var mount_room := _weapon_mount_room(room, mount_index)
	var mount := _get_mount_data(player.ship_layout, mount_room, player.ship_position, player.ship_rotation)
	var firing_mount := _resolve_firing_mount_for_bearing(mount, battery_direction, aim_direction, weapon)
	if firing_mount.is_empty():
		return false
	var projectile_direction: Vector2 = firing_mount.get("fire_direction_override", aim_direction)
	var target_position := Vector2(firing_mount["position"]) + projectile_direction * float(weapon.get("maximum_range"))
	if not _fire_projectile(firing_mount, target_position, weapon, ProjectileFaction.PLAYER, player.velocity, player.physics_body):
		return false
	var reload_time := float(weapon.get("reload_seconds")) / maxf(mount_efficiency, 0.1)
	player_weapon_cooldowns[cooldown_key] = reload_time
	_mark_weapon_fired(ProjectileFaction.PLAYER, 0, room_id, mount_index, reload_time)
	return true


func _update_enemy_weapons(enemy: Dictionary, target: Dictionary, delta: float) -> void:
	var layout := enemy.get("layout") as Resource
	if layout == null:
		return
	var target_position: Vector2 = target.get("position", enemy["position"])
	var combat_faction := int(enemy.get("combat_faction", ProjectileFaction.ENEMY))
	var enemy_body := enemy.get("physics_body") as RigidBody2D
	if is_instance_valid(enemy_body):
		combat_faction = int(enemy_body.get_meta("ship_faction", combat_faction))
	var cooldowns: Dictionary = enemy["weapon_cooldowns"]
	for room: Resource in layout.get("rooms"):
		if room.get("type_name") != "WEAPONS":
			continue
		var room_id: StringName = room.get("room_id")
		var power_factor := float((enemy.get("room_power_factors", {}) as Dictionary).get(room_id, 0.0))
		if power_factor <= 0.001:
			continue
		var required_crew := int(ROOM_STAFFING_RULES.effective_requirements(
			room,
			int(room.get("minimum_crew")),
			int(room.get("optimal_crew"))
		).y)
		var crew_factor := 1.0
		if required_crew > 0:
			var available_crew := int(enemy.get("healthy_crew_count", enemy.get("crew_count", 0)))
			var total_required := maxi(int(enemy.get("optimal_crew", required_crew)), required_crew)
			crew_factor = clampf(float(available_crew) / float(total_required), 0.0, 1.0)
		if crew_factor <= 0.001:
			continue
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		for mount_index: int in range(_weapon_mount_count(room)):
			var cooldown_key := _weapon_mount_cooldown_key(room_id, mount_index)
			var cooldown := maxf(float(cooldowns.get(cooldown_key, 0.0)) - delta, 0.0)
			cooldowns[cooldown_key] = cooldown
			if cooldown > 0.0:
				continue
			var mount_room := _weapon_mount_room(room, mount_index)
			var mount := _get_mount_data(layout, mount_room, enemy["position"], enemy["rotation"])
			var firing_mount := _resolve_firing_mount(mount, target_position, weapon)
			if firing_mount.is_empty():
				continue
			if not _fire_projectile(firing_mount, target_position, weapon, combat_faction, enemy["velocity"], enemy_body):
				continue
			var operating_factor := maxf(minf(power_factor, crew_factor), 0.1)
			var reload_time: float = float(weapon.get("reload_seconds")) / (_weapon_room_group_bonus(room) * operating_factor)
			cooldowns[cooldown_key] = reload_time
			_mark_weapon_fired(combat_faction, int(enemy["id"]), room_id, mount_index, reload_time)
			# Large batteries used to release every ready mount in one physics frame.
			# Besides looking unnaturally synchronized, that produced a large burst of
			# projectile, audio, and impact work. One shot per ship per tick preserves
			# the full rate of fire while spreading a broadside over a few frames.
			enemy["weapon_cooldowns"] = cooldowns
			return
	enemy["weapon_cooldowns"] = cooldowns


## Rebuilds operating state from the same reactor-field and staffing rules used
## by the Shipyard. Destroyed reactor grids stop covering station services and
## weapons; an unmanned station can remain physically present but cannot work.
func _refresh_enemy_blueprint_operations(enemy: Dictionary) -> void:
	var layout := enemy.get("layout") as Resource
	if layout == null:
		return
	var room_damage: Dictionary = enemy.get("room_damage", {})
	var generator_factors: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) not in ["POWER", "REACTOR", "ENGINE"]:
			continue
		var room_id: StringName = room.get("room_id")
		var maximum_health := maxf(float(room.get("maximum_health")), 1.0)
		generator_factors[room_id] = clampf(
			1.0 - float(room_damage.get(room_id, 0.0)) / maximum_health,
			0.0,
			1.0
		)
	var power_report: Dictionary = SHIP_BUILDER_ANALYZER.power_network_report(layout, generator_factors)
	enemy["room_power_factors"] = power_report.get("room_factors", {})

	var essential_crew := 0
	var essential_power := 1.0
	var room_factors: Dictionary = enemy["room_power_factors"]
	for room: Resource in layout.get("rooms"):
		var room_type := String(room.get("type_name"))
		if room_type not in ["COMMAND", "BRIDGE", "POWER", "REACTOR", "ENGINE", "DOCKING"]:
			continue
		var staffing := ROOM_STAFFING_RULES.effective_requirements(
			room,
			int(room.get("minimum_crew")),
			int(room.get("optimal_crew"))
		)
		essential_crew += staffing.x
		if room_type in ["COMMAND", "BRIDGE", "DOCKING"]:
			essential_power = minf(
				essential_power,
				float(room_factors.get(room.get("room_id"), 0.0))
			)
	var healthy_crew := int(enemy.get("healthy_crew_count", enemy.get("crew_count", 0)))
	var crew_ready := healthy_crew >= essential_crew
	var shield_weight := 0.0
	var working_shield_weight := 0.0
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "SHIELDS":
			continue
		var room_id: StringName = room.get("room_id")
		var maximum_health := maxf(float(room.get("maximum_health")), 1.0)
		var health_factor := clampf(
			1.0 - float(room_damage.get(room_id, 0.0)) / maximum_health,
			0.0,
			1.0
		)
		var cell_weight := 0.0
		for rect: Rect2i in room.get("grid_rects"):
			cell_weight += float(rect.size.x * rect.size.y)
		cell_weight = maxf(cell_weight, 1.0)
		shield_weight += cell_weight
		working_shield_weight += cell_weight * minf(
			health_factor,
			float(room_factors.get(room_id, 0.0))
		)
	var shield_factor := (
		clampf(working_shield_weight / shield_weight, 0.0, 1.0)
		if shield_weight > 0.0
		else 0.0
	)
	enemy["shield_operating_factor"] = shield_factor
	enemy["station_operational"] = essential_power >= 0.999 and crew_ready
	enemy["station_power_factor"] = essential_power
	enemy["station_required_crew"] = essential_crew


func _fire_projectile(mount: Dictionary, target_position: Vector2, weapon: Resource, faction: int, inherited_velocity: Vector2, shooter_body: RigidBody2D, target_room_id: StringName = &"") -> bool:
	if faction == ProjectileFaction.PLAYER:
		var weapon_noise := clampf(0.05 + float(weapon.get("damage")) * 0.002, 0.05, 0.24)
		player_weapon_fired.emit(weapon_noise)
	var mount_position: Vector2 = mount["position"]
	var to_target: Vector2 = (target_position - mount_position).normalized()
	var traverse: float = weapon.get("traverse_degrees")
	var default_fire_direction: Vector2 = to_target if traverse > 0.0 else mount["direction"]
	var fire_direction: Vector2 = mount.get("fire_direction_override", default_fire_direction)
	# Aim the scene before reading its Marker2D. The projectile's center then
	# starts at the visible muzzle for manual and automatic fire alike.
	var shooter_ship_id := int(shooter_body.get_meta("ship_id", 0)) if is_instance_valid(shooter_body) else 0
	_notify_weapon_mount_aim(faction, shooter_ship_id, mount, fire_direction, true)
	var spawn_position := _projectile_spawn_position(mount, fire_direction)
	var live_muzzle_position: Variant = _live_weapon_muzzle_position(
		faction, shooter_ship_id, mount, shooter_body
	)
	if live_muzzle_position is Vector2:
		spawn_position = live_muzzle_position
	var dispersion := deg_to_rad(float(weapon.get("accuracy_degrees")))
	if dispersion > 0.0:
		fire_direction = fire_direction.rotated(randf_range(-dispersion, dispersion))
	var projectile_velocity := fire_direction * float(weapon.get("projectile_speed")) + inherited_velocity
	var projectile_id := next_projectile_id
	next_projectile_id += 1
	var physics_world := get_tree().get_first_node_in_group("physics_world")
	if not is_instance_valid(physics_world):
		return false
	var authored_projectile_mass := float(weapon.get("projectile_mass"))
	var collision_mass := (
		maxf(authored_projectile_mass * projectile_knockback_mass_scale, 0.001)
		if projectile_knockback_mass_scale > 0.0
		else 0.001
	)
	var physics_projectile := _acquire_projectile_body(physics_world)
	physics_projectile.call(
		"configure_projectile",
		float(weapon.get("projectile_collision_radius")),
		collision_mass,
		float(weapon.get("projectile_bounce"))
	)
	physics_projectile.call(
		"activate_projectile",
		projectile_id,
		spawn_position,
		fire_direction.angle(),
		projectile_velocity
	)
	for ship_value: Variant in get_tree().get_nodes_in_group("physics_ships"):
		var ship_body := ship_value as RigidBody2D
		if is_instance_valid(ship_body) and int(ship_body.get_meta("ship_faction", -1)) == faction:
			physics_projectile.call("add_projectile_collision_exception", ship_body)
	for fighter_value: Variant in get_tree().get_nodes_in_group("autonomous_fighters"):
		var friendly_fighter := fighter_value as RigidBody2D
		if is_instance_valid(friendly_fighter) and int(friendly_fighter.get_meta("ship_faction", -1)) == faction:
			physics_projectile.call("add_projectile_collision_exception", friendly_fighter)
	projectiles.append({
		"id": projectile_id,
		"position": spawn_position,
		"previous_position": spawn_position,
		"travelled_distance": 0.0,
		"velocity": projectile_velocity,
		"damage": weapon.get("damage"),
		"shield_damage_multiplier": weapon.get("shield_damage_multiplier"),
		"hull_damage_multiplier": weapon.get("hull_damage_multiplier"),
		"system_damage_multiplier": weapon.get("system_damage_multiplier"),
		"breach_damage_multiplier": weapon.get("breach_damage_multiplier"),
		"fighter_damage_multiplier": weapon.get("fighter_damage_multiplier"),
		"ion_disruption_seconds": weapon.get("ion_disruption_seconds"),
		"penetration_power": weapon.get("penetration_power"),
		"remaining_range": weapon.get("maximum_range"),
		"faction": faction,
		"visual_scene": weapon.get("projectile_scene"),
		"impact_color": weapon.get("visual_color"),
		"impact_effect_scene": weapon.get("impact_effect_scene"),
		"weapon_family": weapon.get("weapon_family"),
		"damage_type": weapon.get("damage_type"),
		"impact_debris_definition": weapon.get("impact_debris_definition"),
		"impact_sound": weapon.get("impact_sound"),
		"impact_volume_db": weapon.get("impact_volume_db"),
		"impact_pitch_variation": weapon.get("impact_pitch_variation"),
		"blast_radius": weapon.get("blast_radius"),
		"impacted": false,
		"impact_linger": 0.0,
		"target_room_id": target_room_id,
		"physics_body": physics_projectile,
	})
	_play_optional_firing_sound(weapon, spawn_position)
	return true


func _acquire_projectile_body(physics_world: Node) -> RigidBody2D:
	var body: RigidBody2D
	if not projectile_body_pool.is_empty():
		body = projectile_body_pool.pop_back()
	else:
		body = PHYSICS_PROJECTILE_SCENE.instantiate() as RigidBody2D
		physics_world.add_child(body)
		body.connect("impact_detected", _on_physical_projectile_impact)
	return body


func _release_projectile_body(body: RigidBody2D) -> void:
	if not is_instance_valid(body):
		return
	body.call("prepare_for_pool")
	if projectile_body_pool.size() < maximum_pooled_projectiles:
		projectile_body_pool.append(body)
	else:
		body.queue_free()


## The projectile's travel direction and its physical exit point are deliberately
## separate. A traversing/innaccurate shot may leave at an angle, but it must
## always begin at the visible end of the authored barrel rather than sliding
## around the mount as aim and dispersion change.
func _projectile_spawn_position(mount: Dictionary, fire_direction: Vector2) -> Vector2:
	# Authored weapon scenes own the firing socket.  Keep the final world-space
	# point authoritative all the way through target/mount resolution instead of
	# reconstructing it from whichever coverage candidate happened to win.
	var authored_position: Variant = mount.get("muzzle_position")
	if authored_position is Vector2:
		return Vector2(authored_position)
	var authored_offset: Variant = mount.get("muzzle_offset")
	if authored_offset is Vector2:
		return Vector2(mount["position"]) + Vector2(authored_offset)
	var muzzle_clearance := float(mount.get("muzzle_clearance", 16.0))
	var muzzle_direction: Vector2 = mount.get("muzzle_direction", fire_direction)
	if muzzle_direction.is_zero_approx():
		muzzle_direction = fire_direction
	return Vector2(mount["position"]) + muzzle_direction.normalized() * muzzle_clearance


## The player's rendered weapon scene is authoritative for its barrel tip.
## This deliberately bypasses all room-center and hull-edge approximations.
## Calculated sockets remain as a safe fallback for simulations without a live
## view (headless tests and distant NPCs).
func _live_weapon_muzzle_position(
		faction: int,
		ship_id: int,
		mount: Dictionary,
		shooter_body: RigidBody2D
) -> Variant:
	if not is_instance_valid(shooter_body):
		return null
	var room_id := StringName(mount.get("room_id", &""))
	var mount_index := int(mount.get("mount_index", -1))
	if room_id == &"" or mount_index < 0:
		return null
	for provider_value: Variant in get_tree().get_nodes_in_group("weapon_mount_visual_provider"):
		var provider := provider_value as Node
		if (
			not is_instance_valid(provider)
			or not provider.has_method("matches_weapon_mount_identity")
			or not bool(provider.call("matches_weapon_mount_identity", faction, ship_id))
			or not provider.has_method("get_weapon_muzzle_ship_local_position")
		):
			continue
		var ship_local_position: Variant = provider.call(
			"get_weapon_muzzle_ship_local_position", room_id, mount_index
		)
		if ship_local_position is Vector2:
			return shooter_body.global_position + Vector2(ship_local_position).rotated(
				shooter_body.global_rotation
			)
	return null


func _notify_weapon_mount_aim(
		faction: int,
		ship_id: int,
		mount: Dictionary,
		world_direction: Vector2,
		play_fire_animation: bool
) -> void:
	var room_id := StringName(mount.get("room_id", &""))
	var mount_index := int(mount.get("mount_index", -1))
	if room_id == &"" or mount_index < 0 or world_direction.is_zero_approx():
		return
	for provider_value: Variant in get_tree().get_nodes_in_group("weapon_mount_visual_provider"):
		var provider := provider_value as Node
		if (
			not is_instance_valid(provider)
			or not provider.has_method("matches_weapon_mount_identity")
			or not bool(provider.call("matches_weapon_mount_identity", faction, ship_id))
			or not provider.has_method("aim_weapon_mount_world_direction")
		):
			continue
		provider.call(
			"aim_weapon_mount_world_direction",
			room_id,
			mount_index,
			world_direction,
			play_fire_animation
		)


func _play_optional_firing_sound(weapon: Resource, world_position: Vector2) -> void:
	var sound := weapon.get("firing_sound") as AudioStream
	if sound == null:
		return
	_play_world_sound(
		sound,
		world_position,
		float(weapon.get("firing_volume_db")),
		float(weapon.get("firing_pitch_variation"))
	)


func _play_world_sound(
	stream: AudioStream,
	world_position: Vector2,
	base_volume_db := 0.0,
	pitch_variation := 0.0
) -> AudioStreamPlayer2D:
	if stream == null:
		return null
	var physics_world := get_tree().get_first_node_in_group("physics_world") as Node2D
	if not is_instance_valid(physics_world):
		return null
	# At fleet scale many identical reports occur in the same audible instant.
	# A voice budget preserves the mix without allocating hundreds of nodes.
	if active_world_audio_players.size() >= maximum_world_audio_voices:
		return null
	var player: AudioStreamPlayer2D
	if not world_audio_player_pool.is_empty():
		player = world_audio_player_pool.pop_back()
	else:
		player = AudioStreamPlayer2D.new()
		physics_world.add_child(player)
		player.finished.connect(_on_world_audio_finished.bind(player))
	player.stream = stream
	player.max_distance = world_audio_max_distance
	player.attenuation = world_audio_attenuation
	player.volume_db = base_volume_db + _world_audio_zoom_volume_db()
	if pitch_variation > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.global_position = world_position
	active_world_audio_players.append(player)
	player.play()
	return player


func _on_world_audio_finished(player: AudioStreamPlayer2D) -> void:
	active_world_audio_players.erase(player)
	if not is_instance_valid(player):
		return
	player.stop()
	player.stream = null
	world_audio_player_pool.append(player)


func _world_audio_zoom_volume_db() -> float:
	var zoom_ratio := inverse_lerp(world_audio_minimum_zoom, world_audio_maximum_zoom, tactical_audio_zoom)
	return lerpf(
		world_audio_zoomed_out_db,
		world_audio_zoomed_in_db,
		smoothstep(0.0, 1.0, clampf(zoom_ratio, 0.0, 1.0))
	)


func _ensure_tactical_audio_listener() -> void:
	if is_instance_valid(tactical_audio_listener):
		return
	var physics_world := get_tree().get_first_node_in_group("physics_world") as Node2D
	if not is_instance_valid(physics_world):
		return
	tactical_audio_listener = AudioListener2D.new()
	tactical_audio_listener.name = "TacticalAudioListener"
	physics_world.add_child(tactical_audio_listener)
	tactical_audio_listener.make_current()


func _update_tactical_audio_listener(world_position: Vector2) -> void:
	if not is_instance_valid(tactical_audio_listener):
		_ensure_tactical_audio_listener()
	if is_instance_valid(tactical_audio_listener):
		tactical_audio_listener.global_position = world_position


func _play_enemy_destruction_sound(enemy: Dictionary) -> void:
	var body := enemy.get("physics_body") as RigidBody2D
	var world_position: Vector2 = enemy.get("position", Vector2.ZERO)
	var cell_count: int = int(body.call("get_hull_cell_count")) if is_instance_valid(body) and body.has_method("get_hull_cell_count") else 0
	var is_large: bool = bool(enemy.get("stationary", false)) or cell_count >= 12
	_play_world_sound(
		large_explosion_sound if is_large else medium_explosion_sound,
		world_position,
		1.0 if is_large else -1.0,
		0.045
	)


func _begin_enemy_destruction(enemy: Dictionary) -> void:
	enemy["destruction_active"] = true
	enemy["destruction_remaining"] = ship_destruction_sequence_seconds
	enemy["destruction_burst_clock"] = 0.0
	enemy["destruction_burst_index"] = 0
	enemy["combat_active"] = false
	enemy["player_targetable"] = false
	enemy["defense_alert"] = false
	enemy["station_operational"] = false
	_cancel_enemy_docking_clearance(enemy)
	var body := enemy.get("physics_body") as RigidBody2D
	if is_instance_valid(body):
		body.set_meta("destruction_active", true)
		if body.has_method("set_coast_command"):
			body.call("set_coast_command")
		if not bool(enemy.get("stationary", false)) and absf(body.angular_velocity) < 0.08:
			body.angular_velocity = randf_range(-0.16, 0.16)


func _sync_doomed_enemy_transform(enemy: Dictionary) -> void:
	var body := enemy.get("physics_body") as RigidBody2D
	if not is_instance_valid(body):
		return
	enemy["position"] = body.global_position
	enemy["rotation"] = body.global_rotation
	enemy["velocity"] = body.linear_velocity
	if body.has_method("set_coast_command"):
		body.call("set_coast_command")


func _update_enemy_destruction(enemy: Dictionary, delta: float) -> bool:
	_sync_doomed_enemy_transform(enemy)
	var remaining := maxf(float(enemy.get("destruction_remaining", 0.0)) - delta, 0.0)
	var burst_clock := float(enemy.get("destruction_burst_clock", 0.0)) - delta
	var burst_index := int(enemy.get("destruction_burst_index", 0))
	if burst_clock <= 0.0 and remaining > 0.0:
		var body := enemy.get("physics_body") as RigidBody2D
		_spawn_ship_destruction_burst(body, enemy.get("layout") as Resource, burst_index)
		if burst_index % 2 == 0 and is_instance_valid(body):
			_play_world_sound(small_explosion_sound, body.global_position, -5.0, 0.08)
		burst_index += 1
		burst_clock = ship_destruction_burst_interval
	enemy["destruction_remaining"] = remaining
	enemy["destruction_burst_clock"] = burst_clock
	enemy["destruction_burst_index"] = burst_index
	return remaining <= 0.0


func _finalize_enemy_destruction(index: int, player: Node) -> void:
	var enemy: Dictionary = enemies[index]
	_report_neutral_contact_destroyed(enemy)
	_play_enemy_destruction_sound(enemy)
	_spawn_destroyed_ship_grid_salvage(enemy)
	var destroyed_body := enemy.get("physics_body") as RigidBody2D
	if is_instance_valid(destroyed_body):
		_spawn_ship_destruction_burst(destroyed_body, enemy.get("layout") as Resource, int(enemy.get("destruction_burst_index", 0)), true)
		_spawn_ship_destruction_fragments(destroyed_body, enemy.get("layout", player.ship_layout))
		registered_physics_ships.erase(destroyed_body.get_instance_id())
	var destroyed_instance := enemy.get("instance") as Node
	if is_instance_valid(destroyed_instance):
		destroyed_instance.call("destroy")
	elif is_instance_valid(destroyed_body):
		destroyed_body.queue_free()
	enemies.remove_at(index)


func _spawn_ship_destruction_burst(
	ship_body: RigidBody2D,
	layout: Resource,
	burst_index: int,
	heavy: bool = false
) -> void:
	if not is_instance_valid(ship_body) or layout == null:
		return
	var occupied_cells: Array = _layout_cells(layout).keys()
	var local_point := Vector2.ZERO
	if not occupied_cells.is_empty():
		var bounds: Rect2i = layout.call("get_occupied_bounds")
		var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
		var cell: Vector2i = occupied_cells[randi() % occupied_cells.size()]
		local_point = (
			GRID_GEOMETRY.cell_rect(layout, cell, bounds, TACTICAL_CELL_SIZE).get_center()
			- geometry_size * 0.5
			+ Vector2(randf_range(-3.2, 3.2), randf_range(-3.2, 3.2))
		)
	var outward_normal := local_point.normalized().rotated(ship_body.global_rotation)
	if outward_normal.is_zero_approx():
		outward_normal = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var effect_scene := (
		SHIP_DESTRUCTION_HEAVY_SCENE
		if heavy or burst_index % 4 == 3
		else SHIP_DESTRUCTION_SMALL_SCENE
	)
	_request_impact_sprite(
		ship_body,
		ship_body.to_global(local_point),
		outward_normal,
		Color(1.0, 0.42, 0.12, 1.0),
		effect_scene
	)


func _weapon_operation_key(faction: int, carrier_id: int, room_id: StringName, mount_index: int) -> String:
	return "%d:%d:%s:%d" % [faction, carrier_id, String(room_id), mount_index]


func _mark_weapon_fired(faction: int, carrier_id: int, room_id: StringName, mount_index: int, reload_time: float) -> void:
	var key := _weapon_operation_key(faction, carrier_id, room_id, mount_index)
	weapon_operation_states[key] = {
		"state": "FIRING",
		"fire_pulse": 0.16,
		"reload_remaining": reload_time,
		"reload_total": reload_time,
	}


func _update_weapon_operation_states(delta: float) -> void:
	for key_value: Variant in weapon_operation_states.keys():
		var state: Dictionary = weapon_operation_states[key_value]
		state["fire_pulse"] = maxf(float(state.get("fire_pulse", 0.0)) - delta, 0.0)
		state["reload_remaining"] = maxf(float(state.get("reload_remaining", 0.0)) - delta, 0.0)
		if float(state["fire_pulse"]) > 0.0:
			state["state"] = "FIRING"
		elif float(state["reload_remaining"]) > 0.0:
			state["state"] = "RELOADING"
		else:
			state["state"] = "READY"


func get_weapon_operation_state(faction: int, carrier_id: int, room_id: StringName, mount_index: int = 0) -> Dictionary:
	var key := _weapon_operation_key(faction, carrier_id, room_id, mount_index)
	return weapon_operation_states.get(key, {"state": "READY", "fire_pulse": 0.0, "reload_remaining": 0.0, "reload_total": 0.0})


func get_structural_state(faction: int, ship_id: int) -> ShipStructuralState:
	if faction == ProjectileFaction.PLAYER:
		var player := get_tree().get_first_node_in_group("ship_simulation")
		return player.structural_state if is_instance_valid(player) else null
	var enemy := _enemy_by_id(ship_id)
	return enemy.get("structural_state") as ShipStructuralState if not enemy.is_empty() else null


func set_tactical_audio_zoom(zoom_level: float) -> void:
	tactical_audio_zoom = maxf(zoom_level, 0.01)


func _update_projectiles(player: Node, delta: float) -> void:
	for index: int in range(projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = projectiles[index]
		var physics_body := projectile.get("physics_body") as RigidBody2D
		if projectile["impacted"]:
			projectile["impact_linger"] = float(projectile["impact_linger"]) - delta
			if float(projectile["impact_linger"]) <= 0.0:
				if is_instance_valid(physics_body):
					_release_projectile_body(physics_body)
				projectiles.remove_at(index)
			continue
		if not is_instance_valid(physics_body):
			projectiles.remove_at(index)
			continue
		projectile["previous_position"] = projectile["position"]
		var previous_position: Vector2 = projectile["previous_position"]
		projectile["position"] = physics_body.global_position
		projectile["velocity"] = physics_body.linear_velocity
		var travelled_step := previous_position.distance_to(physics_body.global_position)
		projectile["travelled_distance"] = float(projectile.get("travelled_distance", 0.0)) + travelled_step
		projectile["remaining_range"] = float(projectile["remaining_range"]) - travelled_step
		if float(projectile["remaining_range"]) <= 0.0:
			_release_projectile_body(physics_body)
			projectiles.remove_at(index)


func _on_physical_projectile_impact(
	physics_projectile: RigidBody2D,
	collider: RigidBody2D,
	point: Vector2,
	normal: Vector2,
	incoming_velocity: Vector2,
	projectile_id: int
) -> void:
	for projectile: Dictionary in projectiles:
		if int(projectile["id"]) != projectile_id or projectile["impacted"]:
			continue
		var faction: int = projectile["faction"]
		var collider_faction := int(collider.get_meta("ship_faction", -1))
		if collider_faction == faction:
			return
		var relative_impact_velocity := incoming_velocity - collider.linear_velocity
		# Preserve the contacted surface normal. The old fallback replaced it with
		# the reverse shot direction, so impact effects could not react to the angle
		# of the hull. Only flip the reported normal when it faces into the surface.
		var incoming_direction := relative_impact_velocity.normalized()
		if normal.length_squared() <= 0.0001:
			normal = -incoming_direction
		else:
			normal = normal.normalized()
			if not incoming_direction.is_zero_approx() and normal.dot(incoming_direction) > 0.0:
				normal = -normal
		var absorbed_damage := 0.0
		var unshielded_damage := float(projectile["damage"])
		var catastrophic_breach := false
		var impact_room_id: StringName = collider.call("get_room_id_nearest_world_point", point) if collider.has_method("get_room_id_nearest_world_point") else &""
		var impact_cell := (
			Vector2i(collider.call("get_cell_nearest_world_point", point))
			if collider.has_method("get_cell_nearest_world_point")
			else Vector2i(2147483647, 2147483647)
		)
		if collider.is_in_group("asteroids") and collider.has_method("apply_projectile_damage"):
			collider.call("apply_projectile_damage", float(projectile["damage"]))
		elif bool(collider.get_meta("is_fighter", false)):
			collider.call(
				"apply_damage",
				float(projectile["damage"]) * float(projectile["fighter_damage_multiplier"])
			)
		elif collider_faction != ProjectileFaction.PLAYER:
			var enemy := _enemy_by_id(int(collider.get_meta("ship_id", -1)))
			if not enemy.is_empty():
				var enemy_damage_report := _apply_damage_to_enemy(enemy, projectile, impact_room_id, point - Vector2(enemy["position"]))
				absorbed_damage = float(enemy_damage_report["shield_absorbed"])
				unshielded_damage = float(enemy_damage_report["hull_damage"])
		else:
			var player := get_tree().get_first_node_in_group("ship_simulation")
			if is_instance_valid(player):
				var shield_direction: Vector2 = point - Vector2(player.ship_position)
				var damage_report: Dictionary = player.apply_combat_damage(
					float(projectile["damage"]),
					impact_room_id,
					shield_direction,
					float(projectile["shield_damage_multiplier"]),
					float(projectile["hull_damage_multiplier"]),
					float(projectile["system_damage_multiplier"]),
					float(projectile["breach_damage_multiplier"]),
					impact_cell,
					float(projectile.get("ion_disruption_seconds", 0.0))
				)
				absorbed_damage = float(damage_report["shield_absorbed"])
				unshielded_damage = float(damage_report["hull_damage"])
				catastrophic_breach = bool(damage_report.get("breached", false))
				_destroy_player_ship_if_needed(player)
		if unshielded_damage > 0.0 and not bool(collider.get_meta("is_fighter", false)) and (collider_faction != ProjectileFaction.PLAYER or catastrophic_breach):
			var structure_value: Variant = (
				collider.get_meta("structural_state")
				if collider.has_meta("structural_state")
				else null
			)
			if structure_value is ShipStructuralState:
				var structure := structure_value as ShipStructuralState
				var impact_direction := relative_impact_velocity.normalized()
				var local_direction := collider.to_local(point + impact_direction) - collider.to_local(point)
				var penetration_fraction := unshielded_damage / maxf(float(projectile["damage"]), 0.001)
				structure.trace_penetration(
					collider.to_local(point),
					local_direction,
					float(projectile["penetration_power"]) * penetration_fraction,
					TACTICAL_CELL_SIZE
				)
		var shield_hit := absorbed_damage > 0.0
		var shield_standoff := _shield_impact_standoff_for(collider) if shield_hit else 0.0
		var visual_impact_point := point + normal * shield_standoff if shield_hit else point
		projectile["position"] = visual_impact_point
		projectile["previous_position"] = visual_impact_point
		projectile["impact_normal"] = normal
		projectile["impact_velocity"] = incoming_velocity
		projectile["impact_surface_velocity"] = collider.linear_velocity
		projectile["velocity"] = incoming_velocity
		projectile["impacted"] = true
		projectile["impact_linger"] = projectile_impact_linger
		_play_optional_impact_sound(projectile, visual_impact_point)
		if shield_hit:
			shield_impact_detected.emit(
				collider,
				visual_impact_point,
				normal,
				clampf(absorbed_damage / maxf(float(projectile["damage"]), 0.001), 0.25, 1.0)
			)
		_request_impact_sprite(
			collider,
			visual_impact_point,
			normal,
			projectile["impact_color"],
			projectile.get("impact_effect_scene") as PackedScene
		)
		physics_projectile.call("stop_after_impact")
		return


func _play_optional_impact_sound(projectile: Dictionary, world_position: Vector2) -> void:
	var sound := projectile.get("impact_sound") as AudioStream
	if sound == null:
		return
	_play_world_sound(
		sound,
		world_position,
		float(projectile.get("impact_volume_db", 0.0)),
		float(projectile.get("impact_pitch_variation", 0.0))
	)


func _shield_impact_standoff_for(collider: RigidBody2D) -> float:
	var faction := int(collider.get_meta("ship_faction", -1))
	var ship_view := get_tree().get_first_node_in_group("ship_view")
	if not is_instance_valid(ship_view):
		return 5.0
	var visual: Control
	if faction == ProjectileFaction.PLAYER:
		var player_shield := ship_view.get("shield_visual") as Control
		if is_instance_valid(player_shield):
			return float(player_shield.get("impact_standoff"))
		visual = ship_view.get("ship_visual") as Control
	else:
		var visuals: Dictionary = ship_view.get("enemy_visuals")
		visual = visuals.get(int(collider.get_meta("ship_id", -1))) as Control
	if not is_instance_valid(visual):
		return 5.0
	var shield := visual.get_node_or_null("ShieldVisual")
	return float(shield.get("impact_standoff")) if is_instance_valid(shield) else 5.0


func _request_impact_sprite(
	collider: RigidBody2D,
	point: Vector2,
	outward_normal: Vector2,
	impact_color: Color,
	impact_scene: PackedScene = null
) -> void:
	if not is_instance_valid(collider):
		return
	impact_effect_requested.emit(collider, point, outward_normal.normalized(), impact_color, impact_scene)


func _spawn_ship_destruction_fragments(ship_body: RigidBody2D, layout: Resource) -> void:
	if destruction_debris_definition == null or not is_instance_valid(ship_body) or layout == null:
		return
	var physics_world := get_tree().get_first_node_in_group("physics_world")
	if not is_instance_valid(physics_world):
		return
	var occupied := _layout_cells(layout)
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
	var segments: Array[Dictionary] = GRID_GEOMETRY.boundary_segments(layout, occupied, bounds, TACTICAL_CELL_SIZE)
	var random := RandomNumberGenerator.new()
	random.randomize()
	for segment: Dictionary in segments:
		if random.randf() > float(destruction_debris_definition.get("outline_fragment_coverage")):
			continue
		var local_start: Vector2 = segment["start"] - geometry_size * 0.5
		var local_end: Vector2 = segment["end"] - geometry_size * 0.5
		var local_midpoint := (local_start + local_end) * 0.5
		var local_tangent := local_start.direction_to(local_end)
		var local_normal: Vector2 = segment["normal"]
		var outward_normal := local_normal.rotated(ship_body.global_rotation)
		var fragment_body := PHYSICAL_FRAGMENT_SCENE.instantiate() as RigidBody2D
		fragment_body.set("collision_radius", destruction_debris_definition.get("collision_radius"))
		fragment_body.set("fragment_mass", destruction_debris_definition.get("fragment_mass"))
		fragment_body.set("bounce", destruction_debris_definition.get("bounce"))
		fragment_body.set("friction", destruction_debris_definition.get("friction"))
		fragment_body.linear_damp = float(destruction_debris_definition.get("linear_damping"))
		physics_world.add_child(fragment_body)
		fragment_body.add_collision_exception_with(ship_body)
		fragment_body.global_position = ship_body.to_global(local_midpoint) + outward_normal * 1.5
		fragment_body.global_rotation = local_tangent.rotated(ship_body.global_rotation).angle()
		var break_speed := random.randf_range(
			float(destruction_debris_definition.get("minimum_break_speed")),
			float(destruction_debris_definition.get("maximum_break_speed"))
		)
		var radial_variation := outward_normal.rotated(random.randf_range(-0.45, 0.45))
		fragment_body.linear_velocity = ship_body.linear_velocity + radial_variation * break_speed
		var tumble_speed := deg_to_rad(random.randf_range(
			float(destruction_debris_definition.get("minimum_tumble_degrees")),
			float(destruction_debris_definition.get("maximum_tumble_degrees"))
		))
		fragment_body.angular_velocity = tumble_speed * (-1.0 if random.randf() < 0.5 else 1.0)
		var fragment_id := next_fragment_id
		next_fragment_id += 1
		var color: Color = destruction_debris_definition.get("hull_color")
		if random.randf() < float(destruction_debris_definition.get("hot_fragment_chance")):
			color = destruction_debris_definition.get("hot_color")
		var lifetime: float = float(destruction_debris_definition.get("lifetime")) * random.randf_range(0.82, 1.18)
		impact_fragments.append({
			"id": fragment_id,
			"physics_body": fragment_body,
			"position": fragment_body.global_position,
			"previous_position": fragment_body.global_position,
			"velocity": fragment_body.linear_velocity,
			"rotation": fragment_body.global_rotation,
			"previous_rotation": fragment_body.global_rotation,
			"tumbling": true,
			"remaining_lifetime": lifetime,
			"maximum_lifetime": lifetime,
			"length": local_start.distance_to(local_end) * float(destruction_debris_definition.get("fragment_length_scale")),
			"width": destruction_debris_definition.get("line_width"),
			"color": color,
		})


func _update_impact_fragments(delta: float) -> void:
	for index: int in range(impact_fragments.size() - 1, -1, -1):
		var fragment: Dictionary = impact_fragments[index]
		var body_value: Variant = fragment.get("physics_body")
		fragment["remaining_lifetime"] = float(fragment["remaining_lifetime"]) - delta
		if float(fragment["remaining_lifetime"]) <= 0.0:
			if is_instance_valid(body_value):
				var expired_body := body_value as RigidBody2D
				expired_body.queue_free()
			impact_fragments.remove_at(index)
			continue
		fragment["previous_position"] = fragment["position"]
		if is_instance_valid(body_value):
			var body := body_value as RigidBody2D
			fragment["position"] = body.global_position
			fragment["velocity"] = body.linear_velocity
			if bool(fragment.get("tumbling", false)):
				fragment["previous_rotation"] = fragment["rotation"]
				fragment["rotation"] = body.global_rotation
			continue
		# Lightweight hit sparks follow the same damped/tumbling presentation
		# without entering the physics server or participating in collisions.
		var velocity: Vector2 = fragment.get("velocity", Vector2.ZERO)
		fragment["position"] = Vector2(fragment["position"]) + velocity * delta
		var damping := maxf(float(fragment.get("linear_damping", 0.0)), 0.0)
		fragment["velocity"] = velocity * exp(-damping * delta)
		if bool(fragment.get("tumbling", false)):
			fragment["previous_rotation"] = fragment["rotation"]
			fragment["rotation"] = float(fragment["rotation"]) + float(fragment.get("angular_velocity", 0.0)) * delta


func _find_hull_impact(
	segment_start: Vector2,
	segment_end: Vector2,
	ship_position: Vector2,
	ship_rotation: float,
	layout: Resource
) -> Dictionary:
	var occupied_cells := _layout_cells(layout)
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var local_start := (segment_start - ship_position).rotated(-ship_rotation)
	var local_end := (segment_end - ship_position).rotated(-ship_rotation)
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
	var earliest_weight := INF
	var earliest_normal := Vector2.ZERO
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var cell_rect := GRID_GEOMETRY.cell_rect(layout, cell, bounds, TACTICAL_CELL_SIZE)
		cell_rect.position -= geometry_size * 0.5
		var cell_hit := _segment_rect_entry(local_start, local_end, cell_rect)
		if not cell_hit.is_empty() and float(cell_hit["weight"]) < earliest_weight:
			earliest_weight = cell_hit["weight"]
			earliest_normal = cell_hit["normal"]
	if earliest_weight == INF:
		return {}
	return {
		"point": segment_start.lerp(segment_end, earliest_weight),
		"normal": earliest_normal.rotated(ship_rotation),
	}


func _segment_rect_entry(segment_start: Vector2, segment_end: Vector2, rect: Rect2) -> Dictionary:
	var direction := segment_end - segment_start
	var entry_weight := 0.0
	var exit_weight := 1.0
	var entry_normal := Vector2.ZERO
	for axis: int in range(2):
		var start_value := segment_start[axis]
		var direction_value := direction[axis]
		var minimum_value := rect.position[axis]
		var maximum_value := rect.end[axis]
		if is_zero_approx(direction_value):
			if start_value < minimum_value or start_value > maximum_value:
				return {}
			continue
		var first_weight := (minimum_value - start_value) / direction_value
		var second_weight := (maximum_value - start_value) / direction_value
		var first_normal := Vector2.ZERO
		var second_normal := Vector2.ZERO
		first_normal[axis] = -1.0
		second_normal[axis] = 1.0
		if first_weight > second_weight:
			var swap_weight := first_weight
			first_weight = second_weight
			second_weight = swap_weight
			var swap_normal := first_normal
			first_normal = second_normal
			second_normal = swap_normal
		if first_weight > entry_weight:
			entry_weight = first_weight
			entry_normal = first_normal
		exit_weight = minf(exit_weight, second_weight)
		if entry_weight > exit_weight:
			return {}
	if entry_weight < 0.0 or entry_weight > 1.0:
		return {}
	if entry_normal == Vector2.ZERO:
		entry_normal = -direction.normalized()
	return {"weight": entry_weight, "normal": entry_normal}


func _ensure_enemy_shields(enemy: Dictionary) -> void:
	if enemy.has("shield_banks"):
		return
	var banks: Dictionary = {}
	var layout: Resource = enemy.get("layout")
	if layout != null:
		# Use the player's geometry rules so exposed directional pieces and
		# omnidirectional rooms project exactly the same banks for both sides.
		var model := SHIELD_SIMULATION.new()
		model.ship_layout = layout
		model.call("_initialize_directional_shields")
		for facing: Variant in model.shield_bank_maximums:
			banks[facing] = {"maximum": model.shield_bank_maximums[facing], "current": model.shield_bank_maximums[facing], "rooms": model.shield_bank_rooms[facing], "recovery_delay": 0.0}
		model.free()
	else:
		for facing: int in range(4):
			var capacity := float(enemy.get("maximum_shield", 0.0)) / 4.0
			banks[facing] = {"maximum": capacity, "current": float(enemy.get("shield", capacity * 4.0)) / 4.0, "rooms": [], "recovery_delay": 0.0}
	enemy["shield_banks"] = banks
	_sync_enemy_shields(enemy)


func _update_enemy_shields(enemy: Dictionary, delta: float) -> void:
	_ensure_enemy_shields(enemy)
	var banks: Dictionary = enemy["shield_banks"]
	var layout: Resource = enemy.get("layout")
	var damage: Dictionary = enemy.get("room_damage", {})
	var power: Dictionary = enemy.get("room_power_factors", {})
	for facing: Variant in banks:
		var bank: Dictionary = banks[facing]
		var delay := float(bank.get("recovery_delay", 0.0))
		bank["recovery_delay"] = maxf(delay - delta, 0.0)
		var factor := 1.0
		var rooms: Array = bank["rooms"]
		if layout != null and not rooms.is_empty():
			factor = 0.0
			for room: Resource in layout.get("rooms"):
				if rooms.has(room.get("room_id")):
					var health := clampf(1.0 - float(damage.get(room.get("room_id"), 0.0)) / maxf(float(room.get("maximum_health")), 1.0), 0.0, 1.0)
					factor += minf(health, float(power.get(room.get("room_id"), 1.0))) / float(rooms.size())
		bank["online"] = factor > 0.0
		bank["current"] = minf(float(bank["current"]) + enemy_shield_regeneration * factor * maxf(delta - delay, 0.0), float(bank["maximum"]) * factor)
	_sync_enemy_shields(enemy)


func _sync_enemy_shields(enemy: Dictionary) -> void:
	enemy["shield"] = 0.0
	enemy["maximum_shield"] = 0.0
	for bank: Dictionary in enemy.get("shield_banks", {}).values():
		enemy["shield"] += float(bank["current"])
		enemy["maximum_shield"] += float(bank["maximum"])
		bank["ratio"] = float(bank["current"]) / maxf(float(bank["maximum"]), 0.001)


func _apply_damage_to_enemy(
	enemy: Dictionary,
	projectile: Dictionary,
	target_room_id: StringName = &"",
	impact_world_direction: Vector2 = Vector2.ZERO
) -> Dictionary:
	var damage := maxf(float(projectile.get("damage", 0.0)), 0.0)
	if damage > 0.0:
		_report_neutral_contact_assaulted(enemy)
		if bool(enemy.get("combat_test_neutral_station", false)) and not enemy.has("aggressor_combat_faction"):
			enemy["aggressor_combat_faction"] = int(projectile.get("faction", ProjectileFaction.PLAYER))
			enemy["hostile_to_player"] = int(enemy["aggressor_combat_faction"]) == ProjectileFaction.PLAYER
		if bool(enemy.get("stationary", false)):
			_cancel_enemy_docking_clearance(enemy)
	var shield_damage := damage * maxf(
		float(projectile.get("shield_damage_multiplier", 1.0)),
		0.0
	)
	_ensure_enemy_shields(enemy)
	var direction := impact_world_direction
	if direction.is_zero_approx():
		direction = -Vector2(projectile.get("velocity", Vector2.DOWN))
	var local_direction := direction.rotated(-float(enemy.get("rotation", 0.0)))
	var facing := posmod(roundi(Vector2.UP.angle_to(local_direction) / (PI * 0.5)), 4)
	var banks: Dictionary = enemy["shield_banks"]
	var bank: Dictionary = banks.get(facing, {})
	var absorbed := minf(float(bank.get("current", 0.0)), shield_damage)
	if not bank.is_empty() and shield_damage > 0.0:
		bank["current"] = float(bank["current"]) - absorbed
		var delay := shield_break_recovery_delay if absorbed > 0.0 and float(bank["current"]) <= 0.0 else shield_hit_recovery_delay
		bank["recovery_delay"] = maxf(float(bank.get("recovery_delay", 0.0)), delay)
	_sync_enemy_shields(enemy)
	var remaining_base_damage := damage
	if shield_damage > 0.0:
		remaining_base_damage *= (shield_damage - absorbed) / shield_damage
	var hull_damage := remaining_base_damage * maxf(
		float(projectile.get("hull_damage_multiplier", 1.0)),
		0.0
	)
	var system_damage := remaining_base_damage * maxf(
		float(projectile.get("system_damage_multiplier", 1.0)),
		0.0
	)
	enemy["hull"] = maxf(float(enemy["hull"]) - hull_damage, 0.0)
	if damage > 0.0:
		enemy["defense_alert"] = true
		enemy["player_targetable"] = true
	if not target_room_id.is_empty() and system_damage > 0.0:
		var room_damage: Dictionary = enemy.get("room_damage", {})
		room_damage[target_room_id] = (
			float(room_damage.get(target_room_id, 0.0))
			+ system_damage
		)
		enemy["room_damage"] = room_damage
	return {
		"shield_absorbed": absorbed,
		"hull_damage": hull_damage,
		"system_damage": system_damage,
	}


func _cancel_enemy_docking_clearance(enemy: Dictionary) -> void:
	if not bool(enemy.get("docking_clearance", false)):
		return
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(player) and player.has_method("force_cancel_docking"):
		player.call("force_cancel_docking", int(enemy.get("id", -1)))
	if not bool(enemy.get("docking_clearance", false)):
		return
	var station_body := enemy.get("physics_body") as RigidBody2D
	var player_body := enemy.get("docking_player_body") as RigidBody2D
	if is_instance_valid(player_body) and is_instance_valid(station_body):
		player_body.remove_collision_exception_with(station_body)
		station_body.remove_collision_exception_with(player_body)
	enemy["docking_clearance"] = false
	enemy.erase("docking_player_body")


func _report_neutral_contact_assaulted(enemy: Dictionary) -> void:
	if (
		not bool(enemy.get("neutral_contact", false))
		or bool(enemy.get("reputation_assault_reported", false))
	):
		return
	var faction_id := StringName(enemy.get("faction_id", &"UNAFFILIATED"))
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	if not is_instance_valid(reputation) or reputation.call("get_faction_definition", faction_id) == null:
		return
	enemy["reputation_assault_reported"] = true
	reputation.call(
		"report_incident",
		&"ASSAULT",
		faction_id,
		Vector2(enemy.get("position", Vector2.ZERO)),
		true,
		String(enemy.get("display_name", "CIVILIAN CONTACT")),
		int(enemy.get("id", -1))
	)


func _report_neutral_contact_destroyed(enemy: Dictionary) -> void:
	if (
		not bool(enemy.get("neutral_contact", false))
		or bool(enemy.get("reputation_destruction_reported", false))
	):
		return
	var faction_id := StringName(enemy.get("faction_id", &"UNAFFILIATED"))
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	if not is_instance_valid(reputation) or reputation.call("get_faction_definition", faction_id) == null:
		return
	enemy["reputation_destruction_reported"] = true
	var witnessed := (
		bool(enemy.get("reputation_assault_reported", false))
		or _incident_has_surviving_witness(enemy, 1050.0)
	)
	var action_id: StringName = (
		&"STATION_DESTROYED"
		if bool(enemy.get("stationary", false))
		else &"SHIP_DESTROYED"
	)
	reputation.call(
		"report_incident",
		action_id,
		faction_id,
		Vector2(enemy.get("position", Vector2.ZERO)),
		witnessed,
		String(enemy.get("display_name", "CIVILIAN CONTACT")),
		int(enemy.get("id", -1))
	)


func _incident_has_surviving_witness(subject: Dictionary, maximum_range: float) -> bool:
	var subject_id := int(subject.get("id", -1))
	var subject_position := Vector2(subject.get("position", Vector2.ZERO))
	for contact: Dictionary in enemies:
		if (
			int(contact.get("id", -1)) == subject_id
			or float(contact.get("hull", 0.0)) <= 0.0
			or not bool(contact.get("transponder_online", true))
		):
			continue
		if subject_position.distance_to(Vector2(contact.get("position", Vector2.ZERO))) <= maximum_range:
			return true
	return false


func _connect_player_destruction_signal() -> void:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(player) or not player.has_signal("hull_depleted"):
		return
	var destruction_callback := _on_player_hull_depleted.bind(player)
	if not player.is_connected("hull_depleted", destruction_callback):
		player.connect("hull_depleted", destruction_callback)


func _on_player_hull_depleted(player: Node) -> void:
	_destroy_player_ship_if_needed(player)


func _destroy_player_ship_if_needed(player: Node) -> void:
	if player_destroyed or not is_instance_valid(player) or not player.call("is_hull_depleted"):
		return
	player_destroyed = true
	player_destruction_finalized = false
	player_destruction_remaining = ship_destruction_sequence_seconds
	player_destruction_burst_clock = 0.0
	player_destruction_burst_index = 0
	player.call("mark_destroyed")
	var destroyed_body := player.get("physics_body") as RigidBody2D
	if is_instance_valid(destroyed_body):
		destroyed_body.set_meta("destruction_active", true)
		if destroyed_body.has_method("set_coast_command"):
			destroyed_body.call("set_coast_command")
		if absf(destroyed_body.angular_velocity) < 0.08:
			destroyed_body.angular_velocity = randf_range(-0.16, 0.16)


func _update_player_destruction(player: Node, delta: float) -> void:
	if player_destruction_finalized or not is_instance_valid(player):
		return
	var body := player.get("physics_body") as RigidBody2D
	player_destruction_remaining = maxf(player_destruction_remaining - delta, 0.0)
	player_destruction_burst_clock -= delta
	if player_destruction_burst_clock <= 0.0 and player_destruction_remaining > 0.0:
		_spawn_ship_destruction_burst(body, player.get("ship_layout") as Resource, player_destruction_burst_index)
		if player_destruction_burst_index % 2 == 0 and is_instance_valid(body):
			_play_world_sound(small_explosion_sound, body.global_position, -5.0, 0.08)
		player_destruction_burst_index += 1
		player_destruction_burst_clock = ship_destruction_burst_interval
	if player_destruction_remaining > 0.0:
		return
	player_destruction_finalized = true
	var destroyed_position: Vector2 = player.get("ship_position")
	if is_instance_valid(body):
		destroyed_position = body.global_position
		_spawn_ship_destruction_burst(body, player.get("ship_layout") as Resource, player_destruction_burst_index, true)
		_spawn_ship_destruction_fragments(body, player.get("ship_layout"))
		registered_physics_ships.erase(body.get_instance_id())
	_play_world_sound(large_explosion_sound, destroyed_position, 2.0, 0.025)
	var destroyed_instance := player.get("capital_ship_instance") as Node
	if is_instance_valid(destroyed_instance):
		destroyed_instance.call("destroy")
	elif is_instance_valid(body):
		body.queue_free()
	player.set_physics_process(false)
	player_ship_destroyed.emit(destroyed_position)


func _enemy_by_id(enemy_id: int) -> Dictionary:
	for enemy: Dictionary in enemies:
		if int(enemy["id"]) == enemy_id:
			return enemy
	return {}


func get_tactical_contact(enemy_id: int) -> Dictionary:
	return _enemy_by_id(enemy_id).duplicate()


func request_docking_clearance(enemy_id: int, player: Node) -> Dictionary:
	var enemy := _enemy_by_id(enemy_id)
	if enemy.is_empty():
		return {"ok": false, "message": "CONTACT LOST"}
	if bool(enemy.get("combat_active", true)) or bool(enemy.get("defense_alert", false)):
		return {"ok": false, "message": "CLEARANCE DENIED • HOSTILE ALERT"}
	_refresh_enemy_blueprint_operations(enemy)
	if not bool(enemy.get("station_operational", false)):
		var power_factor := float(enemy.get("station_power_factor", 0.0))
		if power_factor < 0.999:
			return {"ok": false, "message": "CLEARANCE DENIED • STATION POWER OFFLINE"}
		return {"ok": false, "message": "CLEARANCE DENIED • DOCK CREW UNAVAILABLE"}
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	var faction_id := StringName(enemy.get("faction_id", &"UNAFFILIATED"))
	if is_instance_valid(reputation) and reputation.call("get_faction_definition", faction_id) != null:
		var standing := StringName(reputation.call("get_standing", faction_id))
		if standing in [&"HOSTILE", &"HUNTED"]:
			return {"ok": false, "message": "CLEARANCE DENIED • FACTION WARRANT"}
	if not bool(enemy.get("stationary", false)) and PackedStringArray(enemy.get("station_service_tags", PackedStringArray())).is_empty():
		return {"ok": false, "message": "NO COMPATIBLE DOCKING PORT"}
	if not is_instance_valid(player) or not is_instance_valid(player.get("physics_body")):
		return {"ok": false, "message": "HELM LINK UNAVAILABLE"}
	var player_connector: Dictionary = player.call("get_starboard_docking_connector")
	if player_connector.is_empty():
		return {"ok": false, "message": "NO STARBOARD HULL CONNECTOR"}
	var docking_ports := _get_contact_docking_ports(enemy)
	if docking_ports.is_empty():
		return {"ok": false, "message": "NO COMPATIBLE DOCKING PORT"}
	var station_position: Vector2 = enemy.get("position", Vector2.ZERO)
	var player_position: Vector2 = player.get("ship_position")
	var approach_direction := station_position.direction_to(player_position)
	if approach_direction.is_zero_approx():
		approach_direction = Vector2.LEFT
	var chosen_port: Dictionary = docking_ports[0]
	var best_score := -INF
	for port: Dictionary in docking_ports:
		var outward: Vector2 = port["outward"]
		var score := outward.dot(approach_direction)
		if score > best_score:
			best_score = score
			chosen_port = port
	var port_outward: Vector2 = chosen_port["outward"]
	var station_connector: Vector2 = chosen_port["position"]
	var final_rotation := Vector2.RIGHT.angle_to(-port_outward)
	var player_connector_local: Vector2 = player_connector["local_position"]
	var final_position := station_connector - player_connector_local.rotated(final_rotation)
	var hold_position := final_position + port_outward * float(player.get("docking_alignment_distance"))
	var station_body := enemy.get("physics_body") as RigidBody2D
	var player_body := player.get("physics_body") as RigidBody2D
	pending_docking_releases.erase(enemy_id)
	if is_instance_valid(station_body):
		player_body.add_collision_exception_with(station_body)
		station_body.add_collision_exception_with(player_body)
	enemy["docking_clearance"] = true
	enemy["docking_player_body"] = player_body
	enemy["defense_alert"] = false
	enemy["player_targetable"] = false
	_recall_carrier_fighters(station_body)
	var navigation_points := _build_safe_docking_route(
		player_position,
		station_position,
		hold_position,
		final_position,
		port_outward,
		final_rotation,
		station_body,
		player_body,
		float(player.get("docking_route_clearance"))
	)
	return {
		"ok": true,
		"message": "CLEARANCE GRANTED",
		"contact_id": enemy_id,
		"station_body": station_body,
		"station_connector": station_connector,
		"port_outward": port_outward,
		"final_position": final_position,
		"final_rotation": final_rotation,
		"navigation_points": navigation_points,
	}


func complete_undocking(enemy_id: int, player_body: RigidBody2D) -> void:
	var enemy := _enemy_by_id(enemy_id)
	if enemy.is_empty():
		return
	var station_body := enemy.get("physics_body") as RigidBody2D
	if not is_instance_valid(player_body) or not is_instance_valid(station_body):
		_finalize_docking_release(enemy_id, player_body, station_body)
		return
	var station_radius := float(station_body.call("get_hull_bounding_radius")) if station_body.has_method("get_hull_bounding_radius") else 40.0
	var player_radius := float(player_body.call("get_hull_bounding_radius")) if player_body.has_method("get_hull_bounding_radius") else 20.0
	var safe_center_distance := station_radius + player_radius + 12.0
	if player_body.global_position.distance_to(station_body.global_position) >= safe_center_distance:
		_finalize_docking_release(enemy_id, player_body, station_body)
		return
	# The clamp animation is complete, but the hulls still overlap their
	# conservative collision bounds. Keep the exception and clearance record
	# alive until the player has physically exited the berth.
	pending_docking_releases[enemy_id] = {
		"player_body": player_body,
		"station_body": station_body,
		"safe_center_distance": safe_center_distance,
	}


func _update_pending_docking_releases() -> void:
	for enemy_id_value: Variant in pending_docking_releases.keys().duplicate():
		var enemy_id := int(enemy_id_value)
		var release: Dictionary = pending_docking_releases[enemy_id_value]
		var player_body := release.get("player_body") as RigidBody2D
		var station_body := release.get("station_body") as RigidBody2D
		if not is_instance_valid(player_body) or not is_instance_valid(station_body):
			_finalize_docking_release(enemy_id, player_body, station_body)
			continue
		if player_body.global_position.distance_to(station_body.global_position) >= float(release.get("safe_center_distance", 0.0)):
			_finalize_docking_release(enemy_id, player_body, station_body)


func _finalize_docking_release(enemy_id: int, player_body: RigidBody2D, station_body: RigidBody2D) -> void:
	pending_docking_releases.erase(enemy_id)
	if is_instance_valid(player_body) and is_instance_valid(station_body):
		player_body.remove_collision_exception_with(station_body)
		station_body.remove_collision_exception_with(player_body)
		# Give physics one settling window after collision is restored. This
		# prevents a numerical edge contact from becoming a high-energy impact.
		var pair_key := _collision_pair_key(player_body, station_body)
		collision_pair_cooldowns[pair_key] = maxf(float(collision_pair_cooldowns.get(pair_key, 0.0)), 1.0)
	var enemy := _enemy_by_id(enemy_id)
	if enemy.is_empty():
		return
	enemy["docking_clearance"] = false
	enemy.erase("docking_player_body")
	enemy["defense_alert"] = false
	enemy["player_targetable"] = false


func _get_contact_docking_ports(enemy: Dictionary) -> Array[Dictionary]:
	var ports: Array[Dictionary] = []
	var layout: Resource = enemy.get("layout")
	if layout == null:
		return ports
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
	var occupied := GRID_GEOMETRY.layout_cells(layout)
	var station_position: Vector2 = enemy.get("position", Vector2.ZERO)
	var station_rotation := float(enemy.get("rotation", 0.0))
	var extension := 0.0
	var instance := enemy.get("instance") as Node
	if is_instance_valid(instance):
		var definition: Resource = instance.get("definition")
		if definition != null:
			extension = float(definition.get("docking_connector_extension"))
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "DOCKING":
			continue
		var facing := GRID_GEOMETRY.resolved_module_facing(layout, room)
		var local_outward := Vector2(GRID_GEOMETRY.quarter_direction(facing))
		var exposed_faces: Array[Vector2] = []
		for cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			var neighbor := cell + GRID_GEOMETRY.quarter_direction(facing)
			if occupied.has(neighbor):
				continue
			var cell_center := GRID_GEOMETRY.cell_rect(
				layout,
				cell,
				bounds,
				TACTICAL_CELL_SIZE
			).get_center() - geometry_size * 0.5
			exposed_faces.append(cell_center + local_outward * TACTICAL_CELL_SIZE * 0.5)
		if exposed_faces.is_empty():
			continue
		var local_connector := Vector2.ZERO
		for face: Vector2 in exposed_faces:
			local_connector += face
		local_connector /= float(exposed_faces.size())
		local_connector += local_outward * extension
		var world_outward := local_outward.rotated(station_rotation)
		ports.append({
			"room_id": room.get("room_id"),
			"outward": world_outward,
			"position": station_position + local_connector.rotated(station_rotation),
		})
	return ports


func _build_safe_docking_route(
	start: Vector2,
	station_center: Vector2,
	hold_position: Vector2,
	final_position: Vector2,
	port_outward: Vector2,
	final_rotation: float,
	station_body: RigidBody2D,
	player_body: RigidBody2D,
	clearance: float
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var station_radius := 280.0
	if is_instance_valid(station_body) and station_body.has_method("get_hull_bounding_radius"):
		station_radius = float(station_body.call("get_hull_bounding_radius"))
	var player_radius := 40.0
	if is_instance_valid(player_body) and player_body.has_method("get_hull_bounding_radius"):
		player_radius = float(player_body.call("get_hull_bounding_radius"))
	var safe_radius := station_radius + player_radius + clearance
	if _docking_swoop_clears_station(
		start,
		hold_position,
		final_position,
		station_center,
		station_radius
	):
		_append_direct_docking_swoop(points, start, hold_position, final_position)
		return points
	# Enter the hold point along the ship's eventual forward axis. This lets the
	# helm complete the broadside docking turn while it is still moving instead
	# of arriving nose-first, stopping, and spinning through ninety degrees.
	var final_forward := Vector2.UP.rotated(final_rotation)
	var capture_lane_length := maxf(120.0, clearance * 1.35)
	var capture_entry := hold_position - final_forward * capture_lane_length

	if _segment_clears_station(start, capture_entry, station_center, safe_radius):
		_append_rounded_capture(
			points,
			start,
			capture_entry,
			hold_position,
			station_center,
			safe_radius
		)
		_append_terminal_docking_segment(
			points,
			hold_position,
			final_position
		)
		return points

	# A direct capture is obstructed. Join the exclusion ring at a tangent, sweep
	# only as far as the capture lane requires, and then peel away from it.
	# The navigation ring sits slightly outside the true exclusion radius so the
	# straight chords between arc waypoints also remain clear of the hull.
	var routing_radius := safe_radius + maxf(18.0, clearance * 0.25)
	var start_outward := station_center.direction_to(start)
	if start_outward.is_zero_approx():
		start_outward = port_outward
	var start_distance := station_center.distance_to(start)
	var start_angle := start_outward.angle()
	var join_angle := start_angle
	if start_distance > routing_radius + 1.0:
		var tangent_offset := acos(clampf(routing_radius / start_distance, -1.0, 1.0))
		var first_tangent := start_angle + tangent_offset
		var second_tangent := start_angle - tangent_offset
		var capture_angle := station_center.direction_to(capture_entry).angle()
		join_angle = first_tangent
		if absf(angle_difference(second_tangent, capture_angle)) < absf(angle_difference(first_tangent, capture_angle)):
			join_angle = second_tangent
		var tangent_point := station_center + Vector2.RIGHT.rotated(join_angle) * routing_radius
		if start.distance_to(tangent_point) > 1.0:
			points.append(tangent_point)
	else:
		var escape_point := station_center + start_outward * routing_radius
		if start.distance_to(escape_point) > 1.0:
			points.append(escape_point)

	var finish_angle := station_center.direction_to(capture_entry).angle()
	var arc := angle_difference(join_angle, finish_angle)
	if absf(arc) > 0.01:
		var arc_steps := maxi(1, ceili(absf(arc) / deg_to_rad(35.0)))
		for step: int in range(1, arc_steps + 1):
			var weight := float(step) / float(arc_steps)
			var direction := Vector2.RIGHT.rotated(join_angle + arc * weight)
			var arc_point := station_center + direction * routing_radius
			if points.is_empty() or points.back().distance_to(arc_point) > 1.0:
				points.append(arc_point)
	var capture_origin: Vector2 = start if points.is_empty() else points.back()
	_append_rounded_capture(
		points,
		capture_origin,
		capture_entry,
		hold_position,
		station_center,
		safe_radius
	)
	_append_terminal_docking_segment(
		points,
		hold_position,
		final_position
	)
	return points


func _append_direct_docking_swoop(
	points: Array[Vector2],
	start: Vector2,
	control: Vector2,
	final_position: Vector2
) -> void:
	var length_guess := start.distance_to(control) + control.distance_to(final_position)
	var curve_steps := maxi(12, ceili(length_guess / 14.0))
	for sample_index: int in range(1, curve_steps + 1):
		var weight := float(sample_index) / float(curve_steps)
		points.append(_quadratic_point(start, control, final_position, weight))


func _docking_swoop_clears_station(
	start: Vector2,
	control: Vector2,
	final_position: Vector2,
	station_center: Vector2,
	_station_radius: float
) -> bool:
	# A station's broad bounding radius includes its docking arms, so using that
	# radius here incorrectly rejects the clean curve that terminates at a berth.
	# Keep the entire swoop outside the berth's own radial lane instead. The
	# selected outward-facing port makes that lane clear of the central hull.
	var minimum_radius := maxf(
		0.0,
		station_center.distance_to(final_position) - 2.0
	)
	var previous := start
	for sample_index: int in range(1, 25):
		var weight := float(sample_index) / 24.0
		var sample := _quadratic_point(start, control, final_position, weight)
		if not _segment_clears_station(previous, sample, station_center, minimum_radius):
			return false
		previous = sample
	return true


func _append_terminal_docking_segment(
	points: Array[Vector2],
	hold_position: Vector2,
	final_position: Vector2
) -> void:
	# The safe approach point remains part of the continuous route, but there is
	# no decorative S-turn beside the station: helm proceeds directly to clamp.
	if hold_position.distance_to(final_position) > 1.0:
		points.append(final_position)


func _append_rounded_capture(
	points: Array[Vector2],
	previous_position: Vector2,
	corner: Vector2,
	hold_position: Vector2,
	station_center: Vector2,
	safe_radius: float
) -> void:
	var incoming_distance := previous_position.distance_to(corner)
	var outgoing_distance := corner.distance_to(hold_position)
	if incoming_distance <= 1.0 or outgoing_distance <= 1.0:
		if points.is_empty() or points.back().distance_to(hold_position) > 1.0:
			points.append(hold_position)
		return
	var incoming := previous_position.direction_to(corner)
	var outgoing := corner.direction_to(hold_position)
	var trim := minf(110.0, minf(incoming_distance * 0.38, outgoing_distance * 0.55))
	var curve_start := corner - incoming * trim
	var curve_end := corner + outgoing * trim

	# Tighten the fillet if its first shape would cut into the station envelope.
	for attempt: int in range(4):
		var curve_is_safe := true
		var safety_previous := curve_start
		for sample_index: int in range(1, 9):
			var weight := float(sample_index) / 8.0
			var curve_point := _quadratic_point(curve_start, corner, curve_end, weight)
			if not _segment_clears_station(
				safety_previous,
				curve_point,
				station_center,
				safe_radius
			):
				curve_is_safe = false
				break
			safety_previous = curve_point
		if curve_is_safe:
			break
		trim *= 0.55
		curve_start = corner - incoming * trim
		curve_end = corner + outgoing * trim

	if previous_position.distance_to(curve_start) > 1.0:
		points.append(curve_start)
	var curve_length_guess := curve_start.distance_to(corner) + corner.distance_to(curve_end)
	var curve_steps := maxi(8, ceili(curve_length_guess / 10.0))
	for sample_index: int in range(1, curve_steps + 1):
		var weight := float(sample_index) / float(curve_steps)
		points.append(_quadratic_point(curve_start, corner, curve_end, weight))
	if points.back().distance_to(hold_position) > 1.0:
		points.append(hold_position)


func _quadratic_point(from: Vector2, control: Vector2, to: Vector2, weight: float) -> Vector2:
	var inverse := 1.0 - weight
	return from * inverse * inverse + control * 2.0 * inverse * weight + to * weight * weight


func _segment_clears_station(
	from: Vector2,
	to: Vector2,
	station_center: Vector2,
	safe_radius: float
) -> bool:
	var segment := to - from
	if segment.length_squared() <= 0.001:
		return station_center.distance_to(from) >= safe_radius
	var closest_weight := clampf(
		(station_center - from).dot(segment) / segment.length_squared(),
		0.0,
		1.0
	)
	var closest_point := from + segment * closest_weight
	return station_center.distance_to(closest_point) >= safe_radius


func _recall_carrier_fighters(carrier_body: RigidBody2D) -> void:
	if not is_instance_valid(carrier_body):
		return
	for index: int in range(fighters.size() - 1, -1, -1):
		var fighter: Dictionary = fighters[index]
		if fighter.get("carrier") != carrier_body:
			continue
		var craft: Dictionary = fighter.get("craft", {})
		if not craft.is_empty():
			craft["state"] = "DOCKED"
		var fighter_body := fighter.get("physics_body") as RigidBody2D
		if is_instance_valid(fighter_body):
			fighter_body.queue_free()
		fighters.remove_at(index)


func _is_cleared_docking_pair(first: RigidBody2D, second: RigidBody2D) -> bool:
	for enemy: Dictionary in enemies:
		if not bool(enemy.get("docking_clearance", false)):
			continue
		var station_body := enemy.get("physics_body") as RigidBody2D
		var player_body := enemy.get("docking_player_body") as RigidBody2D
		if (first == station_body and second == player_body) or (first == player_body and second == station_body):
			return true
	return false


func set_enemy_player_targetable(enemy_id: int, is_targetable: bool) -> void:
	for index: int in range(enemies.size()):
		if int(enemies[index]["id"]) == enemy_id:
			enemies[index]["player_targetable"] = is_targetable
			if is_targetable:
				enemies[index]["defense_alert"] = true
			return


func _is_player_targetable(enemy: Dictionary) -> bool:
	if bool(enemy.get("asteroid_target", false)):
		var body_value: Variant = enemy.get("physics_body")
		return (
			is_instance_valid(body_value)
			and not (body_value as Node).is_queued_for_deletion()
			and not bool((body_value as Node).get("is_destroyed"))
		)
	if bool(enemy.get("combat_test_ship", false)):
		return bool(enemy.get("hostile_to_player", false)) or bool(enemy.get("player_targetable", false))
	return bool(enemy.get("combat_active", true)) or bool(enemy.get("player_targetable", false))


func _enemy_should_defend(enemy: Dictionary) -> bool:
	if bool(enemy.get("docking_clearance", false)):
		return false
	if bool(enemy.get("training_target", false)) and not bool(enemy.get("training_aggressive", false)):
		return false
	if bool(enemy.get("combat_active", true)):
		return true
	if bool(enemy.get("defense_alert", false)) or bool(enemy.get("player_targetable", false)):
		return true
	return float(enemy.get("shield", 0.0)) < float(enemy.get("maximum_shield", 0.0)) or float(enemy.get("hull", 0.0)) < float(enemy.get("maximum_hull", 0.0))


func _get_room_world_center(layout: Resource, room_id: StringName, ship_position: Vector2, ship_rotation: float) -> Vector2:
	for room: Resource in layout.get("rooms"):
		if room.get("room_id") != room_id:
			continue
		var rects: Array[Rect2i] = room.get("grid_rects")
		if rects.is_empty():
			break
		var bounds: Rect2i = layout.call("get_occupied_bounds")
		var first_cell := rects[0].position
		var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
		var local_position := GRID_GEOMETRY.cell_rect(layout, first_cell, bounds, TACTICAL_CELL_SIZE).get_center() - geometry_size * 0.5
		return ship_position + local_position.rotated(ship_rotation)
	return ship_position


func _player_automatic_target_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		if _is_player_targetable(enemy):
			candidates.append(enemy)
	for body_value: Variant in get_tree().get_nodes_in_group("automatic_weapon_targets"):
		if not is_instance_valid(body_value):
			continue
		var body := body_value as RigidBody2D
		if body == null or body.is_queued_for_deletion() or bool(body.get("is_destroyed")):
			continue
		candidates.append({
			"asteroid_target": true,
			"player_targetable": true,
			"position": body.global_position,
			"rotation": body.global_rotation,
			"physics_body": body,
			"display_name": String(body.get_meta("target_display_name", "TARGET ASTEROID")),
		})
	return candidates


func _nearest_enemy(origin: Vector2, candidates: Array[Dictionary] = []) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var search_targets := candidates
	if search_targets.is_empty():
		search_targets = _player_automatic_target_candidates()
	for enemy: Dictionary in search_targets:
		if not _is_player_targetable(enemy):
			continue
		var distance := origin.distance_squared_to(enemy["position"])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _nearest_valid_enemy(mount: Dictionary, weapon: Resource, candidates: Array[Dictionary] = []) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var search_targets := candidates
	if search_targets.is_empty():
		search_targets = _player_automatic_target_candidates()
	for enemy: Dictionary in search_targets:
		if not _is_player_targetable(enemy):
			continue
		if not _target_is_valid(mount, enemy["position"], weapon):
			continue
		var distance := (mount["position"] as Vector2).distance_squared_to(enemy["position"])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _target_is_valid(mount: Dictionary, target_position: Vector2, weapon: Resource) -> bool:
	return not _resolve_firing_mount(mount, target_position, weapon).is_empty()


func _closest_preview_mount(mount: Dictionary, target_position: Vector2) -> Dictionary:
	var candidates: Array = mount.get("coverage_mounts", [])
	if candidates.is_empty() and mount.has("position") and mount.has("direction"):
		candidates = [mount]
	var best_mount: Dictionary = mount
	var best_angle := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_position: Vector2 = candidate.get(
			"position",
			mount.get("position", Vector2.ZERO)
		)
		var to_target := target_position - candidate_position
		if to_target.is_zero_approx():
			continue
		var direction: Vector2 = candidate.get("direction", Vector2.UP)
		var angle_to_target := absf(angle_difference(direction.angle(), to_target.angle()))
		if angle_to_target < best_angle:
			best_angle = angle_to_target
			best_mount = candidate
	return best_mount


func _manual_battery_direction(ship_rotation: float, aim_direction: Vector2) -> Vector2:
	var local_aim := aim_direction.rotated(-ship_rotation)
	var local_battery := Vector2.ZERO
	if absf(local_aim.x) >= absf(local_aim.y):
		local_battery = Vector2.RIGHT if local_aim.x >= 0.0 else Vector2.LEFT
	else:
		local_battery = Vector2.DOWN if local_aim.y >= 0.0 else Vector2.UP
	return local_battery.rotated(ship_rotation)


func _closest_preview_mount_for_bearing(mount: Dictionary, battery_direction: Vector2) -> Dictionary:
	var candidates: Array = mount.get("coverage_mounts", [])
	if candidates.is_empty() and mount.has("position") and mount.has("direction"):
		candidates = [mount]
	var best_mount: Dictionary = mount
	var best_angle := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		if not bool(candidate.get("line_of_fire_clear", true)):
			continue
		var direction: Vector2 = candidate.get("direction", Vector2.UP)
		var angle_to_bearing := absf(angle_difference(direction.angle(), battery_direction.angle()))
		if angle_to_bearing < best_angle:
			best_angle = angle_to_bearing
			best_mount = candidate
	return best_mount


## Returns the nearest bearing the physical turret can adopt without sweeping
## through its own hull. Exposed quarter mounts may combine several hull-face
## arcs, so this evaluates all of them and chooses the closest legal edge when
## the cursor is inside the ship's blocked sector.
func _closest_legal_mount_aim_direction(mount: Dictionary, aim_direction: Vector2, weapon: Resource) -> Vector2:
	if aim_direction.is_zero_approx():
		return mount.get("direction", Vector2.UP)
	var allowed_degrees := float(weapon.get("traverse_degrees"))
	if bool(weapon.get("uses_exposed_hull_edges")):
		allowed_degrees = maxf(allowed_degrees, 45.0)
	allowed_degrees = clampf(allowed_degrees, 0.0, 89.0)
	var candidates: Array = mount.get("coverage_mounts", [])
	if candidates.is_empty() and mount.has("position") and mount.has("direction"):
		candidates = [mount]
	var closest_direction: Vector2 = mount.get("direction", Vector2.UP)
	var closest_angle := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		if not bool(candidate.get("line_of_fire_clear", true)):
			continue
		var center_direction: Vector2 = candidate.get("direction", Vector2.UP)
		var desired_offset := angle_difference(center_direction.angle(), aim_direction.angle())
		var minimum_offset := deg_to_rad(maxf(float(candidate.get("minimum_offset_degrees", -allowed_degrees)), -allowed_degrees))
		var maximum_offset := deg_to_rad(minf(float(candidate.get("maximum_offset_degrees", allowed_degrees)), allowed_degrees))
		var legal_direction := center_direction.rotated(clampf(desired_offset, minimum_offset, maximum_offset))
		var angle_to_aim := absf(angle_difference(legal_direction.angle(), aim_direction.angle()))
		if angle_to_aim < closest_angle:
			closest_angle = angle_to_aim
			closest_direction = legal_direction
	return closest_direction.normalized()


func _resolve_firing_mount_for_bearing(mount: Dictionary, battery_direction: Vector2, aim_direction: Vector2, weapon: Resource) -> Dictionary:
	if battery_direction.is_zero_approx() or aim_direction.is_zero_approx():
		return {}
	battery_direction = battery_direction.normalized()
	aim_direction = aim_direction.normalized()
	var authored_traverse: float = weapon.get("traverse_degrees")
	var allowed_degrees := authored_traverse
	if bool(weapon.get("uses_exposed_hull_edges")):
		allowed_degrees = maxf(allowed_degrees, 45.0)
	# A mount may turn within the exterior hemisphere of its selected hull face,
	# but never back through the ship itself.
	allowed_degrees = clampf(allowed_degrees, 0.0, 89.0)
	var candidates: Array = mount.get("coverage_mounts", [])
	if candidates.is_empty() and mount.has("position") and mount.has("direction"):
		candidates = [mount]
	var best_mount: Dictionary = {}
	var best_battery_angle := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		var direction: Vector2 = candidate.get("direction", Vector2.UP)
		var angle_to_battery := absf(angle_difference(direction.angle(), battery_direction.angle()))
		if angle_to_battery <= deg_to_rad(1.0) and angle_to_battery < best_battery_angle:
			best_battery_angle = angle_to_battery
			best_mount = candidate.duplicate()
			best_mount["coverage_directions"] = mount.get("coverage_directions", [])
			best_mount["exposed_edge_count"] = mount.get("exposed_edge_count", 0)
			best_mount["muzzle_clearance"] = mount.get("muzzle_clearance", 2.0)
			_copy_authored_muzzle_socket(best_mount, candidate, mount)
			var desired_offset := angle_difference(direction.angle(), aim_direction.angle())
			var minimum_offset := deg_to_rad(maxf(float(candidate.get("minimum_offset_degrees", -allowed_degrees)), -allowed_degrees))
			var maximum_offset := deg_to_rad(minf(float(candidate.get("maximum_offset_degrees", allowed_degrees)), allowed_degrees))
			var clamped_offset := clampf(desired_offset, minimum_offset, maximum_offset)
			best_mount["fire_direction_override"] = direction.rotated(clamped_offset)
	return best_mount


func _resolve_firing_mount(mount: Dictionary, target_position: Vector2, weapon: Resource) -> Dictionary:
	var allowed_degrees: float = weapon.get("traverse_degrees")
	# Exposed-edge gimbals sweep one continuous 90-degree field through each
	# available hull face. Adjacent open faces therefore meet without blind seams.
	if bool(weapon.get("uses_exposed_hull_edges")):
		allowed_degrees = maxf(allowed_degrees, 45.0)
	if allowed_degrees <= 0.0:
		allowed_degrees = fixed_weapon_alignment_degrees
	var candidates: Array = mount.get("coverage_mounts", [])
	if candidates.is_empty() and mount.has("position") and mount.has("direction"):
		candidates = [mount]
	var best_mount: Dictionary = {}
	var best_angle := INF
	for candidate_value: Variant in candidates:
		var candidate: Dictionary = candidate_value
		if not bool(candidate.get("line_of_fire_clear", true)):
			continue
		var candidate_position: Vector2 = candidate.get("position", mount.get("position", Vector2.ZERO))
		var to_target := target_position - candidate_position
		if to_target.length() > float(weapon.get("maximum_range")) or to_target.is_zero_approx():
			continue
		var direction: Vector2 = candidate.get("direction", Vector2.UP)
		var offset_to_target := angle_difference(direction.angle(), to_target.angle())
		var angle_to_target := absf(offset_to_target)
		var minimum_offset := deg_to_rad(maxf(float(candidate.get("minimum_offset_degrees", -allowed_degrees)), -allowed_degrees))
		var maximum_offset := deg_to_rad(minf(float(candidate.get("maximum_offset_degrees", allowed_degrees)), allowed_degrees))
		if offset_to_target >= minimum_offset and offset_to_target <= maximum_offset and angle_to_target < best_angle:
			best_angle = angle_to_target
			best_mount = candidate.duplicate()
			best_mount["coverage_directions"] = mount.get("coverage_directions", [])
			best_mount["exposed_edge_count"] = mount.get("exposed_edge_count", 0)
			best_mount["muzzle_clearance"] = mount.get("muzzle_clearance", 2.0)
			_copy_authored_muzzle_socket(best_mount, candidate, mount)
	return best_mount


## Coverage selection is allowed to choose an aiming arc, never a different
## physical barrel.  Copy the scene-authored socket from the candidate when it
## has one, otherwise inherit the parent mount's exact socket.
func _copy_authored_muzzle_socket(destination: Dictionary, candidate: Dictionary, parent_mount: Dictionary) -> void:
	for property_name: String in ["muzzle_position", "muzzle_offset", "muzzle_direction"]:
		var value: Variant = candidate.get(property_name, parent_mount.get(property_name))
		if value is Vector2:
			destination[property_name] = value


func _weapon_mount_count(room: Resource) -> int:
	var piece_rects: Array = room.get("grid_rects")
	if not piece_rects.is_empty():
		return piece_rects.size()
	return maxi(int(room.get("installed_piece_count")), 1)


func _player_weapon_mount_efficiency(player: Node, room_id: StringName, mount_index: int) -> float:
	if player.has_method("get_weapon_mount_efficiency"):
		return float(player.call("get_weapon_mount_efficiency", room_id, mount_index))
	return float(player.call("get_room_efficiency", room_id))


func _weapon_mount_fire_mode(room: Resource, mount_index: int) -> int:
	if room.has_method("get_weapon_fire_mode"):
		return clampi(int(room.call("get_weapon_fire_mode", mount_index)), WeaponFireMode.LINKED, WeaponFireMode.SENTRY)
	var fire_modes: Array = room.get("weapon_fire_modes")
	if mount_index >= 0 and mount_index < fire_modes.size():
		return clampi(int(fire_modes[mount_index]), WeaponFireMode.LINKED, WeaponFireMode.SENTRY)
	return WeaponFireMode.LINKED


func _weapon_mount_uses_automatic_fire(room: Resource, mount_index: int) -> bool:
	var fire_mode := _weapon_mount_fire_mode(room, mount_index)
	if fire_mode == WeaponFireMode.TRIGGER:
		return false
	return not player_direct_fire_active or fire_mode == WeaponFireMode.SENTRY


func _weapon_mount_accepts_manual_fire(room: Resource, mount_index: int) -> bool:
	return _weapon_mount_fire_mode(room, mount_index) != WeaponFireMode.SENTRY


func _weapon_mount_cooldown_key(room_id: StringName, mount_index: int) -> String:
	return "%s#%d" % [String(room_id), mount_index]


func _weapon_room_group_bonus(room: Resource) -> float:
	return 1.0 + minf(float(_weapon_mount_count(room) - 1) * 0.06, 0.30)


func _weapon_mount_room(room: Resource, mount_index: int) -> Resource:
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.is_empty() or mount_index < 0 or mount_index >= rects.size():
		return room
	var facings: Array = room.get("module_mount_facings")
	var facing := int(room.get("module_facing_quarters"))
	if mount_index < facings.size():
		facing = int(facings[mount_index])
	var signature := "%d:%d:%s:%d" % [room.get_instance_id(), mount_index, str(rects[mount_index]), facing]
	if weapon_mount_room_cache.has(signature):
		var cached: Resource = weapon_mount_room_cache[signature]
		if is_instance_valid(cached):
			return cached
	var mount_room := room.duplicate(false)
	var mount_rects: Array[Rect2i] = [rects[mount_index]]
	mount_room.set("grid_rects", mount_rects)
	mount_room.set("module_facing_quarters", facing)
	mount_room.set("module_mount_facings", [facing])
	mount_room.set("installed_piece_count", 1)
	mount_room.set_meta("source_room_id", StringName(room.get("room_id")))
	mount_room.set_meta("source_mount_index", mount_index)
	weapon_mount_room_cache[signature] = mount_room
	return mount_room


func _get_mount_data(layout: Resource, room: Resource, ship_position: Vector2, ship_rotation: float) -> Dictionary:
	_track_mount_layout(layout)
	var cache_key := _mount_geometry_cache_key(layout, room)
	if mount_geometry_cache.has(cache_key):
		return _mount_geometry_to_world(mount_geometry_cache[cache_key], ship_position, ship_rotation)
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var rects: Array[Rect2i] = room.get("grid_rects")
	var cells: Array[Vector2i] = []
	for grid_rect: Rect2i in rects:
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				cells.append(Vector2i(x, y))
	var average_cell_center := Vector2.ZERO
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, TACTICAL_CELL_SIZE)
	for cell: Vector2i in cells:
		average_cell_center += GRID_GEOMETRY.cell_rect(layout, cell, bounds, TACTICAL_CELL_SIZE).get_center()
	average_cell_center /= maxf(float(cells.size()), 1.0)
	var local_position := average_cell_center - geometry_size * 0.5
	var local_direction := Vector2.UP
	var resolved_facing := GRID_GEOMETRY.resolved_module_facing(layout, room)
	local_direction = Vector2.UP.rotated(float(resolved_facing) * PI * 0.5)
	var weapon: Resource = room.get("weapon_definition")
	var source_room_id := StringName(room.get_meta("source_room_id", room.get("room_id")))
	var source_mount_index := int(room.get_meta("source_mount_index", 0))
	var uses_authored_muzzle := _uses_authored_weapon_muzzle(room, weapon)
	# The standard-room renderer anchors a complete 2x2 weapon piece from the
	# first lattice cell, then gives that rendered rectangle the piece's full
	# size.  Do the same here.  Averaging the four cell centers is only
	# equivalent while every occupied cell has the same half-grid offset; on a
	# staggered hull it drifts the combat socket back toward the ship center
	# even though the cannon art remains anchored to the placed piece.
	var authored_socket_position := average_cell_center - geometry_size * 0.5
	if uses_authored_muzzle and not rects.is_empty():
		var authored_piece_rect: Rect2i = rects[0]
		var rendered_piece_rect := GRID_GEOMETRY.cell_rect(
			layout,
			authored_piece_rect.position,
			bounds,
			TACTICAL_CELL_SIZE
		)
		rendered_piece_rect.size = Vector2(authored_piece_rect.size) * TACTICAL_CELL_SIZE
		authored_socket_position = (
			WEAPON_MOUNT_SOCKET.standard_room_socket_position(rendered_piece_rect, resolved_facing)
			- geometry_size * 0.5
		)
	var authored_muzzle_offset := (
		_authored_weapon_muzzle_offset(weapon, resolved_facing)
		if uses_authored_muzzle
		else Vector2.ZERO
	)
	var coverage_quarters: Array[int] = GRID_GEOMETRY.weapon_coverage_quarters(layout, room, weapon)
	var coverage_directions: Array[Vector2] = []
	var coverage_mounts: Array[Dictionary] = []
	var occupied_cells: Dictionary = GRID_GEOMETRY.layout_cells(layout)
	for quarter: int in coverage_quarters:
		var quarter_local_direction := Vector2(GRID_GEOMETRY.quarter_direction(quarter))
		var quarter_world_direction := quarter_local_direction.rotated(ship_rotation)
		coverage_directions.append(quarter_world_direction)
		var exposed_edge_centers: Array[Vector2] = []
		for cell: Vector2i in cells:
			if GRID_GEOMETRY.face_contact_strength(
				layout,
				cell,
				GRID_GEOMETRY.quarter_direction(quarter),
				occupied_cells
			) >= 0.999:
				continue
			var edge_center := (
				GRID_GEOMETRY.cell_rect(layout, cell, bounds, TACTICAL_CELL_SIZE).get_center()
				- geometry_size * 0.5
				+ quarter_local_direction * TACTICAL_CELL_SIZE * 0.5
			)
			exposed_edge_centers.append(edge_center)
		if exposed_edge_centers.is_empty():
			continue
		var quarter_local_position := Vector2.ZERO
		for edge_center: Vector2 in exposed_edge_centers:
			quarter_local_position += edge_center
		quarter_local_position /= float(exposed_edge_centers.size())
		var desired_clearance := float(weapon.get("traverse_degrees"))
		if bool(weapon.get("uses_exposed_hull_edges")):
			desired_clearance = maxf(desired_clearance, 45.0)
		if desired_clearance <= 0.0:
			desired_clearance = fixed_weapon_alignment_degrees
		desired_clearance = clampf(desired_clearance, 0.0, 89.0)
		var clearance: Vector2 = GRID_GEOMETRY.weapon_face_clearance_degrees(
			layout, room, quarter, desired_clearance
		)
		var coverage_local_position := authored_socket_position if uses_authored_muzzle else quarter_local_position
		var coverage_muzzle_offset := (
			_authored_weapon_muzzle_offset(weapon, quarter)
			if uses_authored_muzzle
			else Vector2.ZERO
		)
		var coverage_world_position := ship_position + coverage_local_position.rotated(ship_rotation)
		var coverage_world_muzzle_offset := coverage_muzzle_offset.rotated(ship_rotation)
		coverage_mounts.append({
			"room_id": source_room_id,
			"mount_index": source_mount_index,
			"position": coverage_world_position,
			"direction": quarter_world_direction,
			"muzzle_offset": coverage_world_muzzle_offset if uses_authored_muzzle else null,
			"muzzle_position": coverage_world_position + coverage_world_muzzle_offset if uses_authored_muzzle else null,
			"quarter": quarter,
			"minimum_offset_degrees": clearance.x,
			"maximum_offset_degrees": clearance.y,
			"line_of_fire_clear": GRID_GEOMETRY.weapon_face_center_is_clear(layout, room, quarter),
		})
	if String(room.get("type_name")) in ["WEAPONS", "HANGAR"] and not cells.is_empty():
		# Weapons fire and hangars launch from the selected forward-facing edge,
		# rather than the center of a potentially large grouped module. An authored
		# muzzle marker can replace this calculated edge point later.
		var extreme_projection := -INF
		var edge_centers: Array[Vector2] = []
		for cell: Vector2i in cells:
			var cell_center := GRID_GEOMETRY.cell_rect(layout, cell, bounds, TACTICAL_CELL_SIZE).get_center() - geometry_size * 0.5
			var projection := cell_center.dot(local_direction)
			if projection > extreme_projection + 0.01:
				extreme_projection = projection
				edge_centers = [cell_center]
			elif is_equal_approx(projection, extreme_projection):
				edge_centers.append(cell_center)
		local_position = Vector2.ZERO
		for edge_center: Vector2 in edge_centers:
			local_position += edge_center
		local_position /= maxf(float(edge_centers.size()), 1.0)
		local_position += local_direction * TACTICAL_CELL_SIZE * 0.5
	if uses_authored_muzzle:
		# Keep combat geometry locked to the same socket used to draw the sprite.
		# The actual firing direction rotates this offset with the cannon, so shots
		# begin at the barrel tip even when the mount traverses within its arc.
		local_position = authored_socket_position
	var world_mount_position := ship_position + local_position.rotated(ship_rotation)
	var world_muzzle_offset := authored_muzzle_offset.rotated(ship_rotation)
	var world_mount := {
		"room_id": source_room_id,
		"mount_index": source_mount_index,
		"position": world_mount_position,
		"direction": local_direction.rotated(ship_rotation),
		"muzzle_offset": world_muzzle_offset if uses_authored_muzzle else null,
		"muzzle_position": world_mount_position + world_muzzle_offset if uses_authored_muzzle else null,
		"coverage_directions": coverage_directions,
		"coverage_mounts": coverage_mounts,
		"exposed_edge_count": GRID_GEOMETRY.room_exposed_quarters(layout, room).size(),
		"muzzle_clearance": authored_muzzle_offset.length() if uses_authored_muzzle else (2.0 if String(room.get("type_name")) in ["WEAPONS", "HANGAR"] else 16.0),
	}
	var local_geometry := _mount_geometry_to_local(world_mount, ship_position, ship_rotation)
	mount_geometry_cache[cache_key] = local_geometry
	return world_mount


## Every authored weapon uses this same contract: the art supplies a socket-to-tip
## vector, and combat rotates that exact vector by the installed grid facing.
## This keeps new weapon types from needing bespoke projectile-origin code.
func _uses_authored_weapon_muzzle(room: Resource, weapon: Resource = null) -> bool:
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return false
	var definition: Resource = weapon if weapon != null else room.get("weapon_definition")
	if definition == null:
		return false
	var has_mount_scene := definition.get("mount_visual_scene") is PackedScene
	if not has_mount_scene and Vector2(definition.get("authored_muzzle_offset_pixels")).is_zero_approx():
		return false
	var rects: Array[Rect2i] = room.get("grid_rects")
	return rects.size() == 1 and rects[0].size == Vector2i(2, 2)


func _authored_weapon_muzzle_offset(weapon: Resource, facing_quarters: int) -> Vector2:
	if weapon == null:
		return Vector2.ZERO
	var source_offset := _weapon_mount_scene_muzzle_offset(weapon)
	if source_offset.is_zero_approx():
		var source_pixels := maxf(float(weapon.get("authored_room_source_pixels")), 1.0)
		source_offset = Vector2(weapon.get("authored_muzzle_offset_pixels")) * ((TACTICAL_CELL_SIZE * 2.0) / source_pixels)
	# Aseprite weapon sources face down. The room renderer applies this identical
	# half-turn before adding the installed N/E/S/W rotation.
	var authored_rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	return source_offset.rotated(authored_rotation)


## Reads the actual Muzzle marker from the weapon scene. This is cached per
## definition, so firing never instantiates scene objects during combat.
func _weapon_mount_scene_muzzle_offset(weapon: Resource) -> Vector2:
	var mount_scene := weapon.get("mount_visual_scene") as PackedScene
	if mount_scene == null:
		return Vector2.ZERO
	var scene_id := mount_scene.get_instance_id()
	if weapon_scene_muzzle_offset_cache.has(scene_id):
		return weapon_scene_muzzle_offset_cache[scene_id]
	var probe := mount_scene.instantiate() as Node2D
	if probe == null:
		return Vector2.ZERO
	var offset := Vector2.ZERO
	if probe.has_method("get_authored_muzzle_offset"):
		offset = probe.call("get_authored_muzzle_offset")
	else:
		var muzzle := probe.get_node_or_null("Muzzle") as Marker2D
		if muzzle != null:
			offset = probe.transform.basis_xform(muzzle.position)
	probe.free()
	weapon_scene_muzzle_offset_cache[scene_id] = offset
	return offset


func _track_mount_layout(layout: Resource) -> void:
	var layout_id := layout.get_instance_id()
	if tracked_mount_layouts.has(layout_id):
		return
	tracked_mount_layouts[layout_id] = weakref(layout)
	if not layout.changed.is_connected(_on_mount_layout_changed):
		layout.changed.connect(_on_mount_layout_changed)


func _on_mount_layout_changed() -> void:
	# Hull topology and authored facings are static during combat. Any drydock
	# edit invalidates the small geometry cache before the next engagement.
	mount_geometry_cache.clear()
	weapon_mount_room_cache.clear()
	propulsion_profile_cache.clear()
	call_deferred("_prewarm_tracked_mount_layouts")


func _prewarm_tracked_mount_layouts() -> void:
	for weak_layout_value: Variant in tracked_mount_layouts.values():
		var weak_layout := weak_layout_value as WeakRef
		var layout := weak_layout.get_ref() as Resource if weak_layout != null else null
		if layout != null:
			_prewarm_layout_mount_geometry(layout)


func _prewarm_layout_mount_geometry(layout: Resource) -> void:
	if layout == null:
		return
	for room: Resource in layout.get("rooms"):
		var room_type := String(room.get("type_name"))
		if room_type == "WEAPONS":
			for mount_index: int in range(_weapon_mount_count(room)):
				_get_mount_data(layout, _weapon_mount_room(room, mount_index), Vector2.ZERO, 0.0)
		elif room_type == "HANGAR":
			_get_mount_data(layout, room, Vector2.ZERO, 0.0)


func _mount_geometry_cache_key(layout: Resource, room: Resource) -> String:
	var weapon: Resource = room.get("weapon_definition")
	# Combined rooms create lightweight per-piece views of the same room.  Their
	# Resource identity is not a reliable discriminator after duplication/cache
	# reuse, so the physical source mount must be part of the geometry key.
	var source_room_id := String(room.get_meta("source_room_id", room.get("room_id")))
	var source_mount_index := int(room.get_meta("source_mount_index", 0))
	return "%d:%d:%s:%d:%s:%d:%d" % [
		layout.get_instance_id(),
		room.get_instance_id(),
		str(room.get("grid_rects")),
		int(room.get("module_facing_quarters")),
		source_room_id,
		source_mount_index,
		weapon.get_instance_id() if weapon != null else 0,
	]


func _mount_geometry_to_local(world_mount: Dictionary, ship_position: Vector2, ship_rotation: float) -> Dictionary:
	var local_mount := world_mount.duplicate(true)
	local_mount["position"] = (Vector2(world_mount["position"]) - ship_position).rotated(-ship_rotation)
	local_mount["direction"] = Vector2(world_mount["direction"]).rotated(-ship_rotation)
	if world_mount.get("muzzle_offset") is Vector2:
		local_mount["muzzle_offset"] = Vector2(world_mount["muzzle_offset"]).rotated(-ship_rotation)
	if world_mount.get("muzzle_position") is Vector2:
		local_mount["muzzle_position"] = (Vector2(world_mount["muzzle_position"]) - ship_position).rotated(-ship_rotation)
	if world_mount.get("muzzle_direction") is Vector2:
		local_mount["muzzle_direction"] = Vector2(world_mount["muzzle_direction"]).rotated(-ship_rotation)
	var local_directions: Array[Vector2] = []
	for world_direction: Vector2 in world_mount.get("coverage_directions", []):
		local_directions.append(world_direction.rotated(-ship_rotation))
	local_mount["coverage_directions"] = local_directions
	var local_coverage_mounts: Array[Dictionary] = []
	for world_coverage_value: Variant in world_mount.get("coverage_mounts", []):
		var world_coverage: Dictionary = world_coverage_value
		var local_coverage := world_coverage.duplicate(true)
		local_coverage["position"] = (Vector2(world_coverage["position"]) - ship_position).rotated(-ship_rotation)
		local_coverage["direction"] = Vector2(world_coverage["direction"]).rotated(-ship_rotation)
		if world_coverage.get("muzzle_offset") is Vector2:
			local_coverage["muzzle_offset"] = Vector2(world_coverage["muzzle_offset"]).rotated(-ship_rotation)
		if world_coverage.get("muzzle_position") is Vector2:
			local_coverage["muzzle_position"] = (Vector2(world_coverage["muzzle_position"]) - ship_position).rotated(-ship_rotation)
		if world_coverage.get("muzzle_direction") is Vector2:
			local_coverage["muzzle_direction"] = Vector2(world_coverage["muzzle_direction"]).rotated(-ship_rotation)
		local_coverage_mounts.append(local_coverage)
	local_mount["coverage_mounts"] = local_coverage_mounts
	return local_mount


func _mount_geometry_to_world(local_mount: Dictionary, ship_position: Vector2, ship_rotation: float) -> Dictionary:
	var world_mount := local_mount.duplicate(true)
	world_mount["position"] = ship_position + Vector2(local_mount["position"]).rotated(ship_rotation)
	world_mount["direction"] = Vector2(local_mount["direction"]).rotated(ship_rotation)
	if local_mount.get("muzzle_offset") is Vector2:
		world_mount["muzzle_offset"] = Vector2(local_mount["muzzle_offset"]).rotated(ship_rotation)
	if local_mount.get("muzzle_position") is Vector2:
		world_mount["muzzle_position"] = ship_position + Vector2(local_mount["muzzle_position"]).rotated(ship_rotation)
	if local_mount.get("muzzle_direction") is Vector2:
		world_mount["muzzle_direction"] = Vector2(local_mount["muzzle_direction"]).rotated(ship_rotation)
	var world_directions: Array[Vector2] = []
	for local_direction: Vector2 in local_mount.get("coverage_directions", []):
		world_directions.append(local_direction.rotated(ship_rotation))
	world_mount["coverage_directions"] = world_directions
	var world_coverage_mounts: Array[Dictionary] = []
	for local_coverage_value: Variant in local_mount.get("coverage_mounts", []):
		var local_coverage: Dictionary = local_coverage_value
		var world_coverage := local_coverage.duplicate(true)
		world_coverage["position"] = ship_position + Vector2(local_coverage["position"]).rotated(ship_rotation)
		world_coverage["direction"] = Vector2(local_coverage["direction"]).rotated(ship_rotation)
		if local_coverage.get("muzzle_offset") is Vector2:
			world_coverage["muzzle_offset"] = Vector2(local_coverage["muzzle_offset"]).rotated(ship_rotation)
		if local_coverage.get("muzzle_position") is Vector2:
			world_coverage["muzzle_position"] = ship_position + Vector2(local_coverage["muzzle_position"]).rotated(ship_rotation)
		if local_coverage.get("muzzle_direction") is Vector2:
			world_coverage["muzzle_direction"] = Vector2(local_coverage["muzzle_direction"]).rotated(ship_rotation)
		world_coverage_mounts.append(world_coverage)
	world_mount["coverage_mounts"] = world_coverage_mounts
	return world_mount


func _get_mount_direction(layout: Resource, cell: Vector2i) -> Vector2:
	var occupied := _layout_cells(layout)
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, 1.0)
	var local_center := GRID_GEOMETRY.cell_rect(layout, cell, bounds, 1.0).get_center() - geometry_size * 0.5
	var candidates: Array[Vector2] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if GRID_GEOMETRY.face_contact_strength(layout, cell, direction, occupied) < 0.999:
			candidates.append(Vector2(direction))
	if candidates.is_empty():
		return Vector2.UP
	var best_direction := candidates[0]
	var best_score := -INF
	for direction: Vector2 in candidates:
		var score := direction.dot(local_center.normalized())
		if score > best_score:
			best_score = score
			best_direction = direction
	return best_direction


func _layout_cells(layout: Resource) -> Dictionary:
	var occupied: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		var rects: Array[Rect2i] = room.get("grid_rects")
		for grid_rect: Rect2i in rects:
			for y: int in range(grid_rect.position.y, grid_rect.end.y):
				for x: int in range(grid_rect.position.x, grid_rect.end.x):
					occupied[Vector2i(x, y)] = true
	return occupied
