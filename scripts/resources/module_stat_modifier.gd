class_name ModuleStatModifier
extends Resource

enum Operation {
	ADD,
	MULTIPLY,
	OVERRIDE,
}

@export var stat_id: StringName
@export var operation := Operation.ADD
@export var value := 0.0
@export var scale_with_footprint_cells := false


func apply_to(base_value: float, footprint_cell_count: int = 1) -> float:
	var effective_value := value * maxf(float(footprint_cell_count), 1.0) if scale_with_footprint_cells else value
	match operation:
		Operation.MULTIPLY:
			return base_value * effective_value
		Operation.OVERRIDE:
			return effective_value
		_:
			return base_value + effective_value
