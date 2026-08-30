@tool
class_name DialogueProfileDefinition
extends Resource

@export_category("Speaker")
@export var profile_id: StringName
@export var speaker_name := "UNKNOWN OPERATOR"
@export var speaker_title := "OPEN CHANNEL"
@export var portrait_seed := 1
@export var portrait_color := Color(0.35, 0.9, 0.88, 1.0)

@export_category("Reputation Greetings")
@export_multiline var allied_greeting := "Your transponder has priority on this channel."
@export_multiline var friendly_greeting := "Good to see a trusted signal out here."
@export_multiline var neutral_greeting := "Channel established. State your business."
@export_multiline var suspicious_greeting := "Keep this transmission short. Your signal has been flagged."
@export_multiline var hostile_greeting := "This channel is being recorded. No services are authorized."

@export_category("Conversation")
@export_multiline var identity_text := "Independent traffic operator. Our manifest is registered on the local net."
@export_multiline var remote_services_text := "Service listings can be transmitted remotely. Physical trade, repair, refit, and transfer require a secured docking hardline."

@export_category("Contract")
@export var offered_quest: Resource
@export_multiline var quest_offer_text := "We have a contract open if your ship has room for the work."
@export_multiline var quest_accepted_text := "Contract registered to your transponder. Return on this channel when the work is complete."
@export_multiline var quest_active_text := "Your contract remains open. The board is tracking your progress."
@export_multiline var quest_ready_text := "The contract telemetry is green. Transmit your completion packet."
@export_multiline var quest_complete_text := "Payment and standing adjustment transmitted. Clean work."

