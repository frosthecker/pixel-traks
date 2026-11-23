extends "res://scripts/npc_enhanced.gd"
class_name TomasEnhanced

var tomas_inventory: Array = []
## Tomas - Veteran Farmer NPC

func _ready() -> void:
	npc_name = "Tomas"
	groq_character_id = "Tomas"
	base_speed = 18.0
	work_efficiency = 1.1
	
	super._ready()
	_setup_tomas_personality()

func _setup_tomas_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 45, "trustfulness": 50, "generosity": 60, "loyalty": 85,
			"competitiveness": 30, "aggressiveness": 25, "curiosity": 40, "extraversion": 35
		}
		biodata.skill_affinities = {"farming": 1.6, "mining": 0.5, "fishing": 0.6, "combat": 0.7, "social": 0.7, "crafting": 0.9}
		biodata.memory_retention = 1.2; biodata.learning_rate = 0.6
		biodata.grudge_holding = 0.6; biodata.forgiveness = 0.5
		biodata.preferred_topics = ["old farming ways", "weather signs", "seed saving", "tool maintenance", "the hard years", "patience"]
		biodata.avoided_topics = ["newfangled gadgets", "easy money", "laziness", "disrespecting the land", "his late wife"]
		biodata.speech_patterns = ["*leans on hoe*", "*spits*", "Rain's coming by noon.", "Don't plant by the calendar.", "I've buried better men than drought."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		veteran_farmer_work_step()

func veteran_farmer_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_veteran_work(level)
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

func _prepare_veteran_work(level: Node) -> void:
	# Tomas works his fields methodically - hoe, seed, water, repeat
	var tools := [Enum.Tool.HOE, Enum.Tool.SEED, Enum.Tool.WATER]
	var tool: Enum.Tool = tools[worker_work_phase % tools.size()]
	
	match tool:
		Enum.Tool.HOE: worker_target_position = _find_hoeing_spot(level)
		Enum.Tool.SEED: worker_target_position = _find_planting_spot(level)
		Enum.Tool.WATER: worker_target_position = _find_water_spot(level)
	
	worker_target_tool = tool
	if worker_target_position == Vector2.INF:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Enum.Tool.SEED

func _find_hoeing_spot(level: Node) -> Vector2:
	var grass: TileMapLayer = level.get_node_or_null("Layers/GrassLayer")
	if grass == null: return Vector2.INF
	var cells := grass.get_used_cells()
	if cells.is_empty(): return Vector2.INF
	var best := Vector2.INF; var best_d := INF
	for cell in cells:
		var cell_data = grass.get_cell_tile_data(cell)
		if cell_data and cell_data.get_custom_data("farmable"):
			var pos := grass.to_global(grass.map_to_local(cell))
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
			"tomas_give_heirloom": _give_heirloom_seed()
			"tomas_predict_weather": _predict_weather()
			"tomas_teach_patience": _teach_patience()
		return
	super._on_dialogic_signal(argument)

func _give_heirloom_seed() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var seeds := ["ancient_wheat", "heritage_potato", "old_corn"]
		level.give_item_to_player(seeds.pick_random(), 1)
	modify_relationship("player", 10.0, "gifted heirloom seed")

func _predict_weather() -> void:
	var predictions := ["Rain in three days.", "Dry week coming.", "Storm by nightfall.", "Perfect planting weather."]
	modify_relationship("player", 3.0, "weather prediction")
	npc_memory.add_event_memory("weather_prediction", "Tomas predicted: " + predictions.pick_random(), ["player"], "", 0.2)

func _teach_patience() -> void:
	modify_relationship("player", 5.0, "taught patience")
	npc_memory.learn_fact("tomas_patience_lesson", true, 0.8, "player")

func get_inventory_items() -> Array[String]:
	return ["ancient_wheat", "heritage_potato", "old_corn", "grandfather_hoe", "weather_jar"]

func get_item_value(item: String) -> int:
	var values := {"ancient_wheat": 200, "heritage_potato": 150, "old_corn": 300, "grandfather_hoe": 500, "weather_jar": 100}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (tomas_inventory != null): tomas_inventory = []
	tomas_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (tomas_inventory != null) and item in tomas_inventory: tomas_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["tomas_inventory"] = tomas_inventory if (tomas_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	tomas_inventory = data.get("tomas_inventory", [])