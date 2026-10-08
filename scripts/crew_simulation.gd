class_name CrewSimulation
extends Node

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const CREW_NAMES := ["ADA", "BOONE", "CYRA", "DEX", "ELI", "FEN", "GAIL", "HOLT", "IONA", "JAX", "KIRA", "LUZ"]
const BRIDGE_CREW_LAYOUT := preload("res://scenes/room_layouts/standard/bridge_room_layout.tscn")
const REACTOR_CREW_LAYOUT := preload("res://scenes/room_layouts/standard/reactor_room_layout.tscn")
const THRUSTER_CREW_LAYOUT := preload("res://scenes/room_layouts/standard/thruster_room_layout.tscn")
const SHIELD_CREW_LAYOUT := preload("res://scenes/room_layouts/standard/shield_room_layout.tscn")
# Effective half-width of a moving crew member in room-layout coordinates.
# This stays small enough for authored bridge/reactor stations beside machinery.
const CREW_BODY_CLEARANCE := 0.075

enum StaffingPriority {
	STANDBY,
	AUTO,
	PRIORITY,
}

@export_category("Starting Crew")
## Number of placeholder crew agents created when the game begins.
@export_range(1, 64, 1) var starting_crew_count := 8
## Maximum supported crew contributed by each Crew Quarters grid cell.
@export_range(1, 32, 1) var crew_capacity_per_quarters_cell := 8
## Editor-authored movement, work-slot, and dot-visual settings.
@export var crew_definition: Resource
## Editor-authored vitals, skill list, and equipment-slot rules shared by newly created crew.
@export var crew_rules: Resource

@export_category("Crew Assignment Audio")
## Confirmation sound played whenever a crew member receives a valid room assignment. Empty is safe.
@export var assignment_sound: AudioStream
## Volume of the assignment confirmation, independent of world-camera zoom.
@export_range(-40.0, 12.0, 0.5) var assignment_volume_db := -4.0

@export_category("Automatic Staffing")
## How often the autonomous staffing scheduler checks room demand and crew availability.
@export_range(0.1, 5.0, 0.1) var staffing_rebalance_seconds := 0.75

@export_category("Crew Quarters Rest")
## Off-duty crew occasionally claim an open berth instead of pacing the ship.
@export_range(0.0, 1.0, 0.05) var rest_chance := 0.10
@export_range(2.0, 60.0, 0.5) var minimum_rest_seconds := 7.0
@export_range(2.0, 90.0, 0.5) var maximum_rest_seconds := 16.0

@export_category("Reserve Crew Routine")
## Jobless reserve crew hold a useful post for a while instead of constantly
## choosing another destination and making the interior look frantic.
@export_range(5.0, 120.0, 0.5) var minimum_reserve_duty_seconds := 20.0
@export_range(5.0, 180.0, 0.5) var maximum_reserve_duty_seconds := 45.0

@export_category("Crew Reinforcements")
## Time required for one Crew Quarters grid to regenerate one missing crew member.
## Injured crew do not count as missing; Medical remains the faster recovery route.
@export_range(5.0, 300.0, 1.0) var crew_reinforcement_seconds := 60.0
## Interior arrival cue played when a Crew Quarters cycle completes. Empty is safe.
@export var crew_reinforcement_sound: AudioStream
## Volume of the Crew Quarters arrival cue. This is an interior ship sound, not a world-space effect.
@export_range(-40.0, 12.0, 0.5) var crew_reinforcement_volume_db := -5.0
## Duration of the forming/arrival effect drawn over a newly produced crew member.
@export_range(0.25, 4.0, 0.05) var crew_reinforcement_visual_seconds := 1.25

var crew_members: Array[Dictionary] = []
var work_slots: Array[Dictionary] = []
var ambient_slots: Array[Dictionary] = []
var crew_spawn_slots: Array[Dictionary] = []
var rest_slots: Array[Dictionary] = []
var furniture_obstacles: Array[Rect2] = []
var furniture_obstacle_polygons: Array[PackedVector2Array] = []
## The captain is a command entity, not a normal staffing resource. Keeping the
## captain outside crew_members prevents auto-staffing, casualties, and capacity
## accounting from silently treating the command chair as another crew slot.
var captain_member: Dictionary = {}
var captain_slot: Dictionary = {}
var next_crew_id := 1
var next_job_id := 1
var damage_control_jobs: Array[Dictionary] = []
var random := RandomNumberGenerator.new()
var room_staffing_priorities: Dictionary = {}
var staffing_rebalance_remaining := 0.0
var crew_reinforcement_timers: Dictionary = {}
## Doors currently being held by crew crossings. A door is released only after
## the last crew member using that threshold has cleared it.
var crew_held_doors: Dictionary = {}
## A doorway is a one-body-wide traffic lane. Crew do not collide with one
## another in rooms, but only one member owns a threshold until they reach the
## far-side landing point. This prevents two agents from being projected into
## opposite wall corners while trying to cross at the same time.
var doorway_reservations: Dictionary = {}


func _ready() -> void:
	add_to_group("crew_simulation")
	random.randomize()
	call_deferred("_initialize_crew")


func _physics_process(delta: float) -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.structural_state == null or crew_definition == null:
		return
	staffing_rebalance_remaining -= delta
	if staffing_rebalance_remaining <= 0.0:
		rebalance_staffing()
		staffing_rebalance_remaining = staffing_rebalance_seconds
	_update_crew_reinforcements(ship, delta)
	# Drop an invalid threshold owner before crew choose this frame's movement.
	# A replacement can then claim it immediately, without two agents making the
	# same decision during one update loop.
	_sync_doorway_reservations()
	for member: Dictionary in crew_members:
		if float(member.get("spawn_visual_remaining", 0.0)) > 0.0:
			member["spawn_visual_remaining"] = maxf(float(member["spawn_visual_remaining"]) - delta, 0.0)
		if bool(member.get("ejected", false)):
			continue
		if bool(member.get("dead", false)):
			continue
		if bool(member.get("incapacitated", false)):
			_update_incapacitated_member(member, ship.structural_state, delta)
			if int(member.get("carried_by", 0)) <= 0:
				_update_decompression(member, ship.structural_state, delta)
			continue
		if int(member.get("rescue_patient_id", 0)) > 0:
			_update_rescuer(member, ship.structural_state, delta)
			continue
		_maybe_begin_medical_visit(member, ship.structural_state)
		if _update_medical_patient(member, delta):
			continue
		if int(member.get("active_job_id", 0)) > 0:
			_update_job_member(member, ship.structural_state, delta)
		else:
			_update_member(member, ship.structural_state, delta)
		_update_decompression(member, ship.structural_state, delta)
		_update_oxygen_exposure(member, ship.structural_state, delta)
		if float(member.get("health", 0.0)) <= 0.0:
			_incapacitate_member(member, ship.structural_state)
	_update_damage_control_jobs(ship, delta)
	_sync_crew_held_doors(ship.structural_state)
	_sync_doorway_reservations()


func _initialize_crew() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null or crew_definition == null or crew_rules == null:
		return
	_build_work_slots(ship.ship_layout)
	if ambient_slots.is_empty():
		return
	var supported_starting_crew := mini(starting_crew_count, get_crew_capacity())
	for index: int in range(supported_starting_crew):
		var slot: Dictionary = _preferred_crew_spawn_slot(index)
		if slot.is_empty():
			break
		_spawn_crew_member(slot, index)
	rebalance_staffing()


func _spawn_crew_member(slot: Dictionary, sequence_index: int = -1, with_arrival_effect: bool = false) -> bool:
	if slot.is_empty() or crew_rules == null or crew_definition == null:
		return false
	var member_id := next_crew_id
	next_crew_id += 1
	var generated_stats: Dictionary = {}
	for stat_definition: Resource in crew_rules.get("stats"):
		var base_value := float(stat_definition.get("base_value"))
		generated_stats[stat_definition.get("stat_id")] = clampf(
			base_value,
			float(stat_definition.get("minimum_value")),
			float(stat_definition.get("maximum_value"))
		)
	var equipment_slots: Array[Resource] = []
	equipment_slots.resize(int(crew_rules.get("equipment_slot_count")))
	equipment_slots.fill(null)
	var roster_index := sequence_index if sequence_index >= 0 else member_id - 1
	crew_members.append({
		"id": member_id,
		"name": CREW_NAMES[roster_index % CREW_NAMES.size()],
		"position": slot["position"],
		"facing_direction": slot.get("facing", Vector2.UP),
		"current_cell": slot["cell"],
		"target_slot": slot,
		"path": [],
		"path_index": 0,
		"idle_time": random.randf_range(0.5, float(crew_definition.get("maximum_idle_seconds"))) + float(roster_index % 6) * 0.35,
		"spawn_visual_remaining": crew_reinforcement_visual_seconds if with_arrival_effect else 0.0,
		"spawn_visual_duration": crew_reinforcement_visual_seconds,
		"state": "OFF DUTY",
		"reserve_role": "",
		"reserve_task": "",
		"assigned_room_id": &"",
		"at_assignment": false,
		"color_shift": float(roster_index % 5) * 0.035,
		"decompression_velocity": Vector2.ZERO,
		"ejected": false,
		"maximum_health": float(crew_rules.get("starting_maximum_health")),
		"health": float(crew_rules.get("starting_maximum_health")),
		"incapacitated": false,
		"incapacitated_seconds": 0.0,
		"dead": false,
		"seeking_medical": false,
		"rescue_patient_id": 0,
		"rescue_phase": "",
		"carried_by": 0,
		"morale": float(crew_rules.get("starting_morale")),
		"stats": generated_stats,
		"equipment": equipment_slots,
		"portrait_scene": crew_rules.get("default_portrait_scene"),
		"active_job_id": 0,
		"job_phase": "",
		"equipped_from_room_id": &"",
		"has_repair_gear": false,
		"has_environmental_gear": false,
		"equip_remaining": 0.0,
		"at_job": false,
		"evacuating": false,
		"resting": false,
		"rest_remaining": 0.0,
	})
	staffing_rebalance_remaining = 0.0
	return true


func fill_crew_to_capacity() -> int:
	var capacity := get_crew_capacity()
	var spawned := 0
	while get_living_crew_count() < capacity:
		var slot := _preferred_crew_spawn_slot(next_crew_id)
		if slot.is_empty() or not _spawn_crew_member(slot, -1, true):
			break
		spawned += 1
	if spawned > 0:
		staffing_rebalance_remaining = 0.0
		rebalance_staffing()
		_play_reinforcement_sound(spawned)
	return spawned


func reset_crew_for_new_run(requested_count: int = 8) -> int:
	crew_members.clear()
	damage_control_jobs.clear()
	crew_reinforcement_timers.clear()
	room_staffing_priorities.clear()
	next_crew_id = 1
	next_job_id = 1
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null or crew_definition == null:
		return 0
	_build_work_slots(ship.ship_layout)
	var count := mini(maxi(requested_count, 1), get_crew_capacity())
	for index: int in range(count):
		var slot := _preferred_crew_spawn_slot(index)
		if slot.is_empty() or not _spawn_crew_member(slot, index, true):
			break
	rebalance_staffing()
	return crew_members.size()


func _update_crew_reinforcements(ship: Node, delta: float) -> void:
	if ship.ship_layout == null or crew_rules == null or crew_definition == null:
		return
	var active_quarters: Array[String] = []
	var active_quarter_cells: Dictionary = {}
	for room: Resource in ship.ship_layout.get("rooms"):
		if String(room.get("type_name")) not in ["CREW", "CREW_QUARTERS"]:
			continue
		var room_id: StringName = room.get("room_id")
		var room_data: Dictionary = ship.get_room_data(room_id)
		var health_ratio: float = (
			float(room_data.get("current_health", 0.0))
			/ maxf(float(room_data.get("maximum_health", 1.0)), 0.001)
		)
		var pressure: float = float(ship.structural_state.get_room_pressure(room_id))
		if health_ratio <= 0.25 or pressure <= 0.2 or float(ship.get_room_power_factor(room_id)) <= 0.2:
			continue
		var quarter_cells: Array[Vector2i] = []
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					quarter_cells.append(Vector2i(x, y))
		quarter_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var berth_modules := _crew_quarters_module_count(room)
		for module_index: int in range(berth_modules):
			var quarters_key := "%s:%d" % [String(room_id), module_index]
			active_quarters.append(quarters_key)
			active_quarter_cells[quarters_key] = quarter_cells[mini(module_index, quarter_cells.size() - 1)]
	for timer_key: Variant in crew_reinforcement_timers.keys().duplicate():
		if not active_quarters.has(String(timer_key)):
			crew_reinforcement_timers.erase(timer_key)
	var living_count: int = get_living_crew_count()
	var capacity: int = get_crew_capacity()
	var recovery_candidate: Dictionary = _crew_member_needing_slow_recovery()
	if living_count >= capacity and recovery_candidate.is_empty():
		for quarters_key: String in active_quarters:
			crew_reinforcement_timers[quarters_key] = 0.0
		return
	# All online quarter cells form one synchronized berth bank. Adding a second
	# connected grid therefore adds a second simultaneous arrival to the cycle,
	# instead of merely extending the ship's maximum roster.
	var cycle_elapsed := 0.0
	for quarters_key: String in active_quarters:
		cycle_elapsed = maxf(cycle_elapsed, float(crew_reinforcement_timers.get(quarters_key, 0.0)))
	cycle_elapsed = minf(cycle_elapsed + delta, crew_reinforcement_seconds)
	for quarters_key: String in active_quarters:
		crew_reinforcement_timers[quarters_key] = cycle_elapsed
	if cycle_elapsed < crew_reinforcement_seconds:
		return
	var completed_arrivals := 0
	for berth_index: int in range(active_quarters.size()):
		var succeeded := false
		var source_cell: Vector2i = active_quarter_cells.get(active_quarters[berth_index], Vector2i.ZERO)
		if living_count < capacity:
			var spawn_slot: Dictionary = _preferred_reinforcement_slot(source_cell)
			succeeded = not spawn_slot.is_empty() and _spawn_crew_member(spawn_slot, -1, true)
			if succeeded:
				living_count += 1
		else:
			recovery_candidate = _crew_member_needing_slow_recovery()
			if not recovery_candidate.is_empty():
				var recovery_slot: Dictionary = _preferred_reinforcement_slot(source_cell, int(recovery_candidate["id"]))
				succeeded = not recovery_slot.is_empty() and _restore_crew_member_at_quarters(recovery_candidate, recovery_slot)
				if succeeded:
					recovery_candidate["spawn_visual_remaining"] = crew_reinforcement_visual_seconds
					recovery_candidate["spawn_visual_duration"] = crew_reinforcement_visual_seconds
		if not succeeded:
			break
		completed_arrivals += 1
		if living_count >= capacity and _crew_member_needing_slow_recovery().is_empty():
			break
	for quarters_key: String in active_quarters:
		crew_reinforcement_timers[quarters_key] = 0.0 if completed_arrivals > 0 else crew_reinforcement_seconds
	if completed_arrivals > 0:
		_play_reinforcement_sound(completed_arrivals)


func _play_reinforcement_sound(arrival_count: int) -> void:
	if crew_reinforcement_sound == null or arrival_count <= 0:
		return
	var player := AudioStreamPlayer.new()
	player.stream = crew_reinforcement_sound
	player.volume_db = crew_reinforcement_volume_db
	player.pitch_scale = clampf(1.0 + float(arrival_count - 1) * 0.025, 1.0, 1.12)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _crew_member_needing_slow_recovery() -> Dictionary:
	var candidate: Dictionary = {}
	var lowest_health_ratio: float = INF
	for member: Dictionary in crew_members:
		if bool(member.get("dead", false)) or bool(member.get("ejected", false)):
			continue
		var maximum_health: float = maxf(float(member.get("maximum_health", 1.0)), 0.001)
		var health_ratio: float = float(member.get("health", maximum_health)) / maximum_health
		if not bool(member.get("incapacitated", false)) and health_ratio >= 0.999:
			continue
		if health_ratio < lowest_health_ratio:
			lowest_health_ratio = health_ratio
			candidate = member
	return candidate


func _restore_crew_member_at_quarters(member: Dictionary, slot: Dictionary) -> bool:
	if member.is_empty() or slot.is_empty():
		return false
	var member_id: int = int(member["id"])
	for rescuer: Dictionary in crew_members:
		if int(rescuer.get("rescue_patient_id", 0)) == member_id:
			_cancel_rescue(rescuer)
	member["position"] = slot["position"]
	member["facing_direction"] = slot.get("facing", Vector2.UP)
	member["current_cell"] = slot["cell"]
	member["target_slot"] = slot
	member["path"] = []
	member["path_index"] = 0
	member["health"] = float(member.get("maximum_health", 1.0))
	member["incapacitated"] = false
	member["incapacitated_seconds"] = 0.0
	member["seeking_medical"] = false
	member["carried_by"] = 0
	member["assigned_room_id"] = &""
	member["at_assignment"] = false
	member["active_job_id"] = 0
	member["at_job"] = false
	member["evacuating"] = false
	member["state"] = "RETURNED TO DUTY"
	member["idle_time"] = 1.5
	staffing_rebalance_remaining = 0.0
	return true


