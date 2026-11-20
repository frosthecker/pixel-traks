extends "res://scripts/npc_enhanced.gd"
class_name ElinEnhanced

var elin_inventory: Array = []
## Scribe Elin - Record Keeper NPC

func _ready() -> void:
	npc_name = "Scribe Elin"
	groq_character_id = "Elin"
	base_speed = 16.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_elin_personality()

func _setup_elin_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 60, "trustfulness": 55, "generosity": 50, "loyalty": 85,
			"competitiveness": 25, "aggressiveness": 5, "curiosity": 80, "extraversion": 35
		}
		biodata.skill_affinities = {"farming": 0.5, "mining": 0.4, "fishing": 0.4, "combat": 0.2, "social": 1.1, "crafting": 1.0}
		biodata.memory_retention = 1.5; biodata.learning_rate = 1.0
		biodata.grudge_holding = 0.4; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["records", "genealogy", "land deeds", "promises", "cipher", "the island's true history", "secrets"]
		biodata.avoided_topics = ["her cipher key", "the missing ledger", "who she works for", "burning records", "her own history"]
		biodata.speech_patterns = ["*dips quill*", "*checks ledger*", "It is written.", "Memory fails. Ink endures.", "Every name has a story."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		scribe_work_step()

func scribe_work_step() -> bool:
	# Works at records office
	var office_pos := Vector2(-100, 0)
	if global_position.distance_to(office_pos) > 10.0:
		var dir := global_position.direction_to(office_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"elin_lookup": _lookup_record()
			"elin_register": _register_promise()
			"elin_decipher": _decipher_text()
		return
	super._on_dialogic_signal(argument)

func _lookup_record() -> void:
	var records := ["Land grant: North field to Miller family.", "Marriage: John and Mira, Year 12.", "Birth: Pip, Year 5.", "Debt: Viktor owes Marcus 500g."]
	modify_relationship("player", 3.0, "looked up record")
	npc_memory.add_event_memory("record_found", "Elin found: " + records.pick_random(), ["player"], "", 0.2)

func _register_promise() -> void:
	modify_relationship("player", 5.0, "registered promise")
	npc_memory.make_promise("player", "Recorded in the ledger", 7)

func _decipher_text() -> void:
	modify_relationship("player", 8.0, "deciphered text")
	npc_memory.learn_fact("cipher_partial_known", true, 0.6, "player")

func get_inventory_items() -> Array[String]:
	return ["ledger", "quill_set", "cipher_key_fragment", "sealing_wax", "old_map", "family_tree"]

func get_item_value(item: String) -> int:
	var values := {"ledger": 200, "quill_set": 50, "cipher_key_fragment": 500, "sealing_wax": 20, "old_map": 300, "family_tree": 400}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (elin_inventory != null): elin_inventory = []
	elin_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (elin_inventory != null) and item in elin_inventory: elin_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["elin_inventory"] = elin_inventory if (elin_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	elin_inventory = data.get("elin_inventory", [])