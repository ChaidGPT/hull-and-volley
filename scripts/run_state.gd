class_name RunState
extends Node

signal run_started(run_seed: int)
signal sector_depth_changed(depth: int, sector: GeneratedSector)
signal pursuit_trace_changed(report: Dictionary)
signal pursuit_stage_changed(stage: int, report: Dictionary)

@export var authored_run_seed := 0

var run_seed := 1
var sector_depth := 0
var current_sector: GeneratedSector
var visited_sector_ids := PackedStringArray()
var visited_archetypes := PackedStringArray()
var journey_sectors: Array[Resource] = []
var journey_route_slots := PackedInt32Array()
var run_active := false
var pursuit_trace := 0.0
var persistent_heat := 0.0
var pursuit_stage := 0

const PURSUIT_STAGE_NAMES := [
	"SIGNAL QUIET",
	"SEARCH PATTERN",
	"POSITION COMPROMISED",
	"LOCKDOWN IMMINENT",
	"KILL ORDER",
]


func _ready() -> void:
	add_to_group("run_state")
	run_seed = authored_run_seed
	if run_seed == 0:
		run_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	run_started.emit(run_seed)
	set_process(true)


func _process(delta: float) -> void:
	if not run_active:
		return
	# A full trace takes several minutes without player-generated noise. Modal
	# terminals pause this node automatically, so planning never burns the clock.
	add_pursuit_trace(delta * 0.105, &"TIME")


func begin_new_run(seed_override: int = 0) -> void:
	run_seed = seed_override
	if run_seed == 0:
		run_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	sector_depth = 0
	current_sector = null
	visited_sector_ids.clear()
	visited_archetypes.clear()
	journey_sectors.clear()
	journey_route_slots.clear()
	persistent_heat = 0.0
	pursuit_trace = 4.0
	pursuit_stage = 0
	run_active = true
	run_started.emit(run_seed)
	_emit_pursuit_report(true)


func add_pursuit_trace(amount: float, reason: StringName = &"NOISE") -> void:
	if not run_active or amount <= 0.0:
		return
	var previous_stage := pursuit_stage
	pursuit_trace = clampf(pursuit_trace + amount, 0.0, 100.0)
	pursuit_stage = clampi(int(floor(pursuit_trace / 25.0)), 0, 4)
	_emit_pursuit_report(previous_stage != pursuit_stage, reason)


func get_pursuit_report(reason: StringName = &"") -> Dictionary:
	return {
		"active": run_active,
		"trace": pursuit_trace,
		"heat": persistent_heat,
		"stage": pursuit_stage,
		"stage_name": PURSUIT_STAGE_NAMES[pursuit_stage],
		"reason": reason,
	}


func _emit_pursuit_report(stage_changed: bool = false, reason: StringName = &"") -> void:
	var report := get_pursuit_report(reason)
	pursuit_trace_changed.emit(report)
	if stage_changed:
		pursuit_stage_changed.emit(pursuit_stage, report)


func advance_to_sector(sector: GeneratedSector) -> void:
	if sector == null:
		return
	sector_depth = maxi(sector.run_depth, sector_depth + 1)
	current_sector = sector
	visited_sector_ids.append(String(sector.sector_id))
	visited_archetypes.append(String(sector.archetype_id))
	journey_sectors.append(sector)
	journey_route_slots.append(clampi(int(sector.get_meta("route_slot", 1)), 0, 2))
	if run_active:
		persistent_heat = minf(40.0, maxf(persistent_heat, pursuit_trace * 0.22) + 2.0)
		pursuit_trace = clampf(persistent_heat + float(sector_depth - 1) * 3.0, 0.0, 100.0)
		var previous_stage := pursuit_stage
		pursuit_stage = clampi(int(floor(pursuit_trace / 25.0)), 0, 4)
		_emit_pursuit_report(previous_stage != pursuit_stage, &"SECTOR_ENTRY")
	sector_depth_changed.emit(sector_depth, sector)


func has_recent_archetype(archetype_id: StringName, lookback: int = 2) -> bool:
	var start_index := maxi(visited_archetypes.size() - maxi(lookback, 0), 0)
	for index: int in range(start_index, visited_archetypes.size()):
		if StringName(visited_archetypes[index]) == archetype_id:
			return true
	return false