func get_reinforcement_status() -> Dictionary:
	var missing_crew: int = maxi(get_crew_capacity() - get_living_crew_count(), 0)
	var has_injured: bool = not _crew_member_needing_slow_recovery().is_empty()
	var active_sources: int = crew_reinforcement_timers.size()
	if active_sources <= 0 or (missing_crew <= 0 and not has_injured):
		return {"active": false, "sources": active_sources, "remaining": 0.0, "mode": ""}
	var greatest_elapsed: float = 0.0
	for elapsed_value: Variant in crew_reinforcement_timers.values():
		greatest_elapsed = maxf(greatest_elapsed, float(elapsed_value))
	return {
		"active": true,
		"sources": active_sources,
		"remaining": maxf(crew_reinforcement_seconds - greatest_elapsed, 0.0),
		"duration": crew_reinforcement_seconds,
		"mode": "REINFORCEMENT" if missing_crew > 0 else "SLOW RECOVERY",
	}


func refresh_work_slots(layout: Resource) -> void:
	if layout == null or crew_definition == null:
		return
	_build_work_slots(layout)
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship) and ship.structural_state != null:
		_reconcile_crew_after_layout_change(ship.structural_state)
	staffing_rebalance_remaining = 0.0
	rebalance_staffing()


func _reconcile_crew_after_layout_change(structure: ShipStructuralState) -> void:
	# Refit can rebuild the door dictionaries while a crew member is physically
	# inside a threshold. Door stage and reservation data belongs to the old
	# topology, so resume everyone from a certified room-side landing instead of
	# carrying a half-finished crossing into the new hull.
	for held_door_value: Variant in crew_held_doors.keys():
		var held_door_id := String(held_door_value)
		if structure.doors.has(held_door_id):
			structure.request_hazard_door_override(held_door_id, false)
			structure.request_door_open(held_door_id, false)
	crew_held_doors.clear()
	doorway_reservations.clear()
	for member: Dictionary in crew_members:
		if bool(member.get("ejected", false)):
			continue
		_stabilize_member_after_layout_change(member, structure)
		var current_cell: Vector2i = member.get("current_cell", Vector2i.ZERO)
		if not structure.cell_rooms.has(current_cell):
			var rescued_cell := _nearest_existing_cell(structure, member.get("position", Vector2.ZERO))
			if rescued_cell == Vector2i(2147483647, 2147483647):
				member["ejected"] = true
				member["assigned_room_id"] = &""
				member["active_job_id"] = 0
				member["path"] = []
				member["state"] = "EJECTED INTO SPACE"
				continue
			member["current_cell"] = rescued_cell
			member["position"] = _cell_center(structure.layout, rescued_cell)
			member["path"] = []
			member["path_index"] = 0
			member["at_assignment"] = false
			member["at_job"] = false
			member["state"] = "RELOCATING"
		var assigned_room: StringName = member.get("assigned_room_id", &"")
		if assigned_room != &"" and get_work_slots_for_room(assigned_room).is_empty():
			member["assigned_room_id"] = &""
			member["target_slot"] = {
				"room_id": structure.cell_rooms.get(member["current_cell"], &""),
				"cell": member["current_cell"],
				"slot_index": -1,
				"position": member["position"],
			}
			member["path"] = []
			member["path_index"] = 0
			member["at_assignment"] = false
			member["state"] = "ROOM REMOVED"
			continue
		var target_slot: Dictionary = member.get("target_slot", {})
		var target_cell: Vector2i = target_slot.get("cell", Vector2i.ZERO)
		var target_room: StringName = structure.cell_rooms.get(target_cell, &"")
		var assigned_target_moved := assigned_room != &"" and target_room != assigned_room
		if not target_slot.is_empty() and (not structure.cell_rooms.has(target_cell) or assigned_target_moved):
			if assigned_target_moved:
				member["assigned_room_id"] = &""
			member["path"] = []
			member["path_index"] = 0
			member["at_assignment"] = false
			member["target_slot"] = {
				"room_id": structure.cell_rooms.get(member["current_cell"], &""),
				"cell": member["current_cell"],
				"slot_index": -1,
				"position": member["position"],
			}
			member["state"] = "TARGET REMOVED"
		var cleaned_path: Array = []
		for path_cell: Vector2i in member.get("path", []):
			if structure.cell_rooms.has(path_cell):
				cleaned_path.append(path_cell)
		if cleaned_path.size() != (member.get("path", []) as Array).size():
			member["path"] = cleaned_path
			member["path_index"] = mini(int(member.get("path_index", 0)), cleaned_path.size())


func _stabilize_member_after_layout_change(member: Dictionary, structure: ShipStructuralState) -> void:
	var current_cell: Vector2i = member.get("current_cell", Vector2i.ZERO)
	if not structure.cell_rooms.has(current_cell):
		_clear_member_door_crossing_state(member)
		return
	var crossing_door_id := String(member.get("door_crossing_id", ""))
	if crossing_door_id.is_empty():
		# Defensive fallback for saves or old runtime states where crossing metadata
		# was already lost even though the visual body still occupies a threshold.
		var member_position := Vector2(member.get("position", Vector2.ZERO))
		for door_value: Variant in structure.doors.values():
			var door: Dictionary = door_value
			var cells: Array = door.get("cells", [])
			if not cells.has(current_cell):
				continue
			var candidate_id := String(door.get("id", ""))
			if member_position.distance_to(structure.get_door_center(candidate_id)) <= 0.18:
				crossing_door_id = candidate_id
				break
	if crossing_door_id.is_empty():
		return
	var clearance := CREW_BODY_CLEARANCE * 2.0
	var safe_position := _safe_cell_navigation_point(structure.layout, current_cell)
	if structure.doors.has(crossing_door_id):
		var room_side_landing := structure.get_door_approach_point(
			crossing_door_id,
			current_cell,
			maxf(clearance, 0.16)
		)
		if not _position_blocked_by_furniture(room_side_landing):
			safe_position = room_side_landing
	member["position"] = safe_position
	member["state"] = "ROUTE RECALIBRATED"
	_clear_member_door_crossing_state(member, crossing_door_id)
	member.erase("furniture_waypoint")
	member.erase("furniture_navigation_leg")
	member.erase("blocked_navigation_time")
	member.erase("navigation_progress_target")
	member.erase("navigation_progress_best_distance")
	member.erase("navigation_stall_time")
	member.erase("navigation_recovery_count")


func _nearest_existing_cell(structure: ShipStructuralState, logical_position: Vector2) -> Vector2i:
	var best_cell := Vector2i(2147483647, 2147483647)
	var best_distance := INF
	for cell_value: Variant in structure.cell_rooms.keys():
		var cell: Vector2i = cell_value
		var distance := logical_position.distance_squared_to(_cell_center(structure.layout, cell))
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	return best_cell


