extends "res://scripts/npc_enhanced.gd"
class_name CaptainReefEnhanced

var reef_inventory: Array = []
## Captain Reef - Harbor Master NPC

func _ready() -> void:
	npc_name = "Captain Reef"
	groq_character_id = "CaptainReef"
	base_speed = 16.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_captain_reef_personality()

func _setup_captain_reef_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 60, "trustfulness": 50, "generosity": 65, "loyalty": 80,
			"competitiveness": 40, "aggressiveness": 30, "curiosity": 60, "extraversion": 75
		}
		biodata.skill_affinities = {"farming": 0.3, "mining": 0.4, "fishing": 0.8, "combat": 1.1, "social": 1.2, "crafting": 0.7}
		biodata.memory_retention = 1.0; biodata.learning_rate = 0.8
		biodata.grudge_holding = 0.5; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["harbor", "wrecks", "tides", "ships", "whales", "the parrot", "naval history"]
		biodata.avoided_topics = ["his leg", "the mutiny", "his wife ashore", "retirement", "peace"]
		biodata.speech_patterns = ["*leans on whalebone leg*", "*parrot squawks*", "Harbor's closed.", "Rocks don't move.", "She'll hold, or she won't."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		harbor_master_work_step()

func harbor_master_work_step() -> bool:
	# Patrols harbor area
	var posts := [Vector2(-150, 400), Vector2(-100, 350), Vector2(-200, 450), Vector2(-50, 380)]
	var target := posts[worker_work_phase % posts.size()]
	
	if global_position.distance_to(target) > 15.0:
		var dir := global_position.direction_to(target)
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
			"reef_clear_dock": _clear_dock()
			"reef_warn": _warn_captain()
			"reef_tale": _tell_tale()
		return
	super._on_dialogic_signal(argument)

func _clear_dock() -> void:
	modify_relationship("player", 5.0, "cleared dock")
	npc_memory.add_event_memory("dock_cleared", "Reef cleared dock for player", ["player"], "", 0.2)

func _warn_captain() -> void:
	var warnings := ["Shallows shifted.", "Current's wrong today.", "Something big in the deeps."]
	modify_relationship("player", 3.0, "warned")
	npc_memory.add_event_memory("warning", "Reef warned: " + warnings.pick_random(), ["player"], "", -0.1)

func _tell_tale() -> void:
	var tales := ["The white whale that sank three ships.", "The island that wasn't there yesterday.", "The crew that mutinied against the wind."]
	modify_relationship("player", 5.0, "told tale")
	npc_memory.add_event_memory("tale_told", "Reef told: " + tales.pick_random(), ["player"], "", 0.3)

func get_inventory_items() -> Array[String]:
	return ["harbor_chart", "whalebone_leg", "parrot", "spyglass", "logbook", "anchor", "signal_flags"]

func get_item_value(item: String) -> int:
	var values := {"harbor_chart": 200, "whalebone_leg": 500, "parrot": 300, "spyglass": 300, "logbook": 400, "anchor": 150, "signal_flags": 80}
	return values.get(item, 150)

func add_inventory_item(item: String) -> void:
	if not (reef_inventory != null): reef_inventory = []
	reef_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (reef_inventory != null) and item in reef_inventory: reef_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["reef_inventory"] = reef_inventory if (reef_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	reef_inventory = data.get("reef_inventory", [])