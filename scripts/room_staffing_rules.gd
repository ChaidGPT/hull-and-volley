extends RefCounted

## Canonical ordinary-crew staffing levels. Special occupants such as the
## captain are authored separately by the room layout and are not counted here.
const OPTIMAL_CREW_BY_TYPE := {
	"COMMAND": 2,
	"BRIDGE": 2,
	"POWER": 2,
	"REACTOR": 2,
	"ENGINE": 2,
	"PROPULSION": 1,
	"THRUSTER": 1,
	"SHIELD": 2,
	"SHIELDS": 2,
	"MEDICAL": 2,
	"MEDICAL_BAY": 2,
	"WORKSHOP": 2,
	"ENGINEERING": 2,
	"HANGAR": 2,
	"SECURITY": 1,
}

const MINIMUM_CREW_BY_TYPE := {
	"COMMAND": 1,
	"BRIDGE": 1,
	"POWER": 1,
	"REACTOR": 1,
	"ENGINE": 1,
	"PROPULSION": 0,
	"THRUSTER": 0,
	"SHIELD": 1,
	"SHIELDS": 1,
	"MEDICAL": 1,
	"MEDICAL_BAY": 1,
	"WORKSHOP": 1,
	"ENGINEERING": 1,
	"HANGAR": 1,
	"SECURITY": 1,
}

const TWO_CREW_WEAPON_TERMS := [
	"HEAVY",
	"EXPLOSIVE",
	"MISSILE",
	"LONGSHOT",
	"MASSIVE",
]

const NON_WORKING_ROOM_TYPES := [
	"CREW",
	"CREW_QUARTERS",
	"MESS_HALL",
	"SUPPLY_STORAGE",
	"CARGO",
	"UNASSIGNED",
]

const EXTERNAL_WEAPON_HEALTH_PER_PIECE := 12.0
const EXTERNAL_SHIELD_HEALTH_PER_PIECE := 16.0


static func effective_requirements(room: Resource, configured_minimum: int, configured_optimal: int) -> Vector2i:
	var type_name := String(room.get("type_name")).to_upper()
	if type_name in NON_WORKING_ROOM_TYPES or is_unmanned_exterior_module(room):
		return Vector2i.ZERO
	var module_name := String(room.get("display_name")).to_upper()
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		var recipe_name := String(recipe.get("display_name")).strip_edges()
		if not recipe_name.is_empty():
			module_name = recipe_name.to_upper()
	var minimum := effective_minimum_crew(type_name, configured_minimum)
	var optimal := effective_optimal_crew(type_name, configured_optimal, minimum, module_name)
	return Vector2i(minimum, maxi(optimal, minimum))


static func is_unmanned_exterior_module(room: Resource) -> bool:
	if room == null:
		return false
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		var tags: PackedStringArray = recipe.get("tags")
		if tags.has("unmanned") and tags.has("external"):
			return true
	var type_name := String(room.get("type_name")).to_upper()
	if type_name not in ["PROPULSION", "WEAPONS", "SHIELD", "SHIELDS"]:
		return false
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.is_empty():
		return false
	for rect: Rect2i in rects:
		if rect.size != Vector2i.ONE:
			return false
	return true


static func exterior_piece_count(room: Resource) -> int:
	if room == null:
		return 1
	var rects: Array[Rect2i] = room.get("grid_rects")
	return maxi(rects.size(), maxi(int(room.get("installed_piece_count")), 1))


static func effective_maximum_health(room: Resource, configured_maximum: float) -> float:
	if not is_unmanned_exterior_module(room):
		return configured_maximum
	var per_piece := (
		EXTERNAL_SHIELD_HEALTH_PER_PIECE
		if String(room.get("type_name")).to_upper() in ["SHIELD", "SHIELDS"]
		else EXTERNAL_WEAPON_HEALTH_PER_PIECE
	)
	return minf(configured_maximum, per_piece * float(exterior_piece_count(room)))


static func effective_minimum_crew(type_name: String, configured_minimum: int) -> int:
	var key := type_name.to_upper()
	if key == "WEAPONS":
		# Weapon recipes define the crew floor used by their firing logic. Keep at
		# least one operator for legacy weapons that do not specify a minimum.
		return maxi(configured_minimum, 1)
	if MINIMUM_CREW_BY_TYPE.has(key):
		return int(MINIMUM_CREW_BY_TYPE[key])
	return maxi(configured_minimum, 0)


static func effective_optimal_crew(
	type_name: String,
	configured_optimal: int,
	minimum_crew: int = 0,
	module_name: String = ""
) -> int:
	var key := type_name.to_upper()
	if key == "WEAPONS":
		var weapon_optimal := 1
		var upper_name := module_name.to_upper()
		for term: String in TWO_CREW_WEAPON_TERMS:
			if upper_name.contains(term):
				weapon_optimal = 2
				break
		return maxi(weapon_optimal, minimum_crew)
	if OPTIMAL_CREW_BY_TYPE.has(key):
		return maxi(int(OPTIMAL_CREW_BY_TYPE[key]), minimum_crew)
	return maxi(configured_optimal, minimum_crew)
