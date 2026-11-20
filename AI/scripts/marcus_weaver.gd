extends "res://scripts/npc_enhanced.gd"
class_name MarcusWeaverEnhanced

var marcus_weaver_inventory: Array = []
## Marcus - Weaver/Tailor NPC

func _ready() -> void:
	npc_name = "Marcus"
	groq_character_id = "MarcusWeaver"
	base_speed = 20.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_marcus_weaver_personality()

func _setup_marcus_weaver_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 55, "trustfulness": 40, "generosity": 65, "loyalty": 70,
			"competitiveness": 50, "aggressiveness": 15, "curiosity": 70, "extraversion": 45
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.3, "fishing": 0.3, "combat": 0.2, "social": 1.0, "crafting": 1.6}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.0
		biodata.grudge_holding = 0.5; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["weaving", "dyes", "loom tension", "silk", "patterns", "guild secrets", "fabric quality"]
		biodata.avoided_topics = ["his expulsion", "cheap fabric", "machine weaving", "stains", "wrinkles"]
		biodata.speech_patterns = ["*checks thread tension*", "*rubs fabric between fingers*", "The warp holds the truth.", "A loose thread unravels empires.", "Color is personality woven visible."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		weaver_work_step()

func weaver_work_step() -> bool:
	# Weaver works at loom - stationary work
	var loom_pos := Vector2(50, -180)
	if global_position.distance_to(loom_pos) > 10.0:
		var dir := global_position.direction_to(loom_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	# At loom - simulate weaving
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"marcus_give_fabric": _give_fabric()
			"marcus_repair_clothes": _repair_clothes()
			"marcus_teach_weaving": _teach_weaving()
		return
	super._on_dialogic_signal(argument)

func _give_fabric() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var fabrics := ["fine_silk", "wool_cloth", "linen", "dyed_fabric", "patterned_cloth"]
		level.give_item_to_player(fabrics.pick_random(), randi_range(1, 3))
	modify_relationship("player", 5.0, "gifted fabric")

func _repair_clothes() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("repair_player_clothing"):
		level.repair_player_clothing()
	modify_relationship("player", 8.0, "repaired clothing")

func _teach_weaving() -> void:
	modify_relationship("player", 10.0, "taught weaving")
	npc_memory.learn_fact("weaving_known", true, 0.8, "player")

func get_inventory_items() -> Array[String]:
	return ["fine_silk", "wool_cloth", "linen", "dyed_fabric", "patterned_cloth", "spindle", "loom_shuttle"]

func get_item_value(item: String) -> int:
	var values := {"fine_silk": 100, "wool_cloth": 40, "linen": 30, "dyed_fabric": 60, "patterned_cloth": 80, "spindle": 50, "loom_shuttle": 60}
	return values.get(item, 30)

func add_inventory_item(item: String) -> void:
	if not (marcus_weaver_inventory != null): marcus_weaver_inventory = []
	marcus_weaver_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (marcus_weaver_inventory != null) and item in marcus_weaver_inventory: marcus_weaver_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["marcus_weaver_inventory"] = marcus_weaver_inventory if (marcus_weaver_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	marcus_weaver_inventory = data.get("marcus_weaver_inventory", [])