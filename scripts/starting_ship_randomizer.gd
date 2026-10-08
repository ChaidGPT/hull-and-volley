class_name StartingShipRandomizer
extends RefCounted

const BASE_LAYOUT := preload("res://resources/ship_designs/barebones_starter.tres")
const SHIP_BUILDER_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const GRID_INVENTORY_CATALOG := preload("res://scripts/grid_inventory_catalog.gd")

const PROFILE_ORDER := [&"INTERCEPTOR", &"WARDEN", &"RAIDER"]
## The escape-hangar pool is intentionally smaller than the Forge catalog.
## Only mounts with finished room and weapon artwork belong in a live run.
const JAILBREAK_WEAPON_IDS: Array[StringName] = [
	&"explosive_cannon",
	&"laser_emitter",
]
const CALLSIGNS := [
	"EMBER", "KITE", "MONGREL", "LATCHKEY", "SUNDOG", "VAGRANT",
	"NEEDLE", "GHOSTLIGHT", "RUSTWING", "JACKAL", "CINDER", "WAYWARD",
]

const VISUAL_READY_DRAFT_POOL := [
	"WEAPON:explosive_cannon_mount",
	"WEAPON:laser_emitter_mount",
	"SHIELDS",
	"PROPULSION",
	"POWER",
	"CREW_QUARTERS",
]


func generate_draft_rounds(random_seed: int = 0) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	if random_seed == 0:
		random.randomize()
	else:
		random.seed = random_seed
	var specialization_pool := VISUAL_READY_DRAFT_POOL.duplicate()
	_shuffle(specialization_pool, random)
	return [
		{
			"title": "WEAPONS LOCKER",
			"warning": "SELECT ONE FIRE-CONTROL PACKAGE • THE OTHER WILL BE PURGED",
			"options": [
				_draft_option("WEAPON:explosive_cannon_mount", "HEAVY SHELLS • IMPACT DAMAGE"),
				_draft_option("WEAPON:laser_emitter_mount", "PRECISION BEAM • RAPID RESPONSE"),
			],
		},
		{
			"title": "EXTERIOR SYSTEMS RACK",
			"warning": "SELECT ONE SURVIVAL SYSTEM • THE OTHER WILL BE ABANDONED",
			"options": [
				_draft_option("SHIELDS", "DIRECTIONAL PROTECTION • MUST FACE OUTBOARD"),
				_draft_option("PROPULSION", "ADDITIONAL THRUST • DIRECTION SET BY PLACEMENT"),
			],
		},
		{
			"title": "LAST OPEN CARGO CRADLE",
			"warning": "SELECT ONE FINAL GRID • LOCKDOWN IS CLOSING",
			"options": [
				_draft_option(String(specialization_pool[0]), "FINAL SALVAGE ALLOCATION"),
				_draft_option(String(specialization_pool[1]), "FINAL SALVAGE ALLOCATION"),
			],
		},
	]


func _draft_option(inventory_key: String, role_text: String) -> Dictionary:
	var descriptor := GRID_INVENTORY_CATALOG.describe(BASE_LAYOUT, inventory_key)
	return {
		"inventory_key": inventory_key,
		"name": String(descriptor.get("display_name", inventory_key)).to_upper(),
		"role": role_text,
		"descriptor": descriptor,
		"preview_layout": _draft_preview_layout(inventory_key, descriptor),
	}


func _draft_preview_layout(inventory_key: String, descriptor: Dictionary) -> Resource:
	var layout: Resource = BASE_LAYOUT.duplicate(true)
	layout.set("design_name", String(descriptor.get("display_name", "SALVAGE GRID")))
	layout.set("lattice_version", 2)
	layout.set("build_origin", Vector2i.ZERO)
	layout.set("columns", 6)
	layout.set("rows", 6)
	var rooms: Array[Resource] = []
	layout.set("rooms", rooms)
	var room_type := String(descriptor.get("room_type", inventory_key))
	var footprint := Vector2i(descriptor.get("footprint", Vector2i.ONE))
	var facing := 0 if room_type in ["WEAPONS", "SHIELDS"] else (2 if room_type == "PROPULSION" else -1)
	var recipe := descriptor.get("recipe") as Resource
	var weapon := recipe.get("payload_resource") as Resource if recipe != null else null
	_add_room(
		layout,
		rooms,
		room_type,
		Rect2i(Vector2i(2, 2), footprint),
		facing,
		weapon,
		String(descriptor.get("display_name", inventory_key))
	)
	if recipe != null and not rooms.is_empty():
		var room := rooms.back() as Resource
		room.set("module_recipe", recipe)
		room.set("minimum_crew", int(recipe.get("minimum_crew")))
		room.set("optimal_crew", int(recipe.get("optimal_crew")))
		room.set("maximum_health", float(recipe.get("maximum_health")))
	layout.set("rooms", rooms)
	return layout


func generate_candidates(count: int = 3, random_seed: int = 0) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	if random_seed == 0:
		random.randomize()
	else:
		random.seed = random_seed
	var profiles := PROFILE_ORDER.duplicate()
	_shuffle(profiles, random)
	var names := CALLSIGNS.duplicate()
	_shuffle(names, random)
	var candidates: Array[Dictionary] = []
	for index: int in range(mini(count, profiles.size())):
		candidates.append(_generate_candidate(StringName(profiles[index]), String(names[index]), random, index))
	return candidates


