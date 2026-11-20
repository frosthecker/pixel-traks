extends "res://scripts/npc_enhanced.gd"
class_name ElaraEnhanced

var elara_inventory: Array = []
## Elara - Organic Farmer NPC

func _ready() -> void:
	npc_name = "Elara"
	groq_character_id = "Elara"
	base_speed = 22.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_elara_personality()

func _setup_elara_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 75, "trustfulness": 65, "generosity": 80, "loyalty": 70,
			"competitiveness": 20, "aggressiveness": 10, "curiosity": 70, "extraversion": 60
		}
		biodata.skill_affinities = {"farming": 1.5, "mining": 0.4, "fishing": 0.5, "combat": 0.3, "social": 1.1, "crafting": 0.8}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.8
		biodata.preferred_topics = ["composting", "companion planting", "heirloom seeds", "soil health", "nature spirits", "sustainable living"]
		biodata.avoided_topics = ["chemical fertilizers", "monoculture", "factory farming", "greed", "shortcuts"]
		biodata.speech_patterns = ["*brushes dirt from knees*", "*inhales soil scent*", "The earth provides.", "Listen to the roots.", "Every seed has a song."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		organic_farmer_work_step()

func organic_farmer_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_organic_work(level)
		if worker_target_position == Vector2.INF: return true
	
	if global_position.distance_to(worker_target_position) > 12.0:
		var dir := global_position.direction_to(worker_target_position)
		last_direction = dir.round()
		move(dir, base_speed * work_efficiency)
		return false
	
	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(worker_target_position).round()
	if last_direction.is_zero_approx(): last_direction = Vector2.RIGHT
	level.npc_tool_use(worker_target_tool, worker_target_position, false, worker_seed)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_organic_work(level: Node) -> void:
	# Elara focuses on composting, companion planting, natural methods
	if worker_work_phase % 3 == 0:
		worker_target_position = _find_compost_spot(level)
		worker_target_tool = Tool.HOE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Tool.SEED
	elif worker_work_phase % 3 == 1:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Tool.SEED
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_water_spot(level)
			worker_target_tool = Tool.WATER
	else:
		worker_target_position = _find_water_spot(level)
		worker_target_tool = Tool.WATER
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Tool.SEED

func _find_compost_spot(level: Node) -> Vector2:
	# Look for dark dirt to enrich
	var dark_dirt: TileMapLayer = level.get_node_or_null("Layers/DarkDirtLayer")
	if dark_dirt == null: return Vector2.INF
	var cells := dark_dirt.get_used_cells()
	if cells.is_empty(): return Vector2.INF
	var best := Vector2.INF; var best_d := INF
	for cell in cells:
		var pos := dark_dirt.to_global(dark_dirt.map_to_local(cell))
		var d := global_position.distance_squared_to(pos)
		if d < best_d: best_d = d; best = pos
	return best

func _find_water_spot(level: Node) -> Vector2:
	var dark_dirt: TileMapLayer = level.get_node_or_null("Layers/DarkDirtLayer")
	if dark_dirt == null: return Vector2.INF
	var cells := dark_dirt.get_used_cells()
	if cells.is_empty(): return Vector2.INF
	var best := Vector2.INF; var best_d := INF
	for cell in cells:
		var pos := dark_dirt.to_global(dark_dirt.map_to_local(cell))
		var d := global_position.distance_squared_to(pos)
		if d < best_d: best_d = d; best = pos
	return best

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"elara_give_compost": _give_compost()
			"elara_teach_companion": _teach_companion_planting()
			"elara_bless_seeds": _bless_seeds()
		return
	super._on_dialogic_signal(argument)

func _give_compost() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("compost", randi_range(3, 8))
	modify_relationship("player", 5.0, "shared compost")

func _teach_companion_planting() -> void:
	modify_relationship("player", 8.0, "taught companion planting")
	npc_memory.learn_fact("companion_planting_known", true, 0.9, "player")

func _bless_seeds() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("blessed_seeds", 1)
	modify_relationship("player", 10.0, "blessed seeds")

func get_inventory_items() -> Array[String]:
	return ["compost", "heirloom_seeds", "blessed_seeds", "herbal_tea", "wildflower_honey"]

func get_item_value(item: String) -> int:
	var values := {"compost": 15, "heirloom_seeds": 50, "blessed_seeds": 100, "herbal_tea": 20, "wildflower_honey": 40}
	return values.get(item, 15)

func add_inventory_item(item: String) -> void:
	if not (elara_inventory != null): elara_inventory = []
	elara_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (elara_inventory != null) and item in elara_inventory: elara_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["elara_inventory"] = elara_inventory if (elara_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	elara_inventory = data.get("elara_inventory", [])