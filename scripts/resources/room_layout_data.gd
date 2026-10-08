@tool
class_name RoomLayoutData
extends Resource

enum WeaponFireMode {
	LINKED,
	TRIGGER,
	SENTRY,
}

@export var room_id: StringName
@export var display_name := "ROOM"
@export var type_name := "UNASSIGNED"
@export var effect_label := "SYSTEM OUTPUT"
@export_multiline var description := ""
@export var grid_label := ""
@export var grid_rects: Array[Rect2i] = []
## Blueprint footprint measured in quarter-module lattice cells. A legacy/full
## compartment is 2x2, a quarter module is 1x1, and a long half-room is 1x2.
## Installed rooms store their occupied shape in grid_rects; this value is the
## catalog/template shape used when a new piece is picked up.
@export var build_footprint_lattice := Vector2i(2, 2)
@export var color := Color(0.2, 0.24, 0.25)
@export_range(1.0, 10000.0, 1.0) var maximum_health := 100.0
@export var produces_output := true
@export var contributes_to_hull := true
@export_category("Power Coverage")
## Number of overlapping reactor fields required for full operation. Zero uses
## the default for this grid type or its installed module recipe.
@export_range(0, 8, 1) var required_reactor_fields := 0
@export_category("Ship Logistics")
## NONE, SUPPLY, or CARGO. Supply storage serves crew operations; cargo storage holds trade and salvage freight.
@export_enum("NONE", "SUPPLY", "CARGO") var storage_role := "NONE"
## Storage volume contributed by each occupied grid cell before staffing and module modifiers.
@export_range(0.0, 100000.0, 1.0) var storage_capacity_per_cell := 0.0
@export_category("Crew Manning")
## Crew who must be physically at work slots before this room produces any output.
@export_range(0, 1000, 1) var minimum_crew := 1
## Crew required at work slots for 100% room output. Installed module recipes may override this.
@export_range(0, 1000, 1) var optimal_crew := 1
@export_category("Base Grid Adjacency")
## Requirements that must be satisfied before this base grid type can be installed in the shipyard.
@export var build_requirements: Array[Resource] = []
## Effects this basic section type applies to touching sections even when it has no specialized module installed.
@export var adjacency_effects: Array[Resource] = []
@export var weapon_definition: Resource
@export_category("Module Footprint")
@export var module_recipe: Resource
@export_range(0, 3, 1) var module_rotation_quarters := 0
@export_range(-1, 3, 1) var module_facing_quarters := -1
## Number of independently installed pieces represented by this compartment.
## Like pieces may share one room while preserving their individual hardware.
@export_range(1, 1000, 1) var installed_piece_count := 1
## Facing for each installed piece, aligned with grid_rects. Older layouts fall
## back to module_facing_quarters when this array is empty.
@export var module_mount_facings: Array[int] = []
## Fire-control directive for each independently installed weapon mount,
## aligned with grid_rects. LINKED fires automatically until manual control is
## engaged, TRIGGER is manual-only, and SENTRY remains autonomous at all times.
@export var weapon_fire_modes: Array[int] = []
@export var module_mirrored := false


func get_weapon_fire_mode(mount_index: int) -> int:
	if mount_index >= 0 and mount_index < weapon_fire_modes.size():
		return clampi(weapon_fire_modes[mount_index], WeaponFireMode.LINKED, WeaponFireMode.SENTRY)
	return WeaponFireMode.LINKED


func set_weapon_fire_mode(mount_index: int, fire_mode: int) -> void:
	if mount_index < 0:
		return
	var mount_count := maxi(installed_piece_count, maxi(grid_rects.size(), 1))
	while weapon_fire_modes.size() < mount_count:
		weapon_fire_modes.append(WeaponFireMode.LINKED)
	if mount_index >= weapon_fire_modes.size():
		return
	weapon_fire_modes[mount_index] = clampi(fire_mode, WeaponFireMode.LINKED, WeaponFireMode.SENTRY)
	emit_changed()
