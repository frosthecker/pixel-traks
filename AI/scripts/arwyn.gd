extends "res://scripts/npc_enhanced.gd"
class_name ArwynEnhanced

var arwyn_inventory: Array = []
## Professor Arwyn - Scholar NPC

func _ready() -> void:
	npc_name = "Professor Arwyn"
	groq_character_id = "Arwyn"
	base_speed = 18.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_arwyn_personality()

func _setup_arwyn_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 55, "trustfulness": 50, "generosity": 60, "loyalty": 70,
			"competitiveness": 40, "aggressiveness": 10, "curiosity": 95, "extraversion": 40
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.6, "fishing": 0.4, "combat": 0.3, "social": 0.9, "crafting": 1.3}
		biodata.memory_retention = 1.3; biodata.learning_rate = 1.4
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.7
		biodata.preferred_topics = ["anomalies", "magnetism", "luminescence", "ancient tech", "forbidden science", "the purge", "hypotheses"]
		biodata.avoided_topics = ["her colleagues", "the Inquisition", "peer review", "funding", "practical applications"]
		biodata.speech_patterns = ["*adjusts goggles*", "*mumbles equations*", "The data suggests...", "Fascinating anomaly.", "Control group compromised."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		scholar_work_step()

func scholar_work_step() -> bool:
	# Works at lab/lighthouse
	var lab_pos := Vector2(-120, 50)
	if global_position.distance_to(lab_pos) > 10.0:
		var dir := global_position.direction_to(lab_pos)
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
			"arwyn_analyze": _analyze_item()
			"arwyn_share_theory": _share_theory()
			"arwyn_give_gadget": _give_gadget()
		return
	super._on_dialogic_signal(argument)

func _analyze_item() -> void:
	modify_relationship("player", 5.0, "analyzed item")
	npc_memory.learn_fact("item_analyzed_by_arwyn", true, 0.8, "player")

func _share_theory() -> void:
	var theories := ["The island is a machine.", "The stones are batteries.", "The tides follow a hidden pattern."]
	modify_relationship("player", 8.0, "shared theory")
	npc_memory.add_event_memory("theory_shared", "Arwyn theorized: " + theories.pick_random(), ["player"], "", 0.3)

func _give_gadget() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var gadgets := ["magnetic_compass", "luminescent_vial", "resonance_detector", "ancient_key"]
		level.give_item_to_player(gadgets.pick_random(), 1)
	modify_relationship("player", 10.0, "gave gadget")

func get_inventory_items() -> Array[String]:
	return ["magnetic_compass", "luminescent_vial", "resonance_detector", "ancient_key", "forbidden_text", "data_crystal"]

func get_item_value(item: String) -> int:
	var values := {"magnetic_compass": 200, "luminescent_vial": 300, "resonance_detector": 400, "ancient_key": 500, "forbidden_text": 600, "data_crystal": 800}
	return values.get(item, 300)

func add_inventory_item(item: String) -> void:
	if not (arwyn_inventory != null): arwyn_inventory = []
	arwyn_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (arwyn_inventory != null) and item in arwyn_inventory: arwyn_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["arwyn_inventory"] = arwyn_inventory if (arwyn_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	arwyn_inventory = data.get("arwyn_inventory", [])