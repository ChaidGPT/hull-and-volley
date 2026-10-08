class_name QuarterConnectorResolver
extends RefCounted

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")


## Returns connector artwork and clockwise quarter-turns for every occupied
## neighbor of one QG. Source art conventions are single=left, straight=LR,
## and corner=LU. Three/four-way junctions safely compose single arms.
static func visual_plan(piece_rect: Rect2i, hull_cells: Dictionary, fallback_quarter: int) -> Array[Dictionary]:
	var quarters: Array[int] = []
	for quarter: int in range(4):
		var neighbor := piece_rect.position + GRID_GEOMETRY.quarter_direction(quarter)
		if hull_cells.has(neighbor):
			quarters.append(quarter)
	if quarters.is_empty():
		quarters.append(posmod(fallback_quarter, 4))
	if quarters.size() == 1:
		return [{"kind": &"single", "turns": posmod(quarters[0] - 3, 4)}]
	if quarters.size() == 2:
		if posmod(quarters[0] - quarters[1], 4) == 2:
			var vertical := quarters.has(0) and quarters.has(2)
			return [{"kind": &"straight", "turns": 1 if vertical else 0}]
		# The corner source joins left (3) to up (0). Rotate that pair until it
		# matches the two occupied neighbor quarters.
		for turns: int in range(4):
			if quarters.has(posmod(3 + turns, 4)) and quarters.has(posmod(turns, 4)):
				return [{"kind": &"corner", "turns": turns}]
	var result: Array[Dictionary] = []
	for quarter: int in quarters:
		result.append({"kind": &"single", "turns": posmod(quarter - 3, 4)})
	return result