func _update_oxygen_exposure(member: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	var room_id: StringName = structure.cell_rooms.get(member["current_cell"], &"")
	if room_id == &"":
		return
	var pressure := structure.get_room_pressure(room_id)
	var hazard_threshold := float(crew_rules.get("oxygen_hazard_threshold"))
	if pressure < hazard_threshold:
		var severity := 1.0 - pressure / maxf(hazard_threshold, 0.001)
		var protection := _vacuum_damage_reduction(member)
		member["health"] = maxf(float(member["health"]) - float(crew_rules.get("vacuum_damage_per_second")) * severity * (1.0 - protection) * delta, 0.0)
		var health_percentage := 100.0 * float(member["health"]) / maxf(float(member["maximum_health"]), 0.001)
		var environmental_panic := pressure <= float(crew_rules.get("evacuation_trigger_oxygen")) and not _permits_vacuum_work(member)
		if (environmental_panic or health_percentage <= float(crew_rules.get("evacuation_health_percentage"))) and not bool(member.get("evacuating", false)):
			_begin_emergency_evacuate(member, structure)


func _vacuum_damage_reduction(member: Dictionary) -> float:
	var reduction := 0.9 if bool(member.get("has_environmental_gear", false)) else 0.0
	for equipment: Resource in member.get("equipment", []):
		if equipment != null:
			reduction += float(equipment.get("vacuum_damage_reduction"))
	return clampf(reduction, 0.0, 1.0)


func _incapacitate_member(member: Dictionary, structure: ShipStructuralState) -> void:
	_cancel_rest(member)
	member["health"] = 0.0
	member["incapacitated"] = true
	member["incapacitated_seconds"] = 0.0
	member["active_job_id"] = 0
	member["at_job"] = false
	member["at_assignment"] = false
	member["assigned_room_id"] = &""
	member["path"] = []
	member.erase("door_crossing_key")
	member.erase("door_crossing_stage")
	member.erase("door_crossing_id")
	member.erase("door_crossing_hazard")
	member["seeking_medical"] = false
	member["state"] = "INCAPACITATED"
	_assign_rescuer_for_patient(member, structure)


func _assign_rescuer_for_patient(patient: Dictionary, structure: ShipStructuralState) -> void:
	var best_rescuer: Dictionary = {}
	var best_path: Array = []
	for candidate: Dictionary in crew_members:
		if candidate == patient or bool(candidate.get("ejected", false)) or bool(candidate.get("incapacitated", false)) or bool(candidate.get("dead", false)):
			continue
		if StringName(candidate.get("assigned_room_id", &"")) != &"" or int(candidate.get("active_job_id", 0)) > 0 or int(candidate.get("rescue_patient_id", 0)) > 0 or bool(candidate.get("seeking_medical", false)):
			continue
		var route := _find_path(structure, candidate["current_cell"], patient["current_cell"])
		if route.is_empty() and candidate["current_cell"] != patient["current_cell"]:
			continue
		if best_rescuer.is_empty() or route.size() < best_path.size():
			best_rescuer = candidate
			best_path = route
	if best_rescuer.is_empty():
		return
	_cancel_rest(best_rescuer)
	var pickup_slot := {
		"room_id": structure.cell_rooms.get(patient["current_cell"], &""),
		"cell": patient["current_cell"],
		"slot_index": -2000 - int(patient["id"]),
		"position": Vector2(patient["position"]) + Vector2(0.18, 0.0),
		"facing": Vector2.UP,
	}
	best_rescuer["rescue_patient_id"] = patient["id"]
	best_rescuer["rescue_phase"] = "TO PATIENT"
	best_rescuer["target_slot"] = pickup_slot
	best_rescuer["path"] = best_path if not best_path.is_empty() else [patient["current_cell"]]
	best_rescuer["path_index"] = 0
	best_rescuer["state"] = "MEDICAL RESCUE"


func _update_rescuer(rescuer: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	var patient := get_member(int(rescuer.get("rescue_patient_id", 0)))
	if patient.is_empty() or bool(patient.get("dead", false)):
		if not patient.is_empty():
			patient["carried_by"] = 0
		_cancel_rescue(rescuer)
		return
	if not (rescuer.get("path", []) as Array).is_empty():
		_update_member(rescuer, structure, delta)
		if int(patient.get("carried_by", 0)) == int(rescuer["id"]):
			patient["position"] = rescuer["position"]
			patient["current_cell"] = rescuer["current_cell"]
		return
	if String(rescuer.get("rescue_phase", "")) == "TO PATIENT":
		var medical_slot := _available_medical_rescue_slot(int(rescuer["id"]))
		if medical_slot.is_empty():
			rescuer["state"] = "AWAITING MEDICAL BERTH"
			return
		var route := _find_path(structure, rescuer["current_cell"], medical_slot["cell"])
		if route.is_empty() and rescuer["current_cell"] != medical_slot["cell"]:
			rescuer["state"] = "NO MEDICAL ROUTE"
			return
		patient["carried_by"] = rescuer["id"]
		patient["state"] = "BEING EVACUATED"
		rescuer["rescue_phase"] = "TO MEDICAL"
		rescuer["target_slot"] = medical_slot
		rescuer["path"] = route if not route.is_empty() else [medical_slot["cell"]]
		rescuer["path_index"] = 0
		rescuer["state"] = "CARRYING CASUALTY"
		return
	patient["carried_by"] = 0
	patient["position"] = rescuer["position"]
	patient["current_cell"] = rescuer["current_cell"]
	patient["state"] = "INCAPACITATED"
	_cancel_rescue(rescuer)


func _available_medical_rescue_slot(rescuer_id: int) -> Dictionary:
	for slot: Dictionary in ambient_slots:
		if String(slot.get("room_type", "")) in ["MEDICAL", "MED_BAY"] and _room_capability_online(slot.get("room_id", &"")) and not _slot_claimed_by_other_crew(slot, rescuer_id):
			return slot
	return {}


func _cancel_rescue(rescuer: Dictionary) -> void:
	rescuer["rescue_patient_id"] = 0
	rescuer["rescue_phase"] = ""
	rescuer["path"] = []
	rescuer["path_index"] = 0
	rescuer["state"] = "OFF DUTY"
	rescuer["idle_time"] = 1.0


func _update_incapacitated_member(member: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	if int(member.get("carried_by", 0)) <= 0 and not _patient_has_rescuer(int(member["id"])):
		_assign_rescuer_for_patient(member, structure)
	var room_id: StringName = structure.cell_rooms.get(member.get("current_cell", Vector2i.ZERO), &"")
	if int(member.get("carried_by", 0)) <= 0 and _room_type_for_id(room_id) in ["MEDICAL", "MED_BAY"] and _room_capability_online(room_id):
		member["health"] = minf(float(member["maximum_health"]), float(member["health"]) + float(crew_rules.get("medical_healing_per_second")) * 0.5 * delta)
		if float(member["health"]) > 0.5:
			member["incapacitated"] = false
			member["state"] = "RECOVERING"
			member["idle_time"] = 5.0
			return
	member["incapacitated_seconds"] = float(member.get("incapacitated_seconds", 0.0)) + delta
	if float(member["incapacitated_seconds"]) >= float(crew_rules.get("incapacitation_survival_seconds")):
		member["dead"] = true
		member["state"] = "DEAD"


func _patient_has_rescuer(patient_id: int) -> bool:
	for member: Dictionary in crew_members:
		if int(member.get("rescue_patient_id", 0)) == patient_id:
			return true
	return false


func _maybe_begin_medical_visit(member: Dictionary, structure: ShipStructuralState) -> void:
	if bool(member.get("seeking_medical", false)) or int(member.get("rescue_patient_id", 0)) > 0 or StringName(member.get("assigned_room_id", &"")) != &"" or int(member.get("active_job_id", 0)) > 0 or bool(member.get("evacuating", false)):
		return
	var health_percent := 100.0 * float(member["health"]) / maxf(float(member["maximum_health"]), 0.001)
	if health_percent >= float(crew_rules.get("medical_seek_health_percentage")):
		return
	for slot: Dictionary in ambient_slots:
		if String(slot.get("room_type", "")) not in ["MEDICAL", "MED_BAY"] or not _room_capability_online(slot.get("room_id", &"")) or _slot_claimed_by_other_crew(slot, int(member["id"])):
			continue
		var path := _find_path(structure, member["current_cell"], slot["cell"])
		if path.is_empty() and member["current_cell"] != slot["cell"]:
			continue
		_cancel_rest(member)
		_clear_idle_routine(member)
		member["target_slot"] = slot
		member["path"] = path if not path.is_empty() else [slot["cell"]]
		member["path_index"] = 0
		member["seeking_medical"] = true
		member["state"] = "SEEKING MEDICAL"
		return


func _update_medical_patient(member: Dictionary, delta: float) -> bool:
	if not bool(member.get("seeking_medical", false)) or not (member.get("path", []) as Array).is_empty():
		return false
	var medical_slot: Dictionary = member["target_slot"]
	var room_id: StringName = medical_slot.get("room_id", &"")
	member["state"] = "RECEIVING TREATMENT"
	var medical_output := get_room_station_output(room_id)
	if _room_capability_online(room_id) and medical_output > 0.0:
		member["health"] = minf(float(member["maximum_health"]), float(member["health"]) + float(crew_rules.get("medical_healing_per_second")) * medical_output * delta)
	else:
		member["state"] = "MEDICAL BAY OFFLINE"
	if float(member["health"]) >= float(member["maximum_health"]) - 0.01:
		member["seeking_medical"] = false
		member["state"] = "OFF DUTY"
		member["idle_time"] = 2.0
	return true


func _room_capability_online(room_id: StringName) -> bool:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return false
	var status: Dictionary = ship.get_room_capability_status(room_id)
	return not status.is_empty() and bool(status.get("online", false))


func _room_type_for_id(room_id: StringName) -> String:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	return String(ship.call("get_room_type_name", room_id)) if is_instance_valid(ship) else ""


func _permits_vacuum_work(member: Dictionary) -> bool:
	if bool(member.get("has_environmental_gear", false)):
		return true
	for equipment: Resource in member.get("equipment", []):
		if equipment != null and bool(equipment.get("permits_vacuum_work")):
			return true
	return false


func _begin_emergency_evacuate(member: Dictionary, structure: ShipStructuralState) -> void:
	var safe_cell := _nearest_safe_cell(structure, member["current_cell"])
	if safe_cell == Vector2i(2147483647, 2147483647):
		member["state"] = "TRAPPED IN VACUUM"
		return
	var path := _find_path(structure, member["current_cell"], safe_cell)
	if path.is_empty() and safe_cell != member["current_cell"]:
		member["state"] = "NO EVACUATION ROUTE"
		return
	_cancel_rest(member)
	_clear_idle_routine(member)
	var previous_job_id := int(member.get("active_job_id", 0))
	if previous_job_id > 0:
		for job: Dictionary in damage_control_jobs:
			if int(job["id"]) == previous_job_id:
				job["safety_hold"] = true
				job["state"] = "UNSAFE ATMOSPHERE"
				break
	member["active_job_id"] = 0
	member["at_job"] = false
	member["at_assignment"] = false
	member["assigned_room_id"] = &""
	member["evacuating"] = true
	member["target_slot"] = {"room_id": structure.cell_rooms.get(safe_cell, &""), "cell": safe_cell, "slot_index": -1, "position": _cell_center(structure.layout, safe_cell)}
	member["path"] = path if not path.is_empty() else [safe_cell]
	member["path_index"] = 0
	member["state"] = "EVACUATING"


func _nearest_safe_cell(structure: ShipStructuralState, origin: Vector2i) -> Vector2i:
	var safe_pressure := float(crew_rules.get("evacuation_safe_oxygen"))
	var best_cell := Vector2i(2147483647, 2147483647)
	var best_distance := INF
	for cell_value: Variant in structure.cell_rooms.keys():
		var cell: Vector2i = cell_value
		var room_id: StringName = structure.cell_rooms[cell]
		if structure.get_room_pressure(room_id) < safe_pressure:
			continue
		var path := _find_path(structure, origin, cell)
		if path.is_empty() and cell != origin:
			continue
		if path.size() < best_distance:
			best_distance = path.size()
			best_cell = cell
	return best_cell


func _update_job_member(member: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	if String(member.get("job_phase", "")) == "EQUIPPING":
		if not (member.get("path", []) as Array).is_empty():
			_update_member(member, structure, delta)
			return
		var ship := get_tree().get_first_node_in_group("ship_simulation")
		var provider_id: StringName = member.get("equipped_from_room_id", &"")
		var provider_status: Dictionary = ship.get_room_capability_status(provider_id) if is_instance_valid(ship) else {}
		if provider_status.is_empty() or not bool(provider_status.get("online", false)):
			_cancel_member_damage_control(member, "ENGINEERING BAY OFFLINE")
			return
		member["state"] = "OUTFITTING"
		member["equip_remaining"] = maxf(float(member.get("equip_remaining", 0.0)) - delta, 0.0)
		if float(member["equip_remaining"]) > 0.0:
			return
		var job := _damage_control_job(int(member.get("active_job_id", 0)))
		if job.is_empty():
			_cancel_member_damage_control(member, "ORDER CANCELLED")
			return
		member["has_repair_gear"] = true
		member["has_environmental_gear"] = bool(job.get("requires_environment", false))
		member["job_phase"] = "RESPONDING"
		member["at_job"] = false
		member["target_slot"] = job["target"]
		var response_path := _find_path(structure, member["current_cell"], job["target"]["cell"], bool(member.get("has_environmental_gear", false)))
		member["path"] = response_path if not response_path.is_empty() else [job["target"]["cell"]]
		member["path_index"] = 0
		member["state"] = "DAMAGE CONTROL"
		return
	var path: Array = member["path"]
	if path.is_empty():
		member["at_job"] = true
		member["state"] = "REPAIRING"
		return
	_update_member(member, structure, delta)
	if (member["path"] as Array).is_empty():
		member["at_job"] = true
		member["state"] = "REPAIRING"


func _damage_control_job(job_id: int) -> Dictionary:
	for job: Dictionary in damage_control_jobs:
		if int(job["id"]) == job_id:
			return job
	return {}


func _cancel_member_damage_control(member: Dictionary, reason: String) -> void:
	member["active_job_id"] = 0
	member["job_phase"] = ""
	member["equipped_from_room_id"] = &""
	member["has_repair_gear"] = false
	member["has_environmental_gear"] = false
	member["equip_remaining"] = 0.0
	member["at_job"] = false
	member["path"] = []
	member["path_index"] = 0
	member["state"] = reason
	member["idle_time"] = 1.0


func _update_decompression(member: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	var room_id: StringName = structure.cell_rooms.get(member["current_cell"], &"")
	if room_id == &"":
		return
	var force := structure.get_decompression_force(member["position"], room_id)
	var velocity: Vector2 = member["decompression_velocity"]
	var damping := float(structure.material.get("decompression_velocity_damping"))
	velocity = velocity.move_toward(Vector2.ZERO, damping * delta)
	velocity += force * delta
	member["decompression_velocity"] = velocity
	if velocity.length_squared() <= 0.0001:
		return
	member["position"] = Vector2(member["position"]) + velocity * delta
	if not structure.contains_logical_position(member["position"]):
		member["ejected"] = true
		member["at_assignment"] = false
		member["assigned_room_id"] = &""
		member["path"] = []
		member["active_job_id"] = 0
		member["at_job"] = false
		member["state"] = "EJECTED INTO SPACE"


func _build_work_slots(layout: Resource) -> void:
	work_slots.clear()
	ambient_slots.clear()
	crew_spawn_slots.clear()
	rest_slots.clear()
	furniture_obstacles.clear()
	furniture_obstacle_polygons.clear()
	captain_slot.clear()
	var slot_offsets := [Vector2(-0.22, -0.18), Vector2(0.22, 0.18), Vector2(0.22, -0.18), Vector2(-0.22, 0.18)]
	# Navigation runs center-to-center through cells and door midpoints. Keep
	# off-duty parking in inset corners so stationary crew stay out of those lanes.
	var ambient_offsets := [
		Vector2(-0.35, -0.35),
		Vector2(0.35, -0.35),
		Vector2(0.35, 0.35),
		Vector2(-0.35, 0.35),
	]
	var slot_count := mini(int(crew_definition.get("work_slots_per_cell")), slot_offsets.size())
	for room: Resource in layout.get("rooms"):
		# Exterior quarter modules are hardware attached outside the pressure hull.
		# They provide neither duty stations nor off-duty walking/parking targets.
		if ROOM_STAFFING_RULES.is_unmanned_exterior_module(room):
			continue
		var room_type := String(room.get("type_name"))
		var ambient_priority := 0 if room_type in ["CREW", "CREW_QUARTERS"] else (1 if room_type == "UNASSIGNED" else 2)
		var room_rects: Array[Rect2i] = room.get("grid_rects")
		for piece_index: int in range(room_rects.size()):
			var rect: Rect2i = room_rects[piece_index]
			var walkable_bounds := _piece_walkable_bounds(layout, rect)
			var narrow_weapon_piece := room_type == "WEAPONS" and rect.size == Vector2i(2, 2) and _uses_narrow_weapon_room(room)
			if room_type == "COMMAND" and rect.size == Vector2i(2, 2):
				_build_authored_room_layout(BRIDGE_CREW_LAYOUT, layout, room, rect, piece_index)
				continue
			elif room_type == "POWER" and rect.size == Vector2i(2, 2):
				_build_authored_room_layout(REACTOR_CREW_LAYOUT, layout, room, rect, piece_index)
				continue
			elif room_type == "SHIELDS" and rect.size == Vector2i(2, 2):
				_build_authored_room_layout(SHIELD_CREW_LAYOUT, layout, room, rect, piece_index)
				continue
			elif room_type in ["CREW", "CREW_QUARTERS"] and rect.size == Vector2i(2, 2):
				_build_crew_quarters_furnishings(layout, room, rect, piece_index)
			elif room_type == "PROPULSION" and rect.size == Vector2i(2, 2):
				_build_authored_room_layout(THRUSTER_CREW_LAYOUT, layout, room, rect, piece_index)
				continue
			elif narrow_weapon_piece:
				_build_narrow_weapon_furnishings(layout, room, rect, piece_index)
				_build_narrow_weapon_work_slots(layout, room, rect, piece_index)
				# A casemate is machinery, not a lounge or travel lane. Its authored
				# rear stations are the only legal destinations inside the piece.
				# Generic per-cell slots can land on the far side of the gun/aperture,
				# producing an unreachable target and a permanently walking crewman.
				continue
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var cell := Vector2i(x, y)
					var center := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).get_center()
					for ambient_index: int in range(ambient_offsets.size()):
						var ambient_offset: Vector2 = ambient_offsets[ambient_index]
						var ambient_position := _clamp_to_walkable_bounds(center + ambient_offset, walkable_bounds)
						if _position_blocked_by_furniture(ambient_position):
							continue
						ambient_slots.append({
							"room_id": room.get("room_id"),
							"room_type": room_type,
							"cell": cell,
							"slot_index": -1000 - ambient_index,
							"piece_index": piece_index,
							"position": ambient_position,
							"facing": -ambient_offset.normalized() if not ambient_offset.is_zero_approx() else Vector2.UP,
							"ambient_priority": ambient_priority,
							"is_idle_slot": true,
						})
					for slot_index: int in range(slot_count):
						var offset: Vector2 = slot_offsets[slot_index]
						var work_position := _clamp_to_walkable_bounds(center + offset, walkable_bounds)
						if _position_blocked_by_furniture(work_position):
							continue
						work_slots.append({
							"room_id": room.get("room_id"),
							"cell": cell,
							"slot_index": slot_index,
							"piece_index": piece_index,
							"position": work_position,
							"facing": -offset.normalized(),
						})
	_sync_captain_to_bridge()


## Converts a reusable 160x160 room-authoring scene into live ship coordinates.
## Marker positions, marker rotation, final approach points, idle positions, and
## solid furniture can therefore be tuned visually without changing this script.
func _build_authored_room_layout(
	room_scene: PackedScene,
	layout: Resource,
	room: Resource,
	rect: Rect2i,
	piece_index: int
) -> void:
	var authored := room_scene.instantiate() as RoomCrewLayout
	if authored == null:
		return
	var bounds := _module_bounds(layout, rect)
	if bounds.size.is_zero_approx():
		authored.free()
		return
	var facing_quarters := _piece_facing_quarters(room, piece_index)
	var total_quarters := posmod(facing_quarters + authored.source_rotation_quarters, 4)
	var rotation := float(total_quarters) * PI * 0.5
	for obstacle: RoomLayoutObstacle in authored.obstacles():
		var live_polygon := PackedVector2Array()
		for point: Vector2 in obstacle.polygon:
			var layout_point := obstacle.transform * point
			live_polygon.append(_authored_position(bounds, authored.normalized_position(layout_point), rotation))
		if live_polygon.size() >= 3:
			furniture_obstacle_polygons.append(live_polygon)
	var station_index := 0
	for marker: Marker2D in authored.markers_under(&"ManningLocations"):
		var normalized_position := authored.normalized_position(marker.position)
		var source_facing := Vector2.UP.rotated(marker.rotation)
		var position := _authored_position(bounds, normalized_position, rotation)
		var route: Array[Vector2] = []
		for child: Node in marker.get_children():
			if child is Marker2D:
				var route_local := marker.position + (child as Marker2D).position.rotated(marker.rotation)
				route.append(_authored_position(bounds, authored.normalized_position(route_local), rotation))
		work_slots.append({
			"room_id": room.get("room_id"),
			"cell": _cell_in_rect_nearest_to_position(layout, rect, position),
			"slot_index": station_index,
			"piece_index": piece_index,
			"position": position,
			"facing": source_facing.rotated(rotation),
			"authored_station": StringName(marker.name),
			"approach_positions": route,
		})
		station_index += 1
	var idle_index := 0
	for marker: Marker2D in authored.markers_under(&"IdleLocations"):
		var position := _authored_position(bounds, authored.normalized_position(marker.position), rotation)
		if not _position_blocked_by_furniture(position):
			ambient_slots.append({
				"room_id": room.get("room_id"),
				"room_type": String(room.get("type_name")),
				"cell": _cell_in_rect_nearest_to_position(layout, rect, position),
				"slot_index": -3000 - idle_index,
				"piece_index": piece_index,
				"position": position,
				"facing": Vector2.UP.rotated(marker.rotation + rotation),
				"ambient_priority": 2,
				"is_idle_slot": true,
			})
		idle_index += 1
	var special := authored.get_node_or_null(^"SpecialLocations/Captain") as Marker2D
	if special != null:
		var position := _authored_position(bounds, authored.normalized_position(special.position), rotation)
		captain_slot = {
			"room_id": room.get("room_id"),
			"cell": _cell_in_rect_nearest_to_position(layout, rect, position),
			"piece_index": piece_index,
			"position": position,
			"facing": Vector2.UP.rotated(special.rotation + rotation),
		}
	authored.free()


## Returns the exact logical bounds used by the 160x160 authored room art.
func _module_bounds(layout: Resource, rect: Rect2i) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			bounds = cell_rect if not initialized else bounds.merge(cell_rect)
			initialized = true
	return bounds


func _piece_facing_quarters(room: Resource, piece_index: int) -> int:
	var facing := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing = int(mount_facings[piece_index])
	return posmod(maxi(facing, 0), 4)


func _authored_position(bounds: Rect2, normalized_position: Vector2, rotation: float) -> Vector2:
	var local_position := Vector2(
		(normalized_position.x - 0.5) * bounds.size.x,
		(normalized_position.y - 0.5) * bounds.size.y
	)
	return bounds.get_center() + local_position.rotated(rotation)


func _append_authored_work_slot(
	layout: Resource,
	room: Resource,
	rect: Rect2i,
	piece_index: int,
	station_index: int,
	bounds: Rect2,
	normalized_position: Vector2,
	source_facing: Vector2,
	rotation: float,
	tag: StringName
) -> void:
	var position := _authored_position(bounds, normalized_position, rotation)
	work_slots.append({
		"room_id": room.get("room_id"),
		"cell": _cell_in_rect_nearest_to_position(layout, rect, position),
		"slot_index": station_index,
		"piece_index": piece_index,
		"position": position,
		"facing": source_facing.rotated(rotation),
		"authored_station": tag,
	})


## Bridge art faces north. Four ordinary stations operate the forward and
## central consoles; the lower central chair belongs exclusively to the captain.
func _build_bridge_furnishings_and_slots(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var bounds := _module_bounds(layout, rect)
	if bounds.size.is_zero_approx():
		return
	var rotation := float(_piece_facing_quarters(room, piece_index)) * PI * 0.5
	for footprint: Rect2 in [
		Rect2(0.30, 0.20, 0.40, 0.15),
		Rect2(0.35, 0.42, 0.30, 0.22),
	]:
		furniture_obstacles.append(_rotated_normalized_obstacle(bounds, footprint, rotation))
	var stations: Array = [
		[Vector2(0.38, 0.39), Vector2.UP],
		[Vector2(0.62, 0.39), Vector2.UP],
		[Vector2(0.37, 0.57), Vector2.RIGHT],
		[Vector2(0.63, 0.57), Vector2.LEFT],
	]
	for station_index: int in range(stations.size()):
		var station: Array = stations[station_index]
		_append_authored_work_slot(
			layout, room, rect, piece_index, station_index, bounds,
			station[0], station[1], rotation, &"bridge"
		)
	var captain_position := _authored_position(bounds, Vector2(0.50, 0.69), rotation)
	captain_slot = {
		"room_id": room.get("room_id"),
		"cell": _cell_in_rect_nearest_to_position(layout, rect, captain_position),
		"piece_index": piece_index,
		"position": captain_position,
		"facing": Vector2.UP.rotated(rotation),
	}


## Reactor personnel ring the central machinery and face inward. The machinery
## itself is a solid obstacle for both parking and live path detours.
func _build_reactor_furnishings_and_slots(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var bounds := _module_bounds(layout, rect)
	if bounds.size.is_zero_approx():
		return
	var rotation := float(_piece_facing_quarters(room, piece_index)) * PI * 0.5
	furniture_obstacles.append(_rotated_normalized_obstacle(bounds, Rect2(0.30, 0.30, 0.40, 0.40), rotation))
	var stations: Array = [
		[Vector2(0.50, 0.20), Vector2.DOWN],
		[Vector2(0.80, 0.50), Vector2.LEFT],
		[Vector2(0.50, 0.80), Vector2.UP],
		[Vector2(0.20, 0.50), Vector2.RIGHT],
	]
	for station_index: int in range(stations.size()):
		var station: Array = stations[station_index]
		_append_authored_work_slot(
			layout, room, rect, piece_index, station_index, bounds,
			station[0], station[1], rotation, &"reactor"
		)


func _sync_captain_to_bridge() -> void:
	if captain_slot.is_empty():
		captain_member.clear()
		return
	if captain_member.is_empty():
		captain_member = {
			"id": 0,
			"name": "CAPTAIN",
			"color_shift": 0.0,
			"health": 100.0,
			"dead": false,
			"incapacitated": false,
			"ejected": false,
			"carried_by": 0,
			"active_job_id": 0,
			"resting": false,
			"is_captain": true,
		}
	captain_member["position"] = captain_slot["position"]
	captain_member["current_cell"] = captain_slot["cell"]
	captain_member["facing_direction"] = captain_slot["facing"]
	captain_member["assigned_room_id"] = captain_slot["room_id"]
	captain_member["at_assignment"] = true
	captain_member["state"] = "COMMANDING"


## Standard Crew Quarters art contains four beds/footlockers, one centered in
## each quarter of its 2x2 module. Crew approach from the clear central aisle,
## then visually settle onto a reserved bed; normal movement treats the authored
## furniture footprint as solid.
func _build_crew_quarters_furnishings(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var module_bounds := Rect2()
	var initialized := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			module_bounds = cell_rect if not initialized else module_bounds.merge(cell_rect)
			initialized = true
	if not initialized:
		return
	# Crew enter through a small formation in the clear center of the quarters,
	# never directly on a bed, wall, doorway, idle target, or duty station. The
	# roster is subsequently routed from these neutral entry points by the normal
	# staffing pass. Keeping these separate from ambient slots prevents a new
	# member from beginning life already wedged against their eventual target.
	var spawn_center := module_bounds.get_center()
	var spawn_radius := minf(module_bounds.size.x, module_bounds.size.y) * 0.07
	var spawn_offsets: Array[Vector2] = [
		Vector2(-spawn_radius, -spawn_radius),
		Vector2(spawn_radius, -spawn_radius),
		Vector2(-spawn_radius, spawn_radius),
		Vector2(spawn_radius, spawn_radius),
	]
	for spawn_index: int in range(spawn_offsets.size()):
		var spawn_position := spawn_center + spawn_offsets[spawn_index]
		crew_spawn_slots.append({
			"room_id": room.get("room_id"),
			"room_type": String(room.get("type_name")),
			"cell": _cell_in_rect_nearest_to_position(layout, rect, spawn_position),
			"slot_index": -4000 - spawn_index,
			"piece_index": piece_index,
			"module_rect": rect,
			"position": spawn_position,
			"facing": Vector2.DOWN,
		})
	for local_y: int in range(2):
		for local_x: int in range(2):
			var cell := rect.position + Vector2i(local_x, local_y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			# The authored beds are inset toward the horizontal centerline of the
			# 2x2 room rather than centered vertically in each logical cell. Match
			# those actual mattress centers so all four resting poses align alike.
			var mattress_inset := cell_rect.size.y * 0.10
			var bed_position := cell_rect.get_center() + Vector2(
				0.0,
				mattress_inset if local_y == 0 else -mattress_inset
			)
			var aisle_sign := 1.0 if local_x == 0 else -1.0
			var approach_position := bed_position + Vector2(aisle_sign * cell_rect.size.x * 0.38, 0.0)
			approach_position.x = clampf(approach_position.x, module_bounds.position.x + 0.12, module_bounds.end.x - 0.12)
			rest_slots.append({
				"room_id": room.get("room_id"),
				"room_type": String(room.get("type_name")),
				"cell": cell,
				"slot_index": -2000 - local_y * 2 - local_x,
				"piece_index": piece_index,
				"position": approach_position,
				"bed_position": bed_position,
				"facing": Vector2.UP,
				"is_bed": true,
			})
			var obstacle_size := Vector2(cell_rect.size.x * 0.38, cell_rect.size.y * 0.46)
			furniture_obstacles.append(Rect2(bed_position - obstacle_size * 0.5, obstacle_size))


## The standard thruster overlay is a stepped engine housing rather than an
## empty room. Approximate that authored silhouette with three joined solid
## rectangles and rotate them by the exact same convention as the visual art.
## This preserves usable deck around the machinery while keeping crew bodies
## out of the engine and its central feed trunk.
func _build_thruster_furnishings(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var module_bounds := Rect2()
	var initialized := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			module_bounds = cell_rect if not initialized else module_bounds.merge(cell_rect)
			initialized = true
	if not initialized:
		return
	var facing_quarters := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing_quarters = int(mount_facings[piece_index])
	var rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	# Normalized source-art footprints: narrow feed, middle casing, wide base.
	var source_footprints: Array[Rect2] = [
		Rect2(0.44, 0.20, 0.12, 0.35),
		Rect2(0.31, 0.50, 0.38, 0.22),
		Rect2(0.20, 0.68, 0.60, 0.25),
	]
	for normalized_rect: Rect2 in source_footprints:
		furniture_obstacles.append(_rotated_normalized_obstacle(module_bounds, normalized_rect, rotation))


func _uses_narrow_weapon_room(room: Resource) -> bool:
	var weapon: Resource = room.get("weapon_definition")
	if weapon == null or bool(weapon.get("uses_exposed_hull_edges")):
		return false
	return float(weapon.get("traverse_degrees")) < 90.0


## The authored casemate contains two separate forbidden regions: the physical
## gun/socket and the exposed-to-space aperture ahead of it. Treating both as
## furniture keeps ambient parking, work slots, and live paths off the gun and
## prevents crew from walking across empty space that only looks transparent.
func _build_narrow_weapon_furnishings(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var module_bounds := Rect2()
	var initialized := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			module_bounds = cell_rect if not initialized else module_bounds.merge(cell_rect)
			initialized = true
	if not initialized:
		return
	var facing_quarters := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing_quarters = int(mount_facings[piece_index])
	var rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	# Source art faces south. The first footprint is the gun/socket; the second
	# conservatively covers the complete tapered space cutout to the hull edge.
	for normalized_rect: Rect2 in [
		Rect2(0.38, 0.37, 0.24, 0.27),
		Rect2(0.24, 0.61, 0.52, 0.39),
	]:
		furniture_obstacles.append(_rotated_normalized_obstacle(module_bounds, normalized_rect, rotation))


## Narrow casemates have a deliberately divided floor plan. Keep their crew at
## authored stations behind the mount instead of scattering generic cell slots
## around the open firing aperture. Source art faces south, matching the
## furnishing rotation above.
func _build_narrow_weapon_work_slots(layout: Resource, room: Resource, rect: Rect2i, piece_index: int) -> void:
	var module_bounds := Rect2()
	var initialized := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			module_bounds = cell_rect if not initialized else module_bounds.merge(cell_rect)
			initialized = true
	if not initialized:
		return
	var facing_quarters := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing_quarters = int(mount_facings[piece_index])
	var rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	var normalized_stations: Array[Vector2] = [
		Vector2(0.34, 0.20),
		Vector2(0.66, 0.20),
		Vector2(0.34, 0.31),
		Vector2(0.66, 0.31),
	]
	for station_index: int in range(normalized_stations.size()):
		var normalized_position := normalized_stations[station_index]
		var local_position := Vector2(
			(normalized_position.x - 0.5) * module_bounds.size.x,
			(normalized_position.y - 0.5) * module_bounds.size.y
		)
		var station_position := module_bounds.get_center() + local_position.rotated(rotation)
		if _position_blocked_by_furniture(station_position):
			continue
		var station_cell := _cell_in_rect_nearest_to_position(layout, rect, station_position)
		work_slots.append({
			"room_id": room.get("room_id"),
			"cell": station_cell,
			"slot_index": station_index,
			"piece_index": piece_index,
			"position": station_position,
			"facing": Vector2.DOWN.rotated(rotation),
			"authored_weapon_station": true,
		})


func _cell_in_rect_nearest_to_position(layout: Resource, rect: Rect2i, position: Vector2) -> Vector2i:
	var nearest_cell := rect.position
	var nearest_distance := INF
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			if cell_rect.has_point(position):
				return cell
			var distance := cell_rect.get_center().distance_squared_to(position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cell = cell
	return nearest_cell


func _rotated_normalized_obstacle(bounds: Rect2, normalized_rect: Rect2, rotation: float) -> Rect2:
	var local_center := Vector2(
		(normalized_rect.get_center().x - 0.5) * bounds.size.x,
		(normalized_rect.get_center().y - 0.5) * bounds.size.y
	)
	var obstacle_size := normalized_rect.size * bounds.size
	var rotated_center := bounds.get_center() + local_center.rotated(rotation)
	# All supported module facings are quarter turns, so swapping the dimensions
	# produces the exact axis-aligned collision footprint after rotation.
	if posmod(roundi(rotation / (PI * 0.5)), 2) != 0:
		obstacle_size = Vector2(obstacle_size.y, obstacle_size.x)
	return Rect2(rotated_center - obstacle_size * 0.5, obstacle_size)


## Returns the physical piece bounds inset far enough that a crew sprite's
## center cannot be parked inside its authored perimeter walls.
func _piece_walkable_bounds(layout: Resource, rect: Rect2i) -> Rect2:
	var piece_bounds := Rect2()
	var has_cell := false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
			piece_bounds = cell_rect if not has_cell else piece_bounds.merge(cell_rect)
			has_cell = true
	if not has_cell:
		return piece_bounds
	var requested_clearance := float(crew_definition.get("collision_radius_cells")) if crew_definition != null else 0.44
	var maximum_clearance := maxf(minf(piece_bounds.size.x, piece_bounds.size.y) * 0.5 - 0.02, 0.0)
	var clearance := minf(requested_clearance, maximum_clearance)
	return piece_bounds.grow(-clearance)


func _clamp_to_walkable_bounds(position: Vector2, walkable_bounds: Rect2) -> Vector2:
	if walkable_bounds.size.x <= 0.0 or walkable_bounds.size.y <= 0.0:
		return walkable_bounds.get_center()
	return Vector2(
		clampf(position.x, walkable_bounds.position.x, walkable_bounds.end.x),
		clampf(position.y, walkable_bounds.position.y, walkable_bounds.end.y)
	)


func _update_member(member: Dictionary, structure: ShipStructuralState, delta: float) -> void:
	var path: Array = member["path"]
	if path.is_empty():
		if bool(member.get("resting", false)):
			member["rest_remaining"] = maxf(float(member.get("rest_remaining", 0.0)) - delta, 0.0)
			member["state"] = "RESTING"
			if float(member["rest_remaining"]) <= 0.0:
				_finish_rest(member)
			return
		if StringName(member["assigned_room_id"]) != &"":
			member["state"] = "MANNING" if bool(member["at_assignment"]) else "AWAITING ROUTE"
			return
		member["idle_time"] = maxf(float(member["idle_time"]) - delta, 0.0)
		member["state"] = _reserve_idle_state(member)
		if float(member["idle_time"]) <= 0.0:
			_choose_new_assignment(member, structure)
		return
	var path_index := int(member["path_index"])
	if path_index >= path.size():
		_arrive_at_assignment(member)
		return
	var next_cell: Vector2i = path[path_index]
	var current_cell: Vector2i = member["current_cell"]
	var door_id := structure.get_door_between_cells(current_cell, next_cell)
	var door_stage := 0
	var has_door_priority := true
	if not door_id.is_empty():
		var door: Dictionary = structure.doors.get(door_id, {})
		var was_requested_open := bool(door.get("requested_open", false))
		var hazard_override := bool(member.get("has_environmental_gear", false))
		var door_requested := structure.request_hazard_door_override(door_id, true) if hazard_override else structure.request_door_open(door_id, true)
		if door_requested and not was_requested_open:
			_play_door_sound(structure, door_id, true)
		var crossing_key := "%s:%d" % [door_id, path_index]
		if String(member.get("door_crossing_key", "")) != crossing_key:
			member["door_crossing_key"] = crossing_key
			member["door_crossing_stage"] = 0
		member["door_crossing_id"] = door_id
		member["door_crossing_hazard"] = hazard_override
		crew_held_doors[door_id] = bool(crew_held_doors.get(door_id, false)) or hazard_override
		door_stage = int(member.get("door_crossing_stage", 0))
		has_door_priority = _claim_doorway(member, door_id)
		# Crew may walk up to a closed or locked door, but cannot enter its
		# threshold until the panels and safety interlock permit traversal.
		if door_stage >= 1 and (not door_requested or not structure.can_traverse_door(door_id)):
			member["state"] = "WAITING FOR DOOR"
			return
	# A furniture detour belongs to one navigation leg only. In particular, a
	# corner chosen while leaving the engine housing must never survive into the
	# three-stage doorway crossing: it can pull sideways against the jamb and
	# leave the crew body permanently pinned inside the wall.
	var navigation_leg_key := "%d:%d:%d:%d:%d:%s:%d" % [
		path_index,
		current_cell.x,
		current_cell.y,
		next_cell.x,
		next_cell.y,
		door_id,
		door_stage,
	]
	_prepare_furniture_navigation_leg(member, navigation_leg_key)
	var target_position := _safe_cell_navigation_point(structure.layout, next_cell)
	var wall_clearance := float(crew_definition.get("collision_radius_cells")) if crew_definition != null else 0.44
	# The visual crew sprite is wider than the temporary logical doorway. Use a
	# compact body radius for wall collision while retaining the larger parking
	# inset above. Authored door art can widen this later without path changes.
	var body_clearance := minf(wall_clearance, CREW_BODY_CLEARANCE)
	if not door_id.is_empty():
		match door_stage:
			0:
				var queue_clearance := wall_clearance
				if not has_door_priority:
					# Waiting crew form a short queue behind the approach point instead
					# of occupying the exact same wall-adjacent coordinate.
					queue_clearance += 0.22 * float(_doorway_queue_index(member, door_id) + 1)
				target_position = structure.get_door_approach_point(door_id, current_cell, queue_clearance)
			1:
				target_position = structure.get_door_center(door_id)
			2:
				# Put the crew center decisively beyond the far jamb. Once this point
				# is reached the doorway traversal is complete; ordinary navigation in
				# the destination room begins on the following update. Keeping an
				# additional doorway stage here left current_cell referring to the old
				# room and could pin a body in the thruster-room threshold.
				var departure_clearance := maxf(body_clearance * 2.0, 0.30)
				target_position = structure.get_door_approach_point(door_id, next_cell, departure_clearance)
	elif path_index == path.size() - 1:
		# Authored room overlays can introduce furniture after a work/idle slot was
		# chosen. Never keep steering a body toward a slot now occupied by a bed,
		# locker, engine, or weapon mount.
		var target_slot: Dictionary = member.get("target_slot", {})
		var assigned_position: Vector2 = target_slot.get("position", _safe_cell_navigation_point(structure.layout, next_cell))
		assigned_position = _authored_station_route_target(member, target_slot, assigned_position)
		target_position = (
			_safe_cell_navigation_point(structure.layout, next_cell)
			if _position_blocked_by_furniture(assigned_position)
			else assigned_position
		)
	member["state"] = "MOVING"
	var previous_position: Vector2 = member["position"]
	var lattice_speed_scale := 2.0 if structure.layout != null and int(structure.layout.get("lattice_version")) >= 2 else 1.0
	var desired_position := previous_position.move_toward(target_position, float(crew_definition.get("movement_speed_cells")) * lattice_speed_scale * delta)
	# Door approach/threshold/departure points form a safe, wall-normal route.
	# Avoidance begins only after the body has cleared the far jamb; it can then
	# choose a side of any machinery mounted directly behind the doorway.
	if door_id.is_empty():
		desired_position = _steer_around_furniture(member, previous_position, desired_position, target_position, structure, body_clearance)
	else:
		member.erase("furniture_waypoint")
	var passable_door := door_id if not door_id.is_empty() and door_stage >= 1 else ""
	member["position"] = structure.constrain_crew_motion(
		previous_position,
		desired_position,
		current_cell,
		next_cell,
		body_clearance,
		passable_door
	)
	var movement: Vector2 = Vector2(member["position"]) - previous_position
	if not door_id.is_empty() and door_stage == 0 and not has_door_priority:
		member["state"] = "WAITING FOR PASSAGE"
		if Vector2(member["position"]).distance_to(target_position) <= 0.04:
			_reset_navigation_progress(member, target_position)
		return
	# Measuring only zero velocity misses the most common visible jam: a body can
	# shuffle or oscillate along a jamb forever without getting any closer to its
	# destination. Track actual distance gained toward the active door/furniture
	# waypoint instead. This also covers obstructions introduced by future room
	# overlays without requiring a bespoke unstuck rule for each furnishing.
	var progress_target: Vector2 = member.get("furniture_waypoint", target_position)
	if _navigation_progress_stalled(member, Vector2(member["position"]), progress_target, delta):
		member["navigation_recovery_count"] = int(member.get("navigation_recovery_count", 0)) + 1
		# Discard and recompute a stale detour. Never teleport to the target: that
		# bypasses both walls and furniture and can merely hide a bad route by
		# placing the crew on the wrong side of the obstruction.
		member.erase("furniture_waypoint")
		member["state"] = "REPLANNING"
		_reset_navigation_progress(member, target_position)
		# Waiting for a closed/interlocked door returns above and never reaches this
		# watchdog. Reaching it during a crossing therefore means the body is truly
		# pinned at the jamb. Finish the already-authorized threshold traversal onto
		# a generated room-side landing so a doorway can never become a parking spot.
		if not door_id.is_empty():
			_recover_stalled_door_crossing(
				member,
				structure,
				door_id,
				current_cell,
				next_cell,
				path_index,
				door_stage,
				body_clearance
			)
			return
		# Repeating the same final approach can never fix a station which became
		# unreachable after two modules merged or authored furniture changed. On
		# the second failed approach, move only across a verified-clear segment to
		# another unclaimed station in this same room. If there is no such station,
		# release the order so automatic staffing may choose a genuinely reachable
		# crew member/slot on its next pass instead of animating an endless walk.
		if (
			int(member["navigation_recovery_count"]) >= 2
			and door_id.is_empty()
			and path_index == path.size() - 1
			and StringName(member.get("assigned_room_id", &"")) != &""
		):
			if _recover_stalled_work_station(member, structure, body_clearance):
				return
			_relinquish_unreachable_station(member)
			return
	if not movement.is_zero_approx():
		member["facing_direction"] = movement.normalized()
	# A sub-pixel exact-point requirement is fragile at a wall boundary. This is
	# still well below the crew collision radius, but reliably completes a leg
	# after collision projection or floating-point rounding.
	if Vector2(member["position"]).distance_to(target_position) <= 0.04:
		if not door_id.is_empty() and door_stage < 2:
			member["door_crossing_stage"] = door_stage + 1
			return
		# Authored work stations may provide one or more safe final approach
		# markers. Visit those points before parking at the actual station, so a
		# crew member cannot cut diagonally across a console or machinery corner.
		if door_id.is_empty() and path_index == path.size() - 1 and _advance_authored_station_route(member):
			_reset_navigation_progress(member, Vector2(member["position"]))
			return
		member["current_cell"] = next_cell
		member["path_index"] = path_index + 1
		member.erase("door_crossing_key")
		member.erase("door_crossing_stage")
		member.erase("door_crossing_id")
		member.erase("door_crossing_hazard")
		member.erase("furniture_waypoint")
		member.erase("furniture_navigation_leg")
		member.erase("blocked_navigation_time")
		member.erase("navigation_progress_target")
		member.erase("navigation_progress_best_distance")
		member.erase("navigation_stall_time")
		member.erase("navigation_recovery_count")
		if not door_id.is_empty() and int(doorway_reservations.get(door_id, 0)) == int(member.get("id", 0)):
			doorway_reservations.erase(door_id)
		if int(member["path_index"]) >= path.size():
			_arrive_at_assignment(member)


func _recover_stalled_door_crossing(
	member: Dictionary,
	structure: ShipStructuralState,
	door_id: String,
	current_cell: Vector2i,
	next_cell: Vector2i,
	path_index: int,
	door_stage: int,
	body_clearance: float
) -> void:
	if door_stage <= 0:
		member["position"] = structure.get_door_approach_point(
			door_id,
			current_cell,
			maxf(body_clearance * 2.0, 0.16)
		)
		member["door_crossing_stage"] = 1
		member["state"] = "DOORWAY RECOVERED"
		_reset_navigation_progress(member, Vector2(member["position"]))
		return
	member["position"] = structure.get_door_approach_point(
		door_id,
		next_cell,
		maxf(body_clearance * 2.0, 0.30)
	)
	member["current_cell"] = next_cell
	member["path_index"] = path_index + 1
	member["state"] = "DOORWAY RECOVERED"
	_clear_member_door_crossing_state(member, door_id)
	member.erase("furniture_waypoint")
	member.erase("furniture_navigation_leg")
	member.erase("blocked_navigation_time")
	member.erase("navigation_progress_target")
	member.erase("navigation_progress_best_distance")
	member.erase("navigation_stall_time")
	member.erase("navigation_recovery_count")
	if int(member["path_index"]) >= (member.get("path", []) as Array).size():
		_arrive_at_assignment(member)


func _clear_member_door_crossing_state(member: Dictionary, door_id: String = "") -> void:
	var released_door_id := door_id
	if released_door_id.is_empty():
		released_door_id = String(member.get("door_crossing_id", ""))
	if (
		not released_door_id.is_empty()
		and int(doorway_reservations.get(released_door_id, 0)) == int(member.get("id", 0))
	):
		doorway_reservations.erase(released_door_id)
	member.erase("door_crossing_key")
	member.erase("door_crossing_stage")
	member.erase("door_crossing_id")
	member.erase("door_crossing_hazard")


func _authored_station_route_target(member: Dictionary, slot: Dictionary, fallback: Vector2) -> Vector2:
	var route: Array = slot.get("approach_positions", [])
	if route.is_empty():
		member.erase("station_route_key")
		member.erase("station_route_index")
		return fallback
	var route_key := "%s:%d:%d" % [
		String(slot.get("room_id", &"")),
		int(slot.get("piece_index", -1)),
		int(slot.get("slot_index", -1)),
	]
	if String(member.get("station_route_key", "")) != route_key:
		member["station_route_key"] = route_key
		member["station_route_index"] = 0
	var route_index := int(member.get("station_route_index", 0))
	if route_index >= 0 and route_index < route.size():
		return Vector2(route[route_index])
	return fallback


func _advance_authored_station_route(member: Dictionary) -> bool:
	var slot: Dictionary = member.get("target_slot", {})
	var route: Array = slot.get("approach_positions", [])
	var route_index := int(member.get("station_route_index", route.size()))
	if route_index < 0 or route_index >= route.size():
		return false
	member["station_route_index"] = route_index + 1
	return true


## Recover only within the assigned room and only across geometry that the
## normal wall/furniture collision system certifies as clear. This is a rare
## deadlock escape, not a general teleport: it cannot cross a wall, doorway,
## weapon body, or space cutout.
func _recover_stalled_work_station(member: Dictionary, structure: ShipStructuralState, body_clearance: float) -> bool:
	var room_id := StringName(member.get("assigned_room_id", &""))
	var crew_id := int(member.get("id", 0))
	var current_position := Vector2(member.get("position", Vector2.ZERO))
	var current_target: Dictionary = member.get("target_slot", {})
	var current_target_position := Vector2(current_target.get("position", Vector2.INF))
	var candidates: Array[Dictionary] = []
	for slot: Dictionary in get_work_slots_for_room(room_id):
		var slot_position := Vector2(slot.get("position", Vector2.INF))
		if not slot_position.is_finite() or slot_position.distance_squared_to(current_target_position) < 0.0001:
			continue
		if _slot_claimed_by_other_crew(slot, crew_id) or _position_blocked_by_furniture(slot_position):
			continue
		if _segment_hits_any_furniture(current_position, slot_position, body_clearance):
			continue
		if not structure.is_crew_segment_clear(current_position, slot_position, body_clearance):
			continue
		candidates.append(slot)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return current_position.distance_squared_to(Vector2(a["position"])) < current_position.distance_squared_to(Vector2(b["position"]))
	)
	var recovered_slot: Dictionary = candidates[0]
	member["target_slot"] = recovered_slot
	member["position"] = recovered_slot["position"]
	member["current_cell"] = recovered_slot["cell"]
	member["state"] = "STATION RECOVERED"
	_arrive_at_assignment(member)
	return true


func _relinquish_unreachable_station(member: Dictionary) -> void:
	member["assigned_room_id"] = &""
	member["at_assignment"] = false
	member["path"] = []
	member["path_index"] = 0
	member["target_slot"] = {}
	member.erase("station_route_key")
	member.erase("station_route_index")
	member["state"] = "AWAITING CLEAR STATION"
	member["idle_time"] = random.randf_range(0.35, 0.75)
	member.erase("furniture_waypoint")
	member.erase("furniture_navigation_leg")


func _claim_doorway(member: Dictionary, door_id: String) -> bool:
	var crew_id := int(member.get("id", 0))
	var owner_id := int(doorway_reservations.get(door_id, 0))
	if owner_id == crew_id:
		return true
	if owner_id > 0:
		return false
	doorway_reservations[door_id] = crew_id
	return true


func _doorway_queue_index(member: Dictionary, door_id: String) -> int:
	var crew_id := int(member.get("id", 0))
	var index := 0
	for other: Dictionary in crew_members:
		if int(other.get("id", 0)) >= crew_id:
			continue
		if String(other.get("door_crossing_id", "")) != door_id:
			continue
		if bool(other.get("dead", false)) or bool(other.get("ejected", false)) or bool(other.get("incapacitated", false)):
			continue
		index += 1
	return index


func _sync_doorway_reservations() -> void:
	for door_value: Variant in doorway_reservations.keys().duplicate():
		var door_id := String(door_value)
		var owner := get_member(int(doorway_reservations.get(door_id, 0)))
		if (
			owner.is_empty()
			or bool(owner.get("dead", false))
			or bool(owner.get("ejected", false))
			or bool(owner.get("incapacitated", false))
			or String(owner.get("door_crossing_id", "")) != door_id
		):
			doorway_reservations.erase(door_id)


func _sync_crew_held_doors(structure: ShipStructuralState) -> void:
	if structure == null:
		crew_held_doors.clear()
		return
	var active_doors: Dictionary = {}
	for member: Dictionary in crew_members:
		if bool(member.get("dead", false)) or bool(member.get("ejected", false)):
			continue
		var door_id := String(member.get("door_crossing_id", ""))
		if door_id.is_empty():
			continue
		active_doors[door_id] = bool(active_doors.get(door_id, false)) or bool(member.get("door_crossing_hazard", false))
	for door_value: Variant in crew_held_doors.keys().duplicate():
		var door_id := String(door_value)
		if active_doors.has(door_id):
			continue
		var door: Dictionary = structure.doors.get(door_id, {})
		var was_requested_open := bool(door.get("requested_open", false))
		if bool(crew_held_doors.get(door_id, false)):
			structure.request_hazard_door_override(door_id, false)
		else:
			structure.request_door_open(door_id, false)
		if was_requested_open:
			_play_door_sound(structure, door_id, false)
		crew_held_doors.erase(door_id)
	for door_value: Variant in active_doors.keys():
		var door_id := String(door_value)
		var needs_hazard_override := bool(active_doors[door_id])
		var previously_hazardous := bool(crew_held_doors.get(door_id, false))
		if previously_hazardous and not needs_hazard_override:
			structure.request_hazard_door_override(door_id, false)
		if needs_hazard_override:
			structure.request_hazard_door_override(door_id, true)
		else:
			structure.request_door_open(door_id, true)
		crew_held_doors[door_id] = needs_hazard_override


func _play_door_sound(structure: ShipStructuralState, door_id: String, opening: bool) -> void:
	if structure == null or structure.door_definition == null or not structure.doors.has(door_id):
		return
	var ship_view := get_tree().get_first_node_in_group("ship_view")
	if not is_instance_valid(ship_view):
		return
	var zoom_controller := ship_view.get("zoom_controller") as Node
	if not is_instance_valid(zoom_controller):
		return
	var minimum_zoom := float(structure.door_definition.get("minimum_audible_zoom"))
	if float(zoom_controller.get("zoom_level")) < minimum_zoom:
		return
	var property_name := "opening_sound" if opening else "closing_sound"
	var sound := structure.door_definition.get(property_name) as AudioStream
	if sound == null:
		return
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(ship) or not is_instance_valid(ship.physics_body) or not is_instance_valid(combat):
		return
	var door: Dictionary = structure.doors[door_id]
	var cells: Array = door.get("cells", [])
	var world_position: Vector2 = ship.physics_body.global_position
	if cells.size() >= 2 and ship.physics_body.has_method("get_world_point_for_cell"):
		world_position = (
			Vector2(ship.physics_body.call("get_world_point_for_cell", Vector2i(cells[0])))
			+ Vector2(ship.physics_body.call("get_world_point_for_cell", Vector2i(cells[1])))
		) * 0.5
	combat.call(
		"_play_world_sound",
		sound,
		world_position,
		float(structure.door_definition.get("sound_volume_db")),
		float(structure.door_definition.get("sound_pitch_variation"))
	)


func _choose_new_assignment(member: Dictionary, structure: ShipStructuralState) -> void:
	# Ambient locations are scenery for genuinely jobless crew. A member with a
	# room assignment, repair/rescue task, medical route, or evacuation order may
	# never claim one just because their path happened to become empty.
	if not _member_available_for_idle_position(member):
		return
	if ambient_slots.is_empty():
		return
	var reserve_role := String(member.get("reserve_role", ""))
	var returning_from_rest := bool(member.get("return_to_idle_slot", false))
	member["return_to_idle_slot"] = false
	if returning_from_rest:
		var previous_slot: Dictionary = member.get("last_idle_slot", {})
		if _route_member_to_idle_slot(member, structure, previous_slot, reserve_role):
			return
	if not returning_from_rest and random.randf() <= rest_chance:
		var bed := _preferred_open_rest_slot(int(member["id"]))
		if not bed.is_empty():
			var bed_path := _find_path(structure, member["current_cell"], bed["cell"])
			if not bed_path.is_empty() or member["current_cell"] == bed["cell"]:
				member["target_slot"] = bed
				member["path"] = bed_path if not bed_path.is_empty() else [bed["cell"]]
				member["path_index"] = 0
				member["state"] = "MOVING"
				return
	for _attempt: int in range(12):
		var slot := _preferred_reserve_slot(reserve_role, int(member["id"])) if reserve_role != "" else _preferred_ambient_slot(random.randi(), int(member["id"]))
		if slot.is_empty():
			break
		if _route_member_to_idle_slot(member, structure, slot, reserve_role):
			return
	member["idle_time"] = random.randf_range(1.0, 3.0)


func _member_available_for_idle_position(member: Dictionary) -> bool:
	return _member_available_for_ship_duty(member) and StringName(member.get("assigned_room_id", &"")) == &""


func _clear_idle_routine(member: Dictionary) -> void:
	member.erase("return_to_idle_slot")
	member.erase("last_idle_slot")


func _route_member_to_idle_slot(member: Dictionary, structure: ShipStructuralState, slot: Dictionary, reserve_role: String) -> bool:
	if slot.is_empty() or _slot_claimed_by_other_crew(slot, int(member.get("id", 0))):
		return false
	var path := _find_path(structure, member["current_cell"], slot["cell"])
	if path.is_empty() and member["current_cell"] != slot["cell"]:
		return false
	member["target_slot"] = slot
	member["last_idle_slot"] = slot.duplicate(true)
	member["path"] = path if not path.is_empty() else [slot["cell"]]
	member["path_index"] = 0
	if reserve_role == "SECURITY":
		member["reserve_task"] = "SECURITY WATCH"
	elif reserve_role == "LABOR":
		member["reserve_task"] = "SERVICE RUN" if String(slot.get("room_type", "")) in ["WORKSHOP", "HANGAR", "MEDICAL", "MED_BAY"] else "SHIP LABOR"
	member["state"] = "MOVING"
	return true


func _preferred_reserve_slot(role: String, except_crew_id: int) -> Dictionary:
	var preferred_types: Array = (
		["SECURITY", "COMMAND", "BRIDGE", "CREW", "CREW_QUARTERS"]
		if role == "SECURITY"
		else ["WORKSHOP", "HANGAR", "MEDICAL", "MED_BAY", "CREW", "CREW_QUARTERS"]
	)
	var preferred: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for slot: Dictionary in ambient_slots:
		if _slot_claimed_by_other_crew(slot, except_crew_id):
			continue
		if String(slot.get("room_type", "")) in preferred_types:
			preferred.append(slot)
		else:
			fallback.append(slot)
	var candidates := preferred if not preferred.is_empty() else fallback
	if candidates.is_empty():
		return {}
	return candidates[random.randi_range(0, candidates.size() - 1)]


func _reserve_idle_state(member: Dictionary) -> String:
	match String(member.get("reserve_role", "")):
		"SECURITY":
			return "SECURITY WATCH"
		"LABOR":
			return String(member.get("reserve_task", "SHIP LABOR")).replace("_", " ")
		_:
			return "OFF DUTY"


func _preferred_ambient_slot(seed_offset: int = 0, except_crew_id: int = 0) -> Dictionary:
	if ambient_slots.is_empty():
		return {}
	var crew_quarters: Array[Dictionary] = []
	var unassigned_grids: Array[Dictionary] = []
	var other_grids: Array[Dictionary] = []
	for slot: Dictionary in ambient_slots:
		if _slot_claimed_by_other_crew(slot, except_crew_id):
			continue
		match int(slot.get("ambient_priority", 2)):
			0:
				crew_quarters.append(slot)
			1:
				unassigned_grids.append(slot)
			_:
				other_grids.append(slot)
	var roll := posmod(seed_offset, 100) if seed_offset != 0 else random.randi_range(0, 99)
	var candidates: Array[Dictionary] = crew_quarters
	if roll >= 70 and roll < 95 and not unassigned_grids.is_empty():
		candidates = unassigned_grids
	elif roll >= 95 and not other_grids.is_empty():
		candidates = other_grids
	elif candidates.is_empty():
		candidates = unassigned_grids if not unassigned_grids.is_empty() else other_grids
	if candidates.is_empty():
		return {}
	return candidates[posmod(seed_offset, candidates.size())] if seed_offset != 0 else candidates[random.randi_range(0, candidates.size() - 1)]


## Dedicated crew entry points live in the open center of Crew Quarters. They
## are intentionally not work or idle slots: after spawning, staffing assigns a
## destination and the member visibly walks there from a known-safe location.
func _preferred_crew_spawn_slot(seed_offset: int = 0, except_crew_id: int = 0, source_cell: Vector2i = Vector2i(2147483647, 2147483647)) -> Dictionary:
	var local_candidates: Array[Dictionary] = []
	var all_candidates: Array[Dictionary] = []
	for slot: Dictionary in crew_spawn_slots:
		if _slot_claimed_by_other_crew(slot, except_crew_id):
			continue
		all_candidates.append(slot)
		var module_rect: Rect2i = slot.get("module_rect", Rect2i())
		if module_rect.has_point(source_cell):
			local_candidates.append(slot)
	var candidates := local_candidates if not local_candidates.is_empty() else all_candidates
	if candidates.is_empty():
		return _preferred_ambient_slot(seed_offset, except_crew_id)
	return candidates[posmod(seed_offset, candidates.size())]


func _preferred_open_rest_slot(except_crew_id: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for slot: Dictionary in rest_slots:
		if not _slot_claimed_by_other_crew(slot, except_crew_id):
			candidates.append(slot)
	if candidates.is_empty():
		return {}
	return candidates[random.randi_range(0, candidates.size() - 1)]


func _preferred_reinforcement_slot(source_cell: Vector2i, except_crew_id: int = 0) -> Dictionary:
	return _preferred_crew_spawn_slot(random.randi(), except_crew_id, source_cell)


func _slot_claimed_by_other_crew(slot: Dictionary, except_crew_id: int = 0) -> bool:
	var slot_position: Vector2 = slot.get("position", Vector2.ZERO)
	for other: Dictionary in crew_members:
		if int(other.get("id", 0)) == except_crew_id or bool(other.get("ejected", false)):
			continue
		var other_target: Dictionary = other.get("target_slot", {})
		if not other_target.is_empty() and Vector2(other_target.get("position", Vector2.INF)).distance_squared_to(slot_position) < 0.0001:
			return true
		if (other.get("path", []) as Array).is_empty() and Vector2(other.get("position", Vector2.INF)).distance_squared_to(slot_position) < 0.0001:
			return true
	return false


func _arrive_at_assignment(member: Dictionary) -> void:
	member["path"] = []
	member["path_index"] = 0
	member.erase("station_route_key")
	member.erase("station_route_index")
	member.erase("door_crossing_key")
	member.erase("door_crossing_stage")
	member.erase("door_crossing_id")
	member.erase("door_crossing_hazard")
	var arrived_slot: Dictionary = member["target_slot"]
	member["position"] = arrived_slot["position"]
	member["facing_direction"] = arrived_slot.get("facing", member.get("facing_direction", Vector2.UP))
	if bool(arrived_slot.get("is_bed", false)):
		member["position"] = arrived_slot.get("bed_position", arrived_slot["position"])
		member["resting"] = true
		member["rest_remaining"] = random.randf_range(minimum_rest_seconds, maximum_rest_seconds)
		member["state"] = "RESTING"
		return
	member["idle_time"] = random.randf_range(float(crew_definition.get("minimum_idle_seconds")), float(crew_definition.get("maximum_idle_seconds")))
	if bool(member.get("evacuating", false)):
		member["evacuating"] = false
		member["state"] = "RECOVERING"
		member["idle_time"] = random.randf_range(3.0, 6.0)
	elif int(member.get("active_job_id", 0)) > 0:
		member["at_assignment"] = false
		if String(member.get("job_phase", "")) == "EQUIPPING":
			member["at_job"] = false
			member["state"] = "OUTFITTING"
		else:
			member["at_job"] = true
			member["state"] = "REPAIRING"
	else:
		member["at_assignment"] = StringName(member["assigned_room_id"]) != &""
		member["state"] = "MANNING" if bool(member["at_assignment"]) else _reserve_idle_state(member)
		if not bool(member["at_assignment"]) and bool(arrived_slot.get("is_idle_slot", false)):
			member["idle_time"] = random.randf_range(minimum_reserve_duty_seconds, maximum_reserve_duty_seconds)


func _finish_rest(member: Dictionary) -> void:
	var bed: Dictionary = member.get("target_slot", {})
	member["position"] = bed.get("position", member.get("position", Vector2.ZERO))
	member["resting"] = false
	member["rest_remaining"] = 0.0
	member["target_slot"] = {}
	member["return_to_idle_slot"] = true
	member["idle_time"] = 0.0
	member["state"] = _reserve_idle_state(member)


func _cancel_rest(member: Dictionary) -> void:
	if not bool(member.get("resting", false)) and not bool((member.get("target_slot", {}) as Dictionary).get("is_bed", false)):
		return
	var bed: Dictionary = member.get("target_slot", {})
	if bool(member.get("resting", false)):
		member["position"] = bed.get("position", member.get("position", Vector2.ZERO))
	member["resting"] = false
	member["rest_remaining"] = 0.0


func _steer_around_furniture(
	member: Dictionary,
	previous: Vector2,
	desired: Vector2,
	final_target: Vector2,
	structure: ShipStructuralState = null,
	body_radius: float = CREW_BODY_CLEARANCE
) -> Vector2:
	if bool(member.get("resting", false)) or (furniture_obstacles.is_empty() and furniture_obstacle_polygons.is_empty()):
		return desired
	var step_distance := previous.distance_to(desired)
	# Keep an obstacle detour stable across frames. Re-selecting the cheapest
	# corner every tick can make a crew member alternate sides forever instead
	# of committing to a route around a large furnishing such as the engine.
	if member.has("furniture_waypoint"):
		var saved_waypoint: Vector2 = member["furniture_waypoint"]
		if previous.distance_to(saved_waypoint) <= 0.025:
			member.erase("furniture_waypoint")
		elif _segment_hits_any_furniture(previous, saved_waypoint, body_radius):
			member.erase("furniture_waypoint")
		elif structure != null and not structure.is_crew_segment_clear(previous, saved_waypoint, body_radius):
			member.erase("furniture_waypoint")
		else:
			return previous.move_toward(saved_waypoint, step_distance)
	# A layout refresh can leave a crew member standing inside newly-authored
	# furniture. Escape that invalid starting position before asking the shared
	# route solver for an ordinary path.
	for obstacle: Rect2 in furniture_obstacles:
		var expanded := obstacle.grow(body_radius)
		if expanded.has_point(previous):
			var escape_point := _nearest_obstacle_exit(previous, expanded, final_target)
			if structure == null or structure.is_crew_segment_clear(previous, escape_point, body_radius):
				member["furniture_waypoint"] = escape_point
				return previous.move_toward(escape_point, step_distance)
			return previous
	for source_polygon: PackedVector2Array in furniture_obstacle_polygons:
		var expanded_polygon := _expanded_furniture_polygon(source_polygon, body_radius)
		if expanded_polygon.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(previous, expanded_polygon):
			var escape_point := _nearest_polygon_exit(previous, expanded_polygon, final_target)
			if structure == null or structure.is_crew_segment_clear(previous, escape_point, body_radius):
				member["furniture_waypoint"] = escape_point
				return previous.move_toward(escape_point, step_distance)
			return previous
	# The direct leg is clear, so ordinary movement can continue unchanged.
	if not _segment_hits_any_furniture(previous, final_target, body_radius):
		return desired
	# All room layouts use the same small visibility graph. It can route around
	# several rectangles and polygons, rather than making a local one-corner
	# guess that may deadlock when future layouts add more furnishings.
	var detour: Variant = _find_furniture_detour_waypoint(previous, final_target, structure, body_radius)
	if detour is Vector2:
		member["furniture_waypoint"] = detour
		return previous.move_toward(detour, step_distance)
	return previous


func _find_furniture_detour_waypoint(
	start: Vector2,
	goal: Vector2,
	structure: ShipStructuralState,
	body_radius: float
) -> Variant:
	var nodes: Array[Vector2] = [start, goal]
	var candidate_padding := 0.03
	for obstacle: Rect2 in furniture_obstacles:
		var expanded := obstacle.grow(body_radius)
		var candidates: Array[Vector2] = [
			expanded.position - Vector2(candidate_padding, candidate_padding),
			Vector2(expanded.end.x + candidate_padding, expanded.position.y - candidate_padding),
			expanded.end + Vector2(candidate_padding, candidate_padding),
			Vector2(expanded.position.x - candidate_padding, expanded.end.y + candidate_padding),
		]
		for candidate: Vector2 in candidates:
			_append_unique_navigation_node(nodes, candidate)
	for source_polygon: PackedVector2Array in furniture_obstacle_polygons:
		var expanded_polygon := _expanded_furniture_polygon(source_polygon, body_radius)
		var center := _polygon_center(expanded_polygon)
		for vertex: Vector2 in expanded_polygon:
			var outward := (vertex - center).normalized()
			_append_unique_navigation_node(nodes, vertex + outward * candidate_padding)

	var node_count := nodes.size()
	var distances := PackedFloat64Array()
	var previous_nodes := PackedInt32Array()
	var visited := PackedByteArray()
	distances.resize(node_count)
	previous_nodes.resize(node_count)
	visited.resize(node_count)
	for index: int in node_count:
		distances[index] = INF
		previous_nodes[index] = -1
		visited[index] = 0
	distances[0] = 0.0

	# Dijkstra is intentionally used here: authored rooms contain very few
	# obstacle vertices, and a complete visibility graph produces predictable,
	# layout-independent behavior without frame-to-frame corner oscillation.
	for _iteration: int in node_count:
		var current := -1
		var current_distance := INF
		for index: int in node_count:
			if visited[index] == 0 and distances[index] < current_distance:
				current = index
				current_distance = distances[index]
		if current < 0:
			break
		if current == 1:
			break
		visited[current] = 1
		for neighbor: int in node_count:
			if neighbor == current or visited[neighbor] != 0:
				continue
			if not _crew_navigation_segment_clear(nodes[current], nodes[neighbor], structure, body_radius):
				continue
			var proposed := current_distance + nodes[current].distance_to(nodes[neighbor])
			if proposed < distances[neighbor]:
				distances[neighbor] = proposed
				previous_nodes[neighbor] = current

	if previous_nodes[1] < 0:
		return null
	var cursor := 1
	while previous_nodes[cursor] > 0:
		cursor = previous_nodes[cursor]
	return nodes[cursor]


func _append_unique_navigation_node(nodes: Array[Vector2], candidate: Vector2) -> void:
	if _position_blocked_by_furniture(candidate):
		return
	for existing: Vector2 in nodes:
		if existing.distance_squared_to(candidate) <= 0.0004:
			return
	nodes.append(candidate)


func _crew_navigation_segment_clear(
	from: Vector2,
	to: Vector2,
	structure: ShipStructuralState,
	body_radius: float
) -> bool:
	if _segment_hits_any_furniture(from, to, body_radius):
		return false
	return structure == null or structure.is_crew_segment_clear(from, to, body_radius)


func _prepare_furniture_navigation_leg(member: Dictionary, navigation_leg_key: String) -> void:
	if String(member.get("furniture_navigation_leg", "")) == navigation_leg_key:
		return
	member["furniture_navigation_leg"] = navigation_leg_key
	member.erase("furniture_waypoint")
	member["blocked_navigation_time"] = 0.0
	member.erase("navigation_progress_target")
	member.erase("navigation_progress_best_distance")
	member["navigation_stall_time"] = 0.0
	member["navigation_recovery_count"] = 0


## Returns true when a member has failed to get measurably closer to the same
## navigation target for long enough to be considered genuinely jammed. Tiny
## sideways motion and corner oscillation intentionally count as no progress.
func _navigation_progress_stalled(member: Dictionary, position: Vector2, target: Vector2, delta: float) -> bool:
	var distance := position.distance_to(target)
	if distance <= 0.02:
		_reset_navigation_progress(member, target)
		return false
	var saved_target: Vector2 = member.get("navigation_progress_target", Vector2(INF, INF))
	if not saved_target.is_finite() or saved_target.distance_squared_to(target) > 0.000001:
		_reset_navigation_progress(member, target, distance)
		return false
	var best_distance := float(member.get("navigation_progress_best_distance", distance))
	if distance < best_distance - 0.002:
		member["navigation_progress_best_distance"] = distance
		member["navigation_stall_time"] = 0.0
		return false
	member["navigation_stall_time"] = float(member.get("navigation_stall_time", 0.0)) + delta
	return float(member["navigation_stall_time"]) >= 0.65


func _reset_navigation_progress(member: Dictionary, target: Vector2, distance: float = -1.0) -> void:
	member["navigation_progress_target"] = target
	member["navigation_progress_best_distance"] = distance if distance >= 0.0 else Vector2(member.get("position", target)).distance_to(target)
	member["navigation_stall_time"] = 0.0


func _nearest_obstacle_exit(position: Vector2, obstacle: Rect2, final_target: Vector2) -> Vector2:
	var padding := 0.035
	var candidates: Array[Vector2] = [
		Vector2(obstacle.position.x - padding, clampf(position.y, obstacle.position.y, obstacle.end.y)),
		Vector2(obstacle.end.x + padding, clampf(position.y, obstacle.position.y, obstacle.end.y)),
		Vector2(clampf(position.x, obstacle.position.x, obstacle.end.x), obstacle.position.y - padding),
		Vector2(clampf(position.x, obstacle.position.x, obstacle.end.x), obstacle.end.y + padding),
	]
	var best := candidates[0]
	var best_cost := INF
	for candidate: Vector2 in candidates:
		if _position_blocked_by_furniture(candidate):
			continue
		var cost := position.distance_to(candidate) + candidate.distance_to(final_target) * 0.15
		if cost < best_cost:
			best_cost = cost
			best = candidate
	return best


func _segment_hits_any_furniture(from: Vector2, to: Vector2, body_radius: float) -> bool:
	for obstacle: Rect2 in furniture_obstacles:
		if _segment_hits_rect(from, to, obstacle.grow(body_radius)):
			return true
	for polygon: PackedVector2Array in furniture_obstacle_polygons:
		if _segment_hits_polygon(from, to, _expanded_furniture_polygon(polygon, body_radius)):
			return true
	return false


func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	return (
		Geometry2D.segment_intersects_segment(from, to, a, b) != null
		or Geometry2D.segment_intersects_segment(from, to, b, c) != null
		or Geometry2D.segment_intersects_segment(from, to, c, d) != null
		or Geometry2D.segment_intersects_segment(from, to, d, a) != null
	)


func _position_blocked_by_furniture(position: Vector2) -> bool:
	for obstacle: Rect2 in furniture_obstacles:
		if obstacle.grow(CREW_BODY_CLEARANCE).has_point(position):
			return true
	for polygon: PackedVector2Array in furniture_obstacle_polygons:
		if Geometry2D.is_point_in_polygon(position, _expanded_furniture_polygon(polygon, CREW_BODY_CLEARANCE)):
			return true
	return false


func _expanded_furniture_polygon(polygon: PackedVector2Array, clearance: float) -> PackedVector2Array:
	if polygon.size() < 3 or clearance <= 0.0:
		return polygon
	var results := Geometry2D.offset_polygon(polygon, clearance, Geometry2D.JOIN_MITER)
	if results.is_empty():
		return polygon
	return results[0]


func _segment_hits_polygon(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(from, polygon) or Geometry2D.is_point_in_polygon(to, polygon):
		return true
	for index: int in polygon.size():
		var next_index := (index + 1) % polygon.size()
		if Geometry2D.segment_intersects_segment(from, to, polygon[index], polygon[next_index]) != null:
			return true
	return false


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	return center / float(polygon.size())


func _nearest_polygon_exit(position: Vector2, polygon: PackedVector2Array, final_target: Vector2) -> Vector2:
	var center := _polygon_center(polygon)
	var best_point := position
	var best_cost := INF
	for index: int in polygon.size():
		var next_index := (index + 1) % polygon.size()
		var edge_point := Geometry2D.get_closest_point_to_segment(position, polygon[index], polygon[next_index])
		var outward := (edge_point - center).normalized()
		var candidate := edge_point + outward * 0.035
		var cost := position.distance_to(candidate) + candidate.distance_to(final_target) * 0.15
		if cost < best_cost:
			best_cost = cost
			best_point = candidate
	return best_point


func _find_path(structure: ShipStructuralState, start: Vector2i, goal: Vector2i, allow_pressure_override: bool = false) -> Array:
	if not structure.cell_rooms.has(start) or not structure.cell_rooms.has(goal):
		return []
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if not structure.cell_rooms.has(current):
			continue
		if current == goal:
			break
		for connection: Dictionary in GRID_GEOMETRY.touching_neighbors(structure.layout, current):
			var neighbor: Vector2i = connection["cell"]
			if not structure.cell_rooms.has(neighbor) or came_from.has(neighbor):
				continue
			if structure.cell_rooms[current] != structure.cell_rooms[neighbor]:
				var door_id := structure.get_door_between_cells(current, neighbor)
				if door_id.is_empty() or bool(structure.doors[door_id]["locked"]) or (bool(structure.doors[door_id]["pressure_interlocked"]) and not allow_pressure_override):
					continue
			came_from[neighbor] = current
			frontier.append(neighbor)
	if not came_from.has(goal):
		return []
	var result: Array = []
	var step := goal
	while step != start:
		result.push_front(step)
		step = came_from[step]
	return result


func _cell_center(layout: Resource, cell: Vector2i) -> Vector2:
	return GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).get_center()


## Furnished cells do not always have a usable center. Route through a known
## clear slot in that cell (bed aisle, work position, or ambient parking point)
## so the cell graph cannot send crew directly into authored machinery.
func _safe_cell_navigation_point(layout: Resource, cell: Vector2i) -> Vector2:
	for slot: Dictionary in rest_slots:
		if Vector2i(slot.get("cell", Vector2i.ZERO)) == cell:
			var rest_position: Vector2 = slot.get("position", _cell_center(layout, cell))
			if not _position_blocked_by_furniture(rest_position):
				return rest_position
	var center := _cell_center(layout, cell)
	if not _position_blocked_by_furniture(center):
		return center
	var best_point := Vector2.INF
	var best_distance := INF
	for slot_collection: Array in [work_slots, ambient_slots]:
		for slot: Dictionary in slot_collection:
			if Vector2i(slot.get("cell", Vector2i.ZERO)) != cell:
				continue
			var candidate: Vector2 = slot.get("position", center)
			if _position_blocked_by_furniture(candidate):
				continue
			var distance := candidate.distance_squared_to(center)
			if distance < best_distance:
				best_distance = distance
				best_point = candidate
	if best_point != Vector2.INF:
		return best_point
	# Defensive fallback for a future furnishing without authored slots.
	var cell_rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).grow(-0.16)
	for offset: Vector2 in [Vector2(-0.30, 0.0), Vector2(0.30, 0.0), Vector2(0.0, -0.30), Vector2(0.0, 0.30)]:
		var candidate := Vector2(
			clampf(center.x + offset.x, cell_rect.position.x, cell_rect.end.x),
			clampf(center.y + offset.y, cell_rect.position.y, cell_rect.end.y)
		)
		if not _position_blocked_by_furniture(candidate):
			return candidate
	return center


func get_member(crew_id: int) -> Dictionary:
	for member: Dictionary in crew_members:
		if int(member["id"]) == crew_id:
			return member
	return {}


func get_effective_stat(crew_id: int, stat_id: StringName) -> float:
	var member := get_member(crew_id)
	if member.is_empty():
		return 0.0
	var value := float((member["stats"] as Dictionary).get(stat_id, 0.0))
	for equipment: Resource in member["equipment"]:
		if equipment != null:
			value += float((equipment.get("stat_modifiers") as Dictionary).get(stat_id, 0.0))
	return value


func equip_item(crew_id: int, slot_index: int, equipment: Resource) -> bool:
	var member := get_member(crew_id)
	if member.is_empty():
		return false
	var slots: Array[Resource] = member["equipment"]
	if slot_index < 0 or slot_index >= slots.size():
		return false
	slots[slot_index] = equipment
	return true


func unequip_item(crew_id: int, slot_index: int) -> Resource:
	var member := get_member(crew_id)
	if member.is_empty():
		return null
	var slots: Array[Resource] = member["equipment"]
	if slot_index < 0 or slot_index >= slots.size():
		return null
	var previous := slots[slot_index]
	slots[slot_index] = null
	return previous


func get_work_slots_for_room(room_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: Dictionary in work_slots:
		if slot["room_id"] == room_id:
			result.append(slot)
	return result


func assign_crew_to_room(crew_id: int, room_id: StringName, play_confirmation: bool = true) -> bool:
	var member := get_member(crew_id)
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if member.is_empty() or bool(member.get("ejected", false)) or bool(member.get("incapacitated", false)) or bool(member.get("dead", false)) or int(member.get("rescue_patient_id", 0)) > 0 or not is_instance_valid(ship) or ship.structural_state == null:
		return false
	_cancel_rest(member)
	_clear_idle_routine(member)
	var available_slots := get_work_slots_for_room(room_id)
	var occupied: Dictionary = {}
	for other: Dictionary in crew_members:
		if int(other["id"]) == crew_id or StringName(other["assigned_room_id"]) != room_id:
			continue
		occupied[_slot_key(other["target_slot"])] = true
	var chosen := _balanced_open_room_slot(available_slots, occupied, room_id, crew_id)
	if chosen.is_empty():
		return false
	var path := _find_path(ship.structural_state, member["current_cell"], chosen["cell"])
	if path.is_empty() and member["current_cell"] != chosen["cell"]:
		return false
	if path.is_empty():
		path = [chosen["cell"]]
	member["assigned_room_id"] = room_id
	member["reserve_role"] = ""
	member["reserve_task"] = ""
	member["target_slot"] = chosen
	member["path"] = path
	member["path_index"] = 0
	member["at_assignment"] = false
	member["state"] = "REPORTING"
	if play_confirmation:
		_play_assignment_sound()
	return true


func _balanced_open_room_slot(
	available_slots: Array[Dictionary],
	occupied: Dictionary,
	room_id: StringName,
	except_crew_id: int
) -> Dictionary:
	var piece_capacity: Dictionary = {}
	var piece_occupancy: Dictionary = {}
	for slot: Dictionary in available_slots:
		var piece_index := int(slot.get("piece_index", 0))
		piece_capacity[piece_index] = int(piece_capacity.get(piece_index, 0)) + 1
	for other: Dictionary in crew_members:
		if int(other.get("id", 0)) == except_crew_id or StringName(other.get("assigned_room_id", &"")) != room_id:
			continue
		var other_slot: Dictionary = other.get("target_slot", {})
		var piece_index := int(other_slot.get("piece_index", 0))
		piece_occupancy[piece_index] = int(piece_occupancy.get(piece_index, 0)) + 1
	var chosen: Dictionary = {}
	var best_fill := INF
	for slot: Dictionary in available_slots:
		if occupied.has(_slot_key(slot)) or _slot_claimed_by_other_crew(slot, except_crew_id):
			continue
		var piece_index := int(slot.get("piece_index", 0))
		var fill := float(piece_occupancy.get(piece_index, 0)) / maxf(float(piece_capacity.get(piece_index, 1)), 1.0)
		if fill < best_fill:
			best_fill = fill
			chosen = slot
	return chosen


func unassign_crew(crew_id: int) -> void:
	var member := get_member(crew_id)
	if member.is_empty():
		return
	_cancel_rest(member)
	_clear_idle_routine(member)
	member["assigned_room_id"] = &""
	member["reserve_role"] = ""
	member["reserve_task"] = ""
	member["at_assignment"] = false
	member["path"] = []
	member["path_index"] = 0
	member["state"] = "IDLE"
	member["idle_time"] = random.randf_range(0.5, 2.0)


func get_room_staffing(room_id: StringName) -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if _member_is_operating_room(member, room_id):
			count += 1
	return count


func get_room_present_count(room_id: StringName) -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if StringName(member["assigned_room_id"]) == room_id and bool(member["at_assignment"]) and int(member.get("active_job_id", 0)) <= 0 and not bool(member.get("ejected", false)):
			count += 1
	return count


func get_room_assigned_count(room_id: StringName) -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if StringName(member["assigned_room_id"]) == room_id:
			count += 1
	return count


func get_room_manning_requirements(room_id: StringName) -> Vector2i:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return Vector2i(1, 1)
	for room: Resource in ship.ship_layout.get("rooms"):
		if room.get("room_id") != room_id:
			continue
		if not room_type_uses_staffing(String(room.get("type_name"))):
			return Vector2i.ZERO
		var minimum := int(room.get("minimum_crew"))
		var optimal := int(room.get("optimal_crew"))
		var recipe: Resource = room.get("module_recipe")
		if recipe != null:
			minimum = maxi(minimum, int(recipe.get("minimum_crew")))
			optimal = maxi(optimal, int(recipe.get("optimal_crew")))
		return ROOM_STAFFING_RULES.effective_requirements(room, minimum, optimal)
	return Vector2i(1, 1)


func room_type_uses_staffing(type_name: String) -> bool:
	return type_name not in [
		"UNASSIGNED",
		"CREW",
		"CREW_QUARTERS",
		"MESS_HALL",
		"SUPPLY_STORAGE",
		"CARGO",
	]


func get_crew_capacity() -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null:
		return 0
	var capacity := 0
	for room: Resource in ship.ship_layout.get("rooms"):
		if String(room.get("type_name")) not in ["CREW", "CREW_QUARTERS"]:
			continue
		var berth_modules := _crew_quarters_module_count(room)
		capacity += berth_modules * crew_capacity_per_quarters_cell
	return capacity


## The construction grid is a quarter-room lattice: a normal 2x2 crew room is
## one berth module, not four independent quarters. Preserve explicit piece
## counts for merged rooms while normalizing legacy/raw lattice area the same
## way as ShipBuilderAnalyzer.
func _crew_quarters_module_count(room: Resource) -> int:
	if room == null:
		return 0
	var lattice_cells := 0
	for rect: Rect2i in room.get("grid_rects"):
		lattice_cells += rect.size.x * rect.size.y
	var area_modules := ceili(float(lattice_cells) / 4.0)
	return maxi(area_modules, maxi(int(room.get("installed_piece_count")), 1))


func get_living_crew_count() -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if not bool(member.get("dead", false)) and not bool(member.get("ejected", false)):
			count += 1
	return count


func get_healthy_crew_count() -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if _member_available_for_ship_duty(member):
			count += 1
	return count


func get_reserve_crew_count() -> int:
	return get_security_crew_count() + get_labor_crew_count()


func get_security_crew_count() -> int:
	return _reserve_role_count("SECURITY")


func get_labor_crew_count() -> int:
	return _reserve_role_count("LABOR")


func _reserve_role_count(role: String) -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if not bool(member.get("dead", false)) and not bool(member.get("ejected", false)) and String(member.get("reserve_role", "")) == role:
			count += 1
	return count


func get_unfilled_minimum_stations() -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null:
		return 0
	var missing := 0
	for room: Resource in ship.ship_layout.get("rooms"):
		var room_id: StringName = room.get("room_id")
		if get_room_staffing_priority(room_id) == StaffingPriority.STANDBY:
			continue
		var requirements := get_room_manning_requirements(room_id)
		missing += maxi(requirements.x - get_room_assigned_count(room_id), 0)
	return missing


func get_room_manning_efficiency(room_id: StringName) -> float:
	var requirements := get_room_manning_requirements(room_id)
	if requirements.y <= 0:
		return 1.0
	var staffed := get_room_staffing(room_id)
	if staffed < requirements.x:
		return 0.0
	var output := get_room_station_output(room_id)
	return clampf(output / maxf(float(requirements.y), 1.0), 0.0, 1.0)


func get_room_station_output(room_id: StringName) -> float:
	var output := 0.0
	for member: Dictionary in crew_members:
		if _member_is_operating_room(member, room_id):
			output += _member_station_output(member, room_id)
	return output


func get_room_operational_status(room_id: StringName) -> Dictionary:
	var requirements := get_room_manning_requirements(room_id)
	var assigned := get_room_assigned_count(room_id)
	var present := get_room_present_count(room_id)
	var operating := get_room_staffing(room_id)
	var efficiency := get_room_manning_efficiency(room_id)
	var pressure := 1.0
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship) and ship.structural_state != null:
		pressure = ship.structural_state.get_room_pressure(room_id)
	var room_type := ""
	if is_instance_valid(ship):
		room_type = String(ship.call("get_room_type_name", room_id))
	var power_factor := 1.0
	var basic_unpowered := false
	if is_instance_valid(ship):
		if ship.has_method("get_room_power_factor"):
			power_factor = float(ship.call("get_room_power_factor", room_id))
		if ship.has_method("room_type_has_basic_unpowered_operation"):
			basic_unpowered = bool(ship.call("room_type_has_basic_unpowered_operation", room_type))
	var state := "OPERATIONAL"
	var reason := "ROOM MANNED"
	if requirements.y <= 0:
		state = "NOMINAL"
		reason = "ENGINE ROOM GOVERNED" if room_type == "PROPULSION" else "NO LOCAL CREW REQUIRED"
	elif pressure < float(crew_rules.get("oxygen_hazard_threshold")):
		state = "SAFETY HOLD"
		reason = "ROOM IN VACUUM"
	elif power_factor <= 0.01 and not basic_unpowered:
		state = "POWERLESS"
		reason = "NO POWER GRID"
	elif assigned <= 0:
		var auxiliary_thrust := room_type == "PROPULSION" \
			and is_instance_valid(ship) \
			and ship.has_method("get_unmanned_propulsion_baseline") \
			and float(ship.call("get_unmanned_propulsion_baseline", room_id)) > 0.0
		if auxiliary_thrust:
			state = "AUXILIARY"
			reason = "ADJACENT ENGINE LINK • %d%% THRUST" % roundi(float(ship.call("get_unmanned_propulsion_baseline", room_id)) * 100.0)
		else:
			state = "UNMANNED"
			reason = "NO CREW ASSIGNED"
	elif present <= 0:
		state = "CREW EN ROUTE"
		reason = "ASSIGNED CREW NOT AT STATIONS"
	elif operating < requirements.x:
		state = "SAFETY HOLD"
		reason = "STATION CREW UNABLE TO WORK"
	elif power_factor < 0.99:
		state = "DEGRADED"
		reason = "LOW POWER" if basic_unpowered else "POWER LIMITED"
	elif efficiency < 0.98:
		state = "DEGRADED"
		reason = "PARTIAL STAFFING"
	return {
		"state": state,
		"reason": reason,
		"assigned": assigned,
		"present": present,
		"operating": operating,
		"optimal": requirements.y,
		"minimum": requirements.x,
		"efficiency": efficiency,
		"station_output": get_room_station_output(room_id),
		"pressure": pressure,
		"power_factor": power_factor,
	}


func _member_is_operating_room(member: Dictionary, room_id: StringName) -> bool:
	if bool(member.get("ejected", false)) or bool(member.get("incapacitated", false)) or bool(member.get("dead", false)):
		return false
	if StringName(member.get("assigned_room_id", &"")) != room_id:
		return false
	if not bool(member.get("at_assignment", false)):
		return false
	if int(member.get("active_job_id", 0)) > 0 or bool(member.get("evacuating", false)):
		return false
	var state := String(member.get("state", ""))
	if state in ["EVACUATING", "TRAPPED IN VACUUM", "NO EVACUATION ROUTE", "EJECTED INTO SPACE", "RECOVERING"]:
		return false
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship) and ship.structural_state != null:
		var current_room: StringName = ship.structural_state.cell_rooms.get(member.get("current_cell", Vector2i.ZERO), &"")
		if current_room != room_id:
			return false
		var pressure: float = ship.structural_state.get_room_pressure(room_id)
		if pressure < float(crew_rules.get("oxygen_hazard_threshold")) and not _permits_vacuum_work(member):
			return false
	return true


func _member_station_output(_member: Dictionary, _room_id: StringName) -> float:
	# Every healthy crew member fills one complete station. Room output is governed
	# by staffing count, power, damage, atmosphere, and adjacency—not hidden stats.
	return 1.0


func get_room_display_name(room_id: StringName) -> String:
	if room_id == &"":
		return "UNASSIGNED"
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship):
		for room: Resource in ship.ship_layout.get("rooms"):
			if room.get("room_id") == room_id:
				return String(room.get("display_name"))
	return String(room_id)


func get_room_staffing_priority(room_id: StringName) -> int:
	return int(room_staffing_priorities.get(room_id, StaffingPriority.AUTO))


func get_room_staffing_priority_label(room_id: StringName) -> String:
	match get_room_staffing_priority(room_id):
		StaffingPriority.STANDBY:
			return "STANDBY"
		StaffingPriority.PRIORITY:
			return "PRIORITY"
		_:
			return "AUTO"


func set_room_staffing_priority(room_id: StringName, priority: int) -> void:
	room_staffing_priorities[room_id] = clampi(priority, StaffingPriority.STANDBY, StaffingPriority.PRIORITY)
	staffing_rebalance_remaining = 0.0
	rebalance_staffing(true)


func cycle_room_staffing_priority(room_id: StringName) -> int:
	var current := get_room_staffing_priority(room_id)
	var next := StaffingPriority.PRIORITY if current == StaffingPriority.AUTO else (StaffingPriority.STANDBY if current == StaffingPriority.PRIORITY else StaffingPriority.AUTO)
	set_room_staffing_priority(room_id, next)
	return next


func rebalance_staffing(play_confirmation: bool = false) -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null or ship.structural_state == null:
		return 0
	_route_injured_crew_to_medical(ship.structural_state)
	var rooms: Array[Resource] = []
	for room: Resource in ship.ship_layout.get("rooms"):
		var room_id: StringName = room.get("room_id")
		if get_room_staffing_priority(room_id) == StaffingPriority.STANDBY:
			continue
		if get_room_manning_requirements(room_id).y > 0:
			rooms.append(room)
	rooms.sort_custom(_staffing_room_precedes)

	var duty_count := get_healthy_crew_count()
	var desired: Dictionary = {}
	var remaining := duty_count
	for room: Resource in rooms:
		var room_id: StringName = room.get("room_id")
		var minimum := get_room_manning_requirements(room_id).x
		var allocation := mini(minimum, remaining)
		desired[room_id] = allocation
		remaining -= allocation
	for room: Resource in rooms:
		if remaining <= 0:
			break
		var room_id: StringName = room.get("room_id")
		var optimal := get_room_manning_requirements(room_id).y
		var extra := mini(maxi(optimal - int(desired.get(room_id, 0)), 0), remaining)
		desired[room_id] = int(desired.get(room_id, 0)) + extra
		remaining -= extra

	var retained: Dictionary = {}
	for member: Dictionary in crew_members:
		if not _member_available_for_ship_duty(member):
			continue
		var assigned_room: StringName = member.get("assigned_room_id", &"")
		if assigned_room == &"":
			continue
		var retained_count := int(retained.get(assigned_room, 0))
		if retained_count < int(desired.get(assigned_room, 0)):
			retained[assigned_room] = retained_count + 1
		else:
			unassign_crew(int(member["id"]))

	var assigned_total := 0
	for room: Resource in rooms:
		var room_id: StringName = room.get("room_id")
		var deficit := maxi(int(desired.get(room_id, 0)) - get_room_assigned_count(room_id), 0)
		while deficit > 0:
			var candidate := _best_unassigned_crew_for_room(room_id)
			if candidate.is_empty() or not assign_crew_to_room(int(candidate["id"]), room_id, false):
				break
			assigned_total += 1
			deficit -= 1
	_assign_reserve_roles()
	_dispatch_reserve_damage_control(ship)
	if assigned_total > 0 and play_confirmation:
		_play_assignment_sound()
	return assigned_total


func _route_injured_crew_to_medical(structure: ShipStructuralState) -> void:
	for member: Dictionary in crew_members:
		if StringName(member.get("assigned_room_id", &"")) == &"" or bool(member.get("incapacitated", false)):
			continue
		var maximum_health := maxf(float(member.get("maximum_health", 1.0)), 1.0)
		var health_percent := 100.0 * float(member.get("health", maximum_health)) / maximum_health
		if health_percent >= float(crew_rules.get("medical_seek_health_percentage")):
			continue
		if not _has_available_medical_visit_slot(int(member["id"])):
			continue
		unassign_crew(int(member["id"]))
		_maybe_begin_medical_visit(member, structure)


func _has_available_medical_visit_slot(except_crew_id: int) -> bool:
	for slot: Dictionary in ambient_slots:
		if String(slot.get("room_type", "")) in ["MEDICAL", "MED_BAY"] and _room_capability_online(slot.get("room_id", &"")) and not _slot_claimed_by_other_crew(slot, except_crew_id):
			return true
	return false


func _assign_reserve_roles() -> void:
	var reserves: Array[Dictionary] = []
	for member: Dictionary in crew_members:
		if not _member_available_for_ship_duty(member):
			continue
		if StringName(member.get("assigned_room_id", &"")) == &"":
			reserves.append(member)
		else:
			member["reserve_role"] = ""
			member["reserve_task"] = ""
	if reserves.is_empty():
		return
	reserves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"])
	)
	var security_count := maxi(ceili(float(reserves.size()) / 3.0), 1)
	for index: int in range(reserves.size()):
		var member: Dictionary = reserves[index]
		var next_role := "SECURITY" if index < security_count else "LABOR"
		if String(member.get("reserve_role", "")) != next_role:
			member["reserve_role"] = next_role
			member["reserve_task"] = "SECURITY PATROL" if next_role == "SECURITY" else "SHIP LABOR"
			if (member.get("path", []) as Array).is_empty():
				member["idle_time"] = 0.0


func _dispatch_reserve_damage_control(ship: Node) -> void:
	if get_reserve_crew_count() <= 0 or ship.structural_state == null:
		return
	# Breaches are the first priority because they can cascade into oxygen loss.
	for wall_value: Variant in ship.structural_state.walls.values():
		if _available_reserve_responder_count() <= 0:
			return
		var wall: Dictionary = wall_value
		if float(wall["current"]) < float(wall["maximum"]):
			request_wall_repair(String(wall["key"]))
	# Internal machinery damage follows once the hull is sealed.
	for room: Resource in ship.ship_layout.get("rooms"):
		if _available_reserve_responder_count() <= 0:
			return
		var room_id: StringName = room.get("room_id")
		var room_data: Dictionary = ship.get_room_data(room_id)
		if not room_data.is_empty() and float(room_data["current_health"]) < float(room_data["maximum_health"]):
			request_room_repair(room_id)


func _available_reserve_responder_count() -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if _member_available_for_ship_duty(member) and StringName(member.get("assigned_room_id", &"")) == &"" and String(member.get("reserve_role", "")) != "":
			count += 1
	return count


func _staffing_room_precedes(a: Resource, b: Resource) -> bool:
	var a_priority := get_room_staffing_priority(a.get("room_id"))
	var b_priority := get_room_staffing_priority(b.get("room_id"))
	if a_priority != b_priority:
		return a_priority > b_priority
	var a_base := _room_priority(a)
	var b_base := _room_priority(b)
	if a_base != b_base:
		return a_base < b_base
	return String(a.get("display_name")) < String(b.get("display_name"))


func _best_unassigned_crew_for_room(_room_id: StringName) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for member: Dictionary in crew_members:
		if not _member_available_for_ship_duty(member) or StringName(member.get("assigned_room_id", &"")) != &"":
			continue
		candidates.append(member)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"])
	)
	return candidates[0] if not candidates.is_empty() else {}


func _member_available_for_ship_duty(member: Dictionary) -> bool:
	return (
		not bool(member.get("ejected", false))
		and not bool(member.get("incapacitated", false))
		and not bool(member.get("dead", false))
		and not bool(member.get("seeking_medical", false))
		and int(member.get("rescue_patient_id", 0)) <= 0
		and int(member.get("carried_by", 0)) <= 0
		and int(member.get("active_job_id", 0)) <= 0
		and not bool(member.get("evacuating", false))
	)


func auto_assign_room(room_id: StringName, play_confirmation: bool = true) -> int:
	var requirements := get_room_manning_requirements(room_id)
	var needed := maxi(requirements.y - get_room_assigned_count(room_id), 0)
	var assigned := 0
	for member: Dictionary in crew_members:
		if needed <= 0:
			break
		if bool(member.get("ejected", false)) or bool(member.get("incapacitated", false)) or bool(member.get("dead", false)) or int(member.get("rescue_patient_id", 0)) > 0 or StringName(member["assigned_room_id"]) != &"":
			continue
		if assign_crew_to_room(int(member["id"]), room_id, false):
			assigned += 1
			needed -= 1
	if assigned > 0 and play_confirmation:
		_play_assignment_sound()
	return assigned


func auto_assign_priority_rooms() -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.ship_layout == null:
		return 0
	var room_defs: Array = ship.ship_layout.get("rooms")
	var assignable_rooms: Array[Resource] = []
	for room: Resource in room_defs:
		if _room_priority(room) >= 900:
			continue
		var room_id: StringName = room.get("room_id")
		var requirements := get_room_manning_requirements(room_id)
		if requirements.y <= 0:
			continue
		if get_room_assigned_count(room_id) >= requirements.y:
			continue
		assignable_rooms.append(room)
	assignable_rooms.sort_custom(func(a: Resource, b: Resource) -> bool:
		var priority_a := _room_priority(a)
		var priority_b := _room_priority(b)
		if priority_a == priority_b:
			return String(a.get("display_name")) < String(b.get("display_name"))
		return priority_a < priority_b
	)
	var total_assigned := 0
	for room: Resource in assignable_rooms:
		total_assigned += auto_assign_room(room.get("room_id"), false)
		if _unassigned_crew_count() <= 0:
			break
	if total_assigned > 0:
		_play_assignment_sound()
	return total_assigned


func _room_priority(room: Resource) -> int:
	var type_name := String(room.get("type_name"))
	match type_name:
		"COMMAND", "BRIDGE":
			return 0
		"POWER", "REACTOR", "ENGINE":
			return 10
		"SHIELDS":
			return 20
		"WEAPONS":
			return 30
		"HANGAR":
			return 40
		"PROPULSION":
			return 50
		"MEDICAL", "MED_BAY":
			return 60
		"SECURITY":
			return 65
		"CREW", "CREW_QUARTERS":
			return 70
		"WORKSHOP":
			return 80
		"SUPPLY_STORAGE", "CARGO":
			return 90
		_:
			return 999


func _unassigned_crew_count() -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if bool(member.get("ejected", false)):
			continue
		if StringName(member.get("assigned_room_id", &"")) == &"":
			count += 1
	return count


func get_assigned_members(room_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in crew_members:
		if StringName(member["assigned_room_id"]) == room_id:
			result.append(member)
	return result


func _play_assignment_sound() -> void:
	if assignment_sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = assignment_sound
	player.volume_db = assignment_volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _slot_key(slot: Dictionary) -> String:
	return "%s:%d,%d:%d" % [String(slot["room_id"]), int(slot["cell"].x), int(slot["cell"].y), int(slot["slot_index"])]


func request_room_repair(room_id: StringName) -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return 0
	var room: Dictionary = ship.get_room_data(room_id)
	if room.is_empty() or float(room["current_health"]) >= float(room["maximum_health"]):
		return 0
	for job: Dictionary in damage_control_jobs:
		if String(job["type"]) == "ROOM" and StringName(job["room_id"]) == room_id:
			return int(job["id"])
	var slots := get_work_slots_for_room(room_id)
	if slots.is_empty():
		return 0
	var target: Dictionary = {}
	for slot: Dictionary in slots:
		if not _slot_claimed_by_other_crew(slot):
			target = slot
			break
	if target.is_empty():
		return 0
	var job := _create_damage_control_job("ROOM", room_id, "", target)
	_assign_available_repairers(job, ship.structural_state)
	return int(job["id"])


func request_wall_repair(wall_key: String) -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.structural_state == null or not ship.structural_state.walls.has(wall_key):
		return 0
	var wall: Dictionary = ship.structural_state.walls[wall_key]
	if float(wall["current"]) >= float(wall["maximum"]):
		return 0
	for job: Dictionary in damage_control_jobs:
		if String(job["type"]) == "WALL" and String(job["wall_key"]) == wall_key:
			return int(job["id"])
	var cells: Array = wall["cells"]
	if cells.is_empty():
		return 0
	var cell: Vector2i = cells[0]
	var cell_center := _cell_center(ship.ship_layout, cell)
	var wall_center := (Vector2(wall["start"]) + Vector2(wall["end"])) * 0.5
	var room_id: StringName = ship.structural_state.cell_rooms.get(cell, &"")
	var clearance := float(crew_definition.get("collision_radius_cells")) if crew_definition != null else 0.44
	var inward := (cell_center - wall_center).normalized()
	var repair_position := wall_center + inward * clearance
	var target := {
		"room_id": room_id,
		"cell": cell,
		"slot_index": -1,
		"position": repair_position,
		"facing": (wall_center - repair_position).normalized(),
	}
	var job := _create_damage_control_job("WALL", room_id, wall_key, target)
	_assign_available_repairers(job, ship.structural_state)
	return int(job["id"])


func request_room_breach_repairs(room_id: StringName) -> int:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or ship.structural_state == null:
		return 0
	var created := 0
	for wall_value: Variant in ship.structural_state.walls.values():
		var wall: Dictionary = wall_value
		if float(wall["current"]) >= float(wall["maximum"]):
			continue
		var touches_room := false
		for cell_value: Variant in wall["cells"]:
			if StringName(ship.structural_state.cell_rooms.get(cell_value, &"")) == room_id:
				touches_room = true
				break
		if touches_room and request_wall_repair(String(wall["key"])) > 0:
			created += 1
	return created


func _create_damage_control_job(type_name: String, room_id: StringName, wall_key: String, target: Dictionary) -> Dictionary:
	var job := {
		"id": next_job_id,
		"type": type_name,
		"room_id": room_id,
		"wall_key": wall_key,
		"target": target,
		"assigned_crew": [],
		"state": "QUEUED",
		"progress": 0.0,
		"safety_hold": false,
	}
	next_job_id += 1
	damage_control_jobs.append(job)
	return job


func _assign_available_repairers(job: Dictionary, structure: ShipStructuralState) -> void:
	var candidates: Array[Dictionary] = []
	var target_room: StringName = StringName(job["room_id"])
	var unsafe_atmosphere := structure.get_room_pressure(target_room) < float(crew_rules.get("safe_repair_oxygen"))
	job["requires_environment"] = unsafe_atmosphere
	for member: Dictionary in crew_members:
		if not _member_available_for_ship_duty(member):
			continue
		var assigned_room: StringName = member.get("assigned_room_id", &"")
		if assigned_room != &"":
			var requirements := get_room_manning_requirements(assigned_room)
			var room_has_surplus := get_room_assigned_count(assigned_room) > requirements.x
			if not room_has_surplus:
				continue
		candidates.append(member)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_assigned: StringName = a.get("assigned_room_id", &"")
		var b_assigned: StringName = b.get("assigned_room_id", &"")
		if (a_assigned == &"") != (b_assigned == &""):
			return a_assigned == &""
		var a_labor := String(a.get("reserve_role", "")) == "LABOR"
		var b_labor := String(b.get("reserve_role", "")) == "LABOR"
		if a_labor != b_labor:
			return a_labor
		var a_priority := get_room_staffing_priority(a_assigned) if a_assigned != &"" else StaffingPriority.STANDBY
		var b_priority := get_room_staffing_priority(b_assigned) if b_assigned != &"" else StaffingPriority.STANDBY
		if a_priority != b_priority:
			return a_priority < b_priority
		return int(a["id"]) < int(b["id"])
	)
	var maximum := mini(int(crew_rules.get("maximum_repairers_per_job")), candidates.size())
	for index: int in range(maximum):
		_assign_member_to_job(candidates[index], job, structure)
	if not (job["assigned_crew"] as Array).is_empty():
		job["state"] = "OUTFITTING"
	elif candidates.is_empty():
		job["state"] = "AWAITING RESERVE CREW"
	else:
		var ship := get_tree().get_first_node_in_group("ship_simulation")
		var providers: Array[Dictionary] = ship.get_capability_providers("DAMAGE_CONTROL") if is_instance_valid(ship) else []
		var online_provider := false
		for provider: Dictionary in providers:
			online_provider = online_provider or bool(provider.get("online", false))
		job["state"] = "NO ENGINEERING BAY" if providers.is_empty() else ("NO ACCESSIBLE ROUTE" if online_provider else "ENGINEERING BAY OFFLINE")


func _assign_member_to_job(member: Dictionary, job: Dictionary, structure: ShipStructuralState) -> void:
	var provider := _best_equipment_provider(member, job, structure)
	if provider.is_empty():
		return
	_cancel_rest(member)
	_clear_idle_routine(member)
	member["assigned_room_id"] = &""
	member["at_assignment"] = false
	member["active_job_id"] = job["id"]
	member["job_phase"] = "EQUIPPING"
	member["equipped_from_room_id"] = provider["room_id"]
	member["has_repair_gear"] = false
	member["has_environmental_gear"] = false
	member["equip_remaining"] = 0.8
	member["at_job"] = false
	member["target_slot"] = provider["slot"]
	member["path"] = provider["path"]
	member["path_index"] = 0
	member["state"] = "TO ENGINEERING BAY"
	(job["assigned_crew"] as Array).append(member["id"])


func _best_equipment_provider(member: Dictionary, job: Dictionary, structure: ShipStructuralState) -> Dictionary:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return {}
	var best: Dictionary = {}
	var best_distance := 2147483647
	for provider: Dictionary in ship.get_capability_providers("DAMAGE_CONTROL"):
		if not bool(provider.get("online", false)):
			continue
		var provider_id: StringName = provider["id"]
		if _provider_claim_count(provider_id) >= int(provider.get("channels", 0)):
			continue
		for slot: Dictionary in ambient_slots:
			if StringName(slot.get("room_id", &"")) != provider_id or _slot_claimed_by_other_crew(slot, int(member["id"])):
				continue
			var route_to_bay := _find_path(structure, member["current_cell"], slot["cell"])
			if route_to_bay.is_empty() and member["current_cell"] != slot["cell"]:
				continue
			var route_to_job := _find_path(structure, slot["cell"], job["target"]["cell"], bool(job.get("requires_environment", false)))
			if route_to_job.is_empty() and slot["cell"] != job["target"]["cell"]:
				continue
			var distance := route_to_bay.size() + route_to_job.size()
			if distance < best_distance:
				best_distance = distance
				best = {
					"room_id": provider_id,
					"slot": slot,
					"path": route_to_bay if not route_to_bay.is_empty() else [slot["cell"]],
				}
	return best


func _provider_claim_count(room_id: StringName) -> int:
	var count := 0
	for member: Dictionary in crew_members:
		if int(member.get("active_job_id", 0)) > 0 and StringName(member.get("equipped_from_room_id", &"")) == room_id:
			count += 1
	return count


func _update_damage_control_jobs(ship: Node, delta: float) -> void:
	for index: int in range(damage_control_jobs.size() - 1, -1, -1):
		var job: Dictionary = damage_control_jobs[index]
		var active_members: Array[Dictionary] = []
		var valid_ids: Array = []
		for crew_id: Variant in job["assigned_crew"]:
			var member := get_member(int(crew_id))
			if not member.is_empty() and not bool(member.get("ejected", false)) and int(member.get("active_job_id", 0)) == int(job["id"]):
				valid_ids.append(crew_id)
				if bool(member.get("at_job", false)):
					active_members.append(member)
		job["assigned_crew"] = valid_ids
		if valid_ids.is_empty() and not bool(job.get("safety_hold", false)):
			_assign_available_repairers(job, ship.structural_state)
		if active_members.is_empty():
			continue
		job["state"] = "REPAIRING"
		var repair_crew_multiplier := float(active_members.size())
		var complete := false
		if String(job["type"]) == "ROOM":
			var room: Dictionary = ship.get_room_data(job["room_id"])
			if room.is_empty():
				complete = true
			else:
				ship.repair_room(job["room_id"], float(crew_rules.get("room_repair_per_second")) * repair_crew_multiplier * delta)
				var updated: Dictionary = ship.get_room_data(job["room_id"])
				job["progress"] = float(updated["current_health"]) / maxf(float(updated["maximum_health"]), 0.001)
				complete = float(updated["current_health"]) >= float(updated["maximum_health"]) - 0.001
		else:
			var wall_key := String(job["wall_key"])
			if not ship.structural_state.walls.has(wall_key):
				complete = true
			else:
				ship.structural_state.repair_wall_amount(wall_key, float(crew_rules.get("wall_repair_per_second")) * repair_crew_multiplier * delta)
				var wall: Dictionary = ship.structural_state.walls[wall_key]
				job["progress"] = float(wall["current"]) / maxf(float(wall["maximum"]), 0.001)
				complete = float(wall["current"]) >= float(wall["maximum"]) - 0.001
		if complete:
			_complete_damage_control_job(job)
			damage_control_jobs.remove_at(index)


func _complete_damage_control_job(job: Dictionary) -> void:
	for crew_id: Variant in job["assigned_crew"]:
		var member := get_member(int(crew_id))
		if member.is_empty():
			continue
		member["active_job_id"] = 0
		member["job_phase"] = ""
		member["equipped_from_room_id"] = &""
		member["has_repair_gear"] = false
		member["has_environmental_gear"] = false
		member["equip_remaining"] = 0.0
		member["at_job"] = false
		member["state"] = "IDLE"
		member["idle_time"] = random.randf_range(1.0, 3.0)
	staffing_rebalance_remaining = 0.0


func get_jobs_for_room(room_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in damage_control_jobs:
		if StringName(job["room_id"]) == room_id:
			result.append(job)
	return result
