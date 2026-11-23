extends "res://scripts/npc_enhanced.gd"
class_name BrigaEnhanced

var briga_inventory: Array = []
## Sergeant Briga - Guard Sergeant NPC

func _ready() -> void:
	npc_name = "Sergeant Briga"
	groq_character_id = "Briga"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_briga_personality()

func _setup_briga_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 45, "trustfulness": 50, "generosity": 55, "loyalty": 90,
			"competitiveness": 50, "aggressiveness": 50, "curiosity": 55, "extraversion": 45
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.5, "fishing": 0.4, "combat": 1.4, "social": 0.9, "crafting": 0.8}
		biodata.memory_retention = 1.0; biodata.learning_rate = 0.9
		biodata.grudge_holding = 0.5; biodata.forgiveness = 0.5
		biodata.preferred_topics = ["drills", "discipline", "gear maintenance", "tactics", "the old wars", "recruits", "duty"]
		biodata.avoided_topics = ["her discharge", "the massacre at Hollow Pass", "politics", "retirement", "weakness"]
		biodata.speech_patterns = ["*adjusts pauldron*", "*inspects blade*", "Formation holds.", "Eyes front.", "We drill for the day we pray never comes."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		guard_work_step()

func guard_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	# Patrol between guard posts
	var posts := [Vector2(-50, -220), Vector2(50, -220), Vector2(0, -200)]
	var target: Vector2 = posts[worker_work_phase % posts.size()]
	
	if global_position.distance_to(target) > 15.0:
		var dir := global_position.direction_to(target)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	# At post - drill or inspect
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"briga_train": _train_player()
			"briga_inspect": _inspect_gear()
			"briga_assign": _assign_patrol()
		return
	super._on_dialogic_signal(argument)

func _train_player() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("train_player_combat"):
		level.train_player_combat()
	modify_relationship("player", 8.0, "trained player")

func _inspect_gear() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("repair_player_gear"):
		level.repair_player_gear()
	modify_relationship("player", 5.0, "inspected gear")

func _assign_patrol() -> void:
	modify_relationship("player", 3.0, "assigned patrol")
	npc_memory.add_event_memory("patrol_assigned", "Briga assigned patrol duty", ["player"], "", 0.1)

func get_inventory_items() -> Array[String]:
	return ["guard_spear", "shield", "crossbow", "bolts", "armor_polish", "drill_manual", "whistle"]

func get_item_value(item: String) -> int:
	var values := {"guard_spear": 250, "shield": 180, "crossbow": 300, "bolts": 5, "armor_polish": 20, "drill_manual": 100, "whistle": 15}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (briga_inventory != null): briga_inventory = []
	briga_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (briga_inventory != null) and item in briga_inventory: briga_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["briga_inventory"] = briga_inventory if (briga_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	briga_inventory = data.get("briga_inventory", [])