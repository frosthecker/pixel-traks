extends "res://scripts/npc_enhanced.gd"
class_name RivalEnhanced

var rook_inventory: Array = []
## Rook - Competitive Rival Farmer NPC

func _ready() -> void:
	npc_name = "Rook"
	groq_character_id = "Rook"
	base_speed = 28.0
	work_efficiency = 1.2  # Works faster than average
	
	super._ready()
	_setup_rook_personality()

func _setup_rook_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 35,
			"trustfulness": 30,
			"generosity": 25,
			"loyalty": 50,
			"competitiveness": 95,
			"aggressiveness": 45,
			"curiosity": 60,
			"extraversion": 55,
		}
		biodata.skill_affinities = {
			"farming": 1.4,
			"mining": 0.8,
			"fishing": 0.6,
			"combat": 1.0,
			"social": 0.5,
			"crafting": 1.1,
		}
		biodata.memory_retention = 1.0
		biodata.learning_rate = 1.2
		biodata.grudge_holding = 0.7
		biodata.forgiveness = 0.4
		biodata.preferred_topics = ["competition", "best crops", "records", "efficiency", "technique", "winning", "training", "challenges"]
		biodata.avoided_topics = ["losing", "help", "charity", "luck", "shortcuts", "his insecurities"]
		biodata.speech_patterns = ["*wipes sweat*", "*measures stalk*", "Think you can beat that?", "Second place is first loser.", "Show me what you've got."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if behavior_state == "work" and not dialogue_running:
		rival_work_step()

func rival_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true
	
	if worker_target_position == Vector2.INF:
		_prepare_rival_work(level)
		if worker_target_position == Vector2.INF:
			return true
	
	if global_position.distance_to(worker_target_position) > 12.0:
		var travel_direction := global_position.direction_to(worker_target_position)
		last_direction = travel_direction.round()
		move(travel_direction, base_speed * work_efficiency)
		return false
	
	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(worker_target_position).round()
	if last_direction.is_zero_approx():
		last_direction = Vector2.RIGHT
	
	level.npc_tool_use(worker_target_tool, worker_target_position, false, worker_seed)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_rival_work(level: Node) -> void:
	# Rook works his own farm aggressively - mostly farming, some woodcutting
	if worker_work_phase % 4 < 3:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Tool.SEED
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_nearest_tree_position()
			worker_target_tool = Tool.AXE
	else:
		worker_target_position = _find_nearest_tree_position()
		worker_target_tool = Tool.AXE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Tool.SEED

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"rook_challenge":
				_issue_challenge()
			"rook_brag":
				_brag()
			"rook_dismiss":
				_dismiss()
		return
	super._on_dialogic_signal(argument)

func _issue_challenge() -> void:
	# Challenge player to a farming contest
	modify_relationship("player", -2.0, "issued challenge")
	npc_memory.add_event_memory("challenge_issued", "Challenged player to farming contest", ["player"], "", 0.3)

func _brag() -> void:
	# Brag about his achievements
	modify_relationship("player", -3.0, "bragged")

func _dismiss() -> void:
	# Dismiss player's achievements
	modify_relationship("player", -5.0, "dismissed")

func get_inventory_items() -> Array[String]:
	return ["giant_wheat", "prize_potato", "perfect_cabbage", "golden_hoe", "trophy"]

func get_item_value(item: String) -> int:
	var values := {
		"giant_wheat": 100,
		"prize_potato": 150,
		"perfect_cabbage": 200,
		"golden_hoe": 500,
		"trophy": 1000,
	}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (rook_inventory != null):
		rook_inventory = []
	rook_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (rook_inventory != null) and item in rook_inventory:
		rook_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["rook_inventory"] = rook_inventory if (rook_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	rook_inventory = data.get("rook_inventory", [])