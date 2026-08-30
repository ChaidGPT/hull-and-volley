class_name ModuleFootprintDefinition
extends Resource

@export_category("Identity")
@export var footprint_id: StringName = &"one_cell"
@export var display_name := "ONE CELL"

@export_category("Grid Shape")
@export var cells: Array[Vector2i] = [Vector2i.ZERO]
@export var allow_quarter_turn_rotation := true
@export var allow_mirroring := false

@export_category("Hull Exposure")
@export var required_edges: Array[Resource] = []
@export_range(0, 32, 1) var minimum_open_edges := 0
@export var require_forward_exposure := false
@export_range(1, 32, 1) var minimum_forward_exposed_cells := 1


func transformed_cells(rotation_quarters: int, mirrored: bool = false) -> Array[Vector2i]:
	var transformed: Array[Vector2i] = []
	var turns := posmod(rotation_quarters, 4) if allow_quarter_turn_rotation else 0
	for source_cell: Vector2i in cells:
		var cell := source_cell
		if mirrored and allow_mirroring:
			cell.x = -cell.x
		for turn_index: int in range(turns):
			cell = Vector2i(-cell.y, cell.x)
		transformed.append(cell)
	return _normalize_cells(transformed)


func transformed_edge_requirements(rotation_quarters: int, mirrored: bool = false) -> Array[Dictionary]:
	var transformed: Array[Dictionary] = []
	var turns := posmod(rotation_quarters, 4) if allow_quarter_turn_rotation else 0
	var raw_cells: Array[Vector2i] = []
	for source_cell: Vector2i in cells:
		raw_cells.append(_transform_cell(source_cell, turns, mirrored))
	var normalization_offset := Vector2i.ZERO
	if not raw_cells.is_empty():
		normalization_offset = raw_cells[0]
		for raw_cell: Vector2i in raw_cells:
			normalization_offset.x = mini(normalization_offset.x, raw_cell.x)
			normalization_offset.y = mini(normalization_offset.y, raw_cell.y)
	for requirement: Resource in required_edges:
		var cell: Vector2i = _transform_cell(requirement.get("cell_offset"), turns, mirrored)
		var direction: Vector2i = requirement.call("direction_vector")
		if mirrored and allow_mirroring:
			direction.x = -direction.x
		for turn_index: int in range(turns):
			direction = Vector2i(-direction.y, direction.x)
		transformed.append({
			"cell": cell - normalization_offset,
			"direction": direction,
			"must_face_open_space": requirement.get("must_face_open_space"),
		})
	return transformed


func _transform_cell(source_cell: Vector2i, turns: int, mirrored: bool) -> Vector2i:
	var cell := source_cell
	if mirrored and allow_mirroring:
		cell.x = -cell.x
	for turn_index: int in range(turns):
		cell = Vector2i(-cell.y, cell.x)
	return cell


func cell_count() -> int:
	return cells.size()


func _normalize_cells(source_cells: Array[Vector2i]) -> Array[Vector2i]:
	if source_cells.is_empty():
		return []
	var minimum := source_cells[0]
	for cell: Vector2i in source_cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	var normalized: Array[Vector2i] = []
	for cell: Vector2i in source_cells:
		normalized.append(cell - minimum)
	normalized.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return normalized
