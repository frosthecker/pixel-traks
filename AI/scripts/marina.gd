extends "res://scripts/npc_enhanced.gd"
class_name MarinaEnhanced

var marina_inventory: Array = []
## Marina - Net Fisher NPC

func _ready() -> void:
	npc_name = "Marina"
	groq_character_id = "Marina"
	base_speed = 22.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_marina_personality()

func _setup_marina_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 60, "trustfulness": 55, "generosity": 65, "loyalty": 85,
			"competitiveness": 50, "aggressiveness": 35, "curiosity": 55, "extraversion": 65
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.3, "fishing": 1.6, "combat": 1.0, "social": 1.0, "crafting": 0.8}
		biodata.memory_retention = 1.0; biodata.learning_rate = 0.9
		biodata.grudge_holding = 0.5; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["net mending", "tides", "fish migrations", "storms", "the deeps", "crew", "sea songs"]
		biodata.avoided_topics = ["overfishing", "factory ships", "her lost brother", "calm seas", "landlubbers"]
		biodata.speech_patterns = ["*mends net*", "*spits over rail*", "The sea gives. The sea takes.", "Pull together!", "Salt in the blood."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		fisher_work_step()

func fisher_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_fisher_work(level)
		if worker_target_position == Vector2.INF: return true
	
	if global_position.distance_to(worker_target_position) > 12.0:
		var dir := global_position.direction_to(worker_target_position)
		last_direction = dir.round()
		move(dir, base_speed * work_efficiency)
		return false
	
	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(worker_target_position).round()
	if last_direction.is_zero_approx(): last_direction = Vector2.RIGHT
	level.npc_tool_use(worker_target_tool, worker_target_position, false, Enum.Seed.WHEAT)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_fisher_work(level: Node) -> void:
	# Marina uses nets at various spots
	var net_spots := [
		Vector2(-250, 350),
		Vector2(-200, 300),
		Vector2(-300, 400),
		Vector2(-180, 320),
	]
	var spot: Vector2 = net_spots[worker_work_phase % net_spots.size()]
	worker_target_position = spot
	worker_target_tool = Enum.Tool.FISH

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"marina_give_fish": _give_fish()
			"marina_teach_nets": _teach_netting()
			"marina_sing_shanty": _sing_shanty()
		return
	super._on_dialogic_signal(argument)

func _give_fish() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var fish := ["net_caught_fish", "school_fish", "deep_fish", "rare_catch"]
		level.give_item_to_player(fish.pick_random(), randi_range(2, 5))
	modify_relationship("player", 5.0, "gifted fish")

func _teach_netting() -> void:
	modify_relationship("player", 8.0, "taught netting")
	npc_memory.learn_fact("netting_known", true, 0.9, "player")

func _sing_shanty() -> void:
	modify_relationship("player", 3.0, "sang shanty")
	npc_memory.add_event_memory("shanty_sung", "Marina sang a sea shanty", ["player"], "", 0.2)

func get_inventory_items() -> Array[String]:
	return ["net_caught_fish", "school_fish", "deep_fish", "rare_catch", "fishing_net", "float", "anchor"]

func get_item_value(item: String) -> int:
	var values := {"net_caught_fish": 20, "school_fish": 15, "deep_fish": 50, "rare_catch": 200, "fishing_net": 100, "float": 10, "anchor": 80}
	return values.get(item, 15)

func add_inventory_item(item: String) -> void:
	if not (marina_inventory != null): marina_inventory = []
	marina_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (marina_inventory != null) and item in marina_inventory: marina_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["marina_inventory"] = marina_inventory if (marina_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	marina_inventory = data.get("marina_inventory", [])