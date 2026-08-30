class_name DialogueSimulation
extends Node


func _ready() -> void:
	add_to_group("dialogue_simulation")


func begin_conversation(contact: Dictionary) -> Dictionary:
	return _build_view(contact, &"ROOT")


func choose_response(contact: Dictionary, response_id: StringName) -> Dictionary:
	var profile := contact.get("dialogue_profile") as Resource
	match response_id:
		&"WORK":
			return _build_view(contact, &"OFFER")
		&"ACCEPT":
			if profile != null:
				var quest := profile.get("offered_quest") as Resource
				var quests := get_tree().get_first_node_in_group("quest_simulation")
				if is_instance_valid(quests):
					quests.call(
						"accept_quest",
						quest,
						int(contact.get("id", -1)),
						String(contact.get("display_name", "CONTACT"))
					)
			return _build_view(contact, &"ACCEPTED")
		&"IDENTITY":
			return _build_view(contact, &"IDENTITY")
		&"SERVICES":
			return _build_view(contact, &"SERVICES")
		&"STATUS":
			return _build_view(contact, &"STATUS")
		&"TURN_IN":
			if profile != null:
				var quest := profile.get("offered_quest") as Resource
				var quests := get_tree().get_first_node_in_group("quest_simulation")
				if quest != null and is_instance_valid(quests):
					quests.call(
						"turn_in_quest",
						StringName(quest.get("quest_id")),
						int(contact.get("id", -1))
					)
			return _build_view(contact, &"COMPLETED")
		_:
			return _build_view(contact, &"ROOT")


func _build_view(contact: Dictionary, node_id: StringName) -> Dictionary:
	var profile := contact.get("dialogue_profile") as Resource
	var faction_id := StringName(contact.get("faction_id", &"UNAFFILIATED"))
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	var standing: StringName = &"NEUTRAL"
	var signal_color := Color(0.35, 0.9, 0.88, 1.0)
	if is_instance_valid(reputation):
		standing = StringName(reputation.call("get_standing", faction_id))
		var faction_report: Dictionary = reputation.call("get_faction_report", faction_id)
		signal_color = Color(faction_report.get("signal_color", signal_color))
	var speaker_name := String(contact.get("display_name", "UNKNOWN CONTACT"))
	var speaker_title := "OPEN CHANNEL"
	var portrait_seed := int(contact.get("id", 1))
	var portrait_color := signal_color
	var body := "Signal established. No conversational profile is registered for this contact."
	var quest: Resource
	if profile != null:
		speaker_name = _text_or_placeholder(
			String(profile.get("speaker_name")),
			String(contact.get("display_name", "UNKNOWN CONTACT"))
		)
		speaker_title = _text_or_placeholder(
			String(profile.get("speaker_title")),
			"COMMUNICATIONS OPERATOR"
		)
		portrait_seed = int(profile.get("portrait_seed")) + int(contact.get("id", 0))
		portrait_color = Color(profile.get("portrait_color")).lerp(signal_color, 0.25)
		quest = profile.get("offered_quest") as Resource
	var quest_report: Dictionary = {}
	var quests := get_tree().get_first_node_in_group("quest_simulation")
	if quest != null and is_instance_valid(quests):
		quest_report = quests.call("get_contact_quest_report", quest, int(contact.get("id", -1)))
	var quest_state := StringName(quest_report.get("state", &"AVAILABLE"))
	var choices: Array[Dictionary] = []
	if profile != null:
		match node_id:
			&"OFFER":
				body = _text_or_placeholder(
					String(profile.get("quest_offer_text")),
					"This contact has not filed contract details on the local network."
				)
				if quest != null:
					body += "\n\n%s\n%s • %s" % [
						String(quest.get("display_name")),
						String(quest.get("objective_label")),
						String(quest.get("reward_label")),
					]
				choices.append(_choice(&"ACCEPT", "REGISTER CONTRACT", &"positive"))
				choices.append(_choice(&"BACK", "DECLINE", &"quiet"))
			&"ACCEPTED":
				body = _text_or_placeholder(
					String(profile.get("quest_accepted_text")),
					"Contract accepted. Further instructions will follow over this channel."
				)
				choices.append(_choice(&"STATUS", "REVIEW CONTRACT", &"normal"))
			&"IDENTITY":
				body = _text_or_placeholder(
					String(profile.get("identity_text")),
					"No public identity packet is attached to this transmission."
				)
				choices.append(_choice(&"BACK", "RETURN", &"quiet"))
			&"SERVICES":
				body = _text_or_placeholder(
					String(profile.get("remote_services_text")),
					"Remote service information is unavailable. Physical services require docking."
				)
				choices.append(_choice(&"BACK", "RETURN", &"quiet"))
			&"STATUS":
				body = _quest_status_text(profile, quest_report)
				choices.append(_choice(&"BACK", "RETURN", &"quiet"))
			&"COMPLETED":
				body = _text_or_placeholder(
					String(profile.get("quest_complete_text")),
					"Contract completion acknowledged."
				)
				choices.append(_choice(&"BACK", "RETURN", &"quiet"))
			_:
				body = _greeting_for(profile, standing)
				if standing not in [&"HOSTILE", &"HUNTED"]:
					if not quest_report.is_empty():
						match quest_state:
							&"AVAILABLE":
								if standing not in [&"SUSPICIOUS"]:
									choices.append(_choice(&"WORK", "AVAILABLE WORK?", &"positive"))
							&"ACTIVE":
								body += "\n\n" + String(profile.get("quest_active_text"))
								choices.append(_choice(&"STATUS", "CONTRACT STATUS", &"normal"))
							&"READY":
								body += "\n\n" + String(profile.get("quest_ready_text"))
								choices.append(_choice(&"TURN_IN", "TRANSMIT COMPLETION", &"positive"))
							&"COMPLETED":
								body += "\n\n" + String(profile.get("quest_complete_text"))
					choices.append(_choice(&"IDENTITY", "IDENTIFY YOURSELF", &"normal"))
					if bool(contact.get("stationary", false)) or not PackedStringArray(contact.get("station_service_tags", PackedStringArray())).is_empty():
						choices.append(_choice(&"SERVICES", "SERVICE LISTING", &"normal"))
	return {
		"speaker_name": speaker_name,
		"speaker_title": speaker_title,
		"portrait_seed": portrait_seed,
		"portrait_color": portrait_color,
		"standing": standing,
		"body": body,
		"choices": choices,
	}


func _greeting_for(profile: Resource, standing: StringName) -> String:
	var greeting := ""
	match standing:
		&"ALLIED":
			greeting = String(profile.get("allied_greeting"))
		&"FAVORED":
			greeting = String(profile.get("friendly_greeting"))
		&"SUSPICIOUS":
			greeting = String(profile.get("suspicious_greeting"))
		&"HOSTILE", &"HUNTED":
			greeting = String(profile.get("hostile_greeting"))
		_:
			greeting = String(profile.get("neutral_greeting"))
	return _text_or_placeholder(
		greeting,
		"Channel established. This contact has no recorded greeting."
	)


func _quest_status_text(profile: Resource, report: Dictionary) -> String:
	if report.is_empty():
		return String(profile.get("quest_active_text"))
	return "%s\n\n%s\nPROGRESS  %d / %d" % [
		String(report.get("display_name", "CONTRACT")),
		String(report.get("objective_label", "OBJECTIVE")),
		int(report.get("progress", 0)),
		int(report.get("objective_count", 1)),
	]


func _choice(response_id: StringName, label: String, tone: StringName) -> Dictionary:
	return {"id": response_id, "label": label, "tone": tone}


func _text_or_placeholder(value: String, placeholder: String) -> String:
	return placeholder if value.strip_edges().is_empty() else value
