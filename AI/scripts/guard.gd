extends "res://scripts/npc_enhanced.gd"
class_name GuardEnhanced

var vex_inventory: Array = []
## Captain Vex - Island Guard NPC

func _ready() -> void:
	npc_name = "Captain Vex"
	groq_character_id = "Vex"
	base_speed = 26.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_guard_personality()

func _setup_guard_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 40,
			"trustfulness": 35,
			"generosity": 45,
			"loyalty": 95,
			"competitiveness": 50,
			"aggressiveness": 55,
			"curiosity": 50,
			"extraversion": 35,
		}
		biodata.skill_affinities = {
			"farming": 0.5,
			"mining": 0.6,
			"fishing": 0.5,
			"combat": 1.5,
			"social": 0.6,
			"crafting": 0.8,
		}
		biodata.memory_retention = 1.0
		biodata.learning_rate = 0.9
		biodata.grudge_holding = 0.8
		biodata.forgiveness = 0.3
		biodata.preferred_topics = ["defense", "patrols", "combat training", "island security", "threats", "weapon maintenance", "discipline"]
		biodata.avoided_topics = ["his past unit", "why he left the mainland", "politics", "peace negotiations"]
		biodata.speech_patterns = ["*adjusts gauntlet*", "*scans horizon*", "Stand easy.", "Eyes up.", "The perimeter is secure."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if behavior_state == "work" and not dialogue_running:
		patrol_step()

func patrol_step() -> bool:
	var patrol_points := [
		Vector2(0, -200),
		Vector2(-100, -250),
		Vector2(-150, 0),
		Vector2(0, 50),
		Vector2(150, 0),
		Vector2(100, -250),
	]
	
	var current_target := patrol_points[worker_work_phase % patrol_points.size()]
	
	if global_position.distance_to(current_target) > 15.0:
		var dir := global_position.direction_to(current_target)
		last_direction = dir.round()
		move(dir, base_speed * work_efficiency)
		return false
	
	# Reached patrol point - pause briefly
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"vex_give_weapon":
				_give_weapon()
			"vex_train_player":
				_train_player()
			"vex_warning":
				_issue_warning()
		return
	super._on_dialogic_signal(argument)

func _give_weapon() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var weapons := ["iron_sword", "guard_spear", "crossbow", "shield"]
		level.give_item_to_player(weapons.pick_random(), 1)
	modify_relationship("player", 10.0, "gifted weapon")

func _train_player() -> void:
	# Increase player combat skill temporarily
	modify_relationship("player", 5.0, "training")
	npc_memory.learn_fact("combat_trained_by_vex", true, 0.8, "player")

func _issue_warning() -> void:
	modify_relationship("player", -3.0, "warning issued")

func get_inventory_items() -> Array[String]:
	return ["iron_sword", "guard_spear", "shield", "crossbow", "bolts", "armor_repair_kit"]

func get_item_value(item: String) -> int:
	var values := {
		"iron_sword": 200,
		"guard_spear": 250,
		"shield": 180,
		"crossbow": 300,
		"bolts": 5,
		"armor_repair_kit": 50,
	}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (vex_inventory != null):
		vex_inventory = []
	vex_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (vex_inventory != null) and item in vex_inventory:
		vex_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["vex_inventory"] = vex_inventory if (vex_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	vex_inventory = data.get("vex_inventory", [])