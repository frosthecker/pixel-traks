extends "res://scripts/npc_enhanced.gd"
class_name MaraEnhanced

var mara_inventory: Array = []
## Mara - Fisher's Daughter NPC

func _ready() -> void:
	npc_name = "Mara"
	groq_character_id = "Mara"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_mara_personality()

func _setup_mara_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 65, "trustfulness": 60, "generosity": 65, "loyalty": 80,
			"competitiveness": 40, "aggressiveness": 20, "curiosity": 75, "extraversion": 50
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.3, "fishing": 1.3, "combat": 0.7, "social": 1.1, "crafting": 0.9}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.2
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.7
		biodata.preferred_topics = ["sailing", "horizons", "her own boat", "poetry", "Orin", "the deeps", "storms"]
		biodata.avoided_topics = ["settling down", "marriage", "the lighthouse", "her mother", "fear"]
		biodata.speech_patterns = ["*mends sail*", "*gazes at horizon*", "The wind knows.", "Land is just paused sea.", "One day. My boat."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		apprentice_fisher_work_step()

func apprentice_fisher_work_step() -> bool:
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
	# Mara learns from Orin and Marina
	var spots := [
		Vector2(-200, 300),  # Orin's spot
		Vector2(-250, 350),  # Marina's spot
		Vector2(-150, 250),
	]
	var spot: Vector2 = spots[worker_work_phase % spots.size()]
	worker_target_position = spot
	worker_target_tool = Enum.Tool.FISH

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"mara_give_poem": _give_poem()
			"mara_teach_knot": _teach_knot()
			"mara_share_dream": _share_dream()
		return
	super._on_dialogic_signal(argument)

func _give_poem() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("mara_poem", 1)
	modify_relationship("player", 5.0, "shared poem")

func _teach_knot() -> void:
	modify_relationship("player", 8.0, "taught knot")
	npc_memory.learn_fact("sailor_knot_known", true, 0.9, "player")

func _share_dream() -> void:
	var dreams := ["A ship made of light.", "The ocean as a desert.", "Flying over waves."]
	modify_relationship("player", 3.0, "shared dream")
	npc_memory.add_event_memory("dream_shared", "Mara dreamed: " + dreams.pick_random(), ["player"], "", 0.2)

func get_inventory_items() -> Array[String]:
	return ["mara_poem", "sailcloth", "fishing_line", "sea_glass", "driftwood_carving", "compass_rose"]

func get_item_value(item: String) -> int:
	var values := {"mara_poem": 50, "sailcloth": 40, "fishing_line": 20, "sea_glass": 30, "driftwood_carving": 80, "compass_rose": 100}
	return values.get(item, 25)

func add_inventory_item(item: String) -> void:
	if not (mara_inventory != null): mara_inventory = []
	mara_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (mara_inventory != null) and item in mara_inventory: mara_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["mara_inventory"] = mara_inventory if (mara_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	mara_inventory = data.get("mara_inventory", [])