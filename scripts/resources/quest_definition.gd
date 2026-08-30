@tool
class_name QuestDefinition
extends Resource

@export_category("Identity")
@export var quest_id: StringName
@export var display_name := "UNREGISTERED CONTRACT"
@export_multiline var summary := ""

@export_category("Objective")
## Event reported by world systems, such as COLLECT_GRID or DESTROY_CONTACT.
@export var objective_event: StringName = &"COLLECT_GRID"
## Optional event target. Empty accepts any target carried by the event.
@export var objective_target: StringName
@export_range(1, 99, 1) var objective_count := 1
@export var objective_label := "RECOVER LOOSE GRID"
## Optional world pickup created when this contract is accepted.
@export var spawned_pickup_room_type: StringName
@export_range(80.0, 1200.0, 10.0) var spawned_pickup_distance := 260.0

@export_category("Reward")
@export var reward_faction_id: StringName
@export_range(-100.0, 100.0, 1.0) var reputation_reward := 8.0
@export var reward_label := "FACTION FAVOR"