func _generate_candidate(profile: StringName, callsign: String, random: RandomNumberGenerator, serial: int) -> Dictionary:
	var layout: Resource = BASE_LAYOUT.duplicate(true)
	layout.set("design_name", callsign)
	layout.set("lattice_version", 2)
	layout.set("build_origin", Vector2i.ZERO)
	layout.set("columns", 6)
	layout.set("rows", 8)
	var rooms: Array[Resource] = []
	layout.set("rooms", rooms)

	_add_room(layout, rooms, "COMMAND", Rect2i(2, 0, 2, 2), 0, null, "BRIDGE")
	_add_room(layout, rooms, "CREW_QUARTERS", Rect2i(2, 2, 2, 2), -1, null, "CREW QUARTERS")
	_add_room(layout, rooms, "POWER", Rect2i(2, 4, 2, 2), -1, null, "REACTOR")
	_add_room(layout, rooms, "PROPULSION", Rect2i(2, 6, 2, 2), 2, null, "AFT THRUSTER")

	var mirrored := random.randi_range(0, 1) == 1
	var primary_x := 0 if mirrored else 4
	var secondary_x := 4 if mirrored else 0
	var primary_facing := 3 if mirrored else 1
	var secondary_facing := 1 if mirrored else 3
	var weapons := _basic_weapons(layout)
	var primary_weapon: Resource = weapons[random.randi_range(0, weapons.size() - 1)] if not weapons.is_empty() else null
	var secondary_weapon: Resource = weapons[random.randi_range(0, weapons.size() - 1)] if not weapons.is_empty() else null

	var role := ""
	var flavor := ""
	var traits := PackedStringArray()
	match profile:
		&"INTERCEPTOR":
			role = "FAST ESCAPE HULL"
			flavor = "Twin drive sections and a compact gun mount. Built to leave before the alarms agree on what happened."
			traits = PackedStringArray(["TWIN AFT DRIVE", "LIGHT ARMAMENT", "LEAN FRAME"])
			_add_room(layout, rooms, "WEAPONS", Rect2i(primary_x, 2, 2, 2), primary_facing, primary_weapon, "LIGHT GUN MOUNT")
			_add_room(layout, rooms, "PROPULSION", Rect2i(secondary_x, 4, 2, 2), 2, null, "AUXILIARY THRUSTER")
		&"WARDEN":
			role = "SHIELDED PATROL HULL"
			flavor = "A modest field wraps the entire hull. It will blunt fire from any bearing, but it will not hold forever."
			traits = PackedStringArray(["FOUR-SIDE SHIELD", "BALANCED POWER BUS", "CONTROLLED FIRE ARC"])
			_add_room(layout, rooms, "WEAPONS", Rect2i(primary_x, 2, 2, 2), primary_facing, primary_weapon, "PATROL GUN MOUNT")
			_add_room(layout, rooms, "SHIELDS", Rect2i(secondary_x, 4, 2, 2), -1, null, "OMNI SHIELD")
		&"RAIDER":
			role = "BROADSIDER ESCAPE HULL"
			flavor = "Two independent mounts and no wasted support mass. It solves pursuit with volume of fire."
			traits = PackedStringArray(["DUAL WEAPON MOUNTS", "CROSS-DECK FIRE", "LEAN FRAME"])
			_add_room(layout, rooms, "WEAPONS", Rect2i(0, 2, 2, 2), 3, primary_weapon, "PORT GUN MOUNT")
			_add_room(layout, rooms, "WEAPONS", Rect2i(4, 2, 2, 2), 1, secondary_weapon, "STARBOARD GUN MOUNT")

	layout.set("rooms", rooms)
	layout.emit_changed()
	var stats: Dictionary = SHIP_BUILDER_ANALYZER.analyze(layout, Vector2i(6, 8))
	return {
		"name": callsign,
		"serial": "HX-%02d" % (serial + 1),
		"archetype": String(profile),
		"role": role,
		"flavor": flavor,
		"traits": traits,
		"layout": layout,
		"stats": stats,
	}


func _add_room(
	layout: Resource,
	rooms: Array[Resource],
	type_name: String,
	grid_rect: Rect2i,
	facing: int,
	weapon: Resource,
	display_name: String
) -> void:
	var template := _template_for(layout, type_name)
	if template == null:
		return
	var room: Resource = template.duplicate(true)
	room.set("room_id", StringName("starter_%s_%d" % [type_name.to_lower(), rooms.size()]))
	room.set("display_name", display_name)
	var rects: Array[Rect2i] = [grid_rect]
	room.set("grid_rects", rects)
	room.set("build_footprint_lattice", grid_rect.size)
	room.set("installed_piece_count", 1)
	room.set("module_recipe", null)
	room.set("module_facing_quarters", facing)
	var facings: Array[int] = []
	if facing >= 0:
		facings.append(facing)
	room.set("module_mount_facings", facings)
	if type_name == "WEAPONS":
		room.set("weapon_definition", weapon)
		var fire_modes: Array[int] = []
		fire_modes.append(0)
		room.set("weapon_fire_modes", fire_modes)
	rooms.append(room)


func _template_for(layout: Resource, type_name: String) -> Resource:
	for template: Resource in layout.get("room_types"):
		if String(template.get("type_name")) == type_name:
			return template
	return null


func _basic_weapons(layout: Resource) -> Array[Resource]:
	var result: Array[Resource] = []
	for weapon: Resource in layout.get("weapon_types"):
		if StringName(weapon.get("weapon_id")) in JAILBREAK_WEAPON_IDS:
			result.append(weapon)
	return result


func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary
