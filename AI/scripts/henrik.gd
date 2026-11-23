extends "res://scripts/npc_enhanced.gd"
class_name HenrikEnhanced

var henrik_inventory: Array = []
## Henrik - Hunter/Trapper NPC

func _ready() -> void:
	npc_name = "Henrik"
	groq_character_id = "Henrik"
	base_speed = 26.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_henrik_personality()

func _setup_henrik_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 40, "trustfulness": 35, "generosity": 50, "loyalty": 80,
			"competitiveness": 45, "aggressiveness": 40, "curiosity": 70, "extraversion": 25
		}
		biodata.skill_affinities = {"farming": 0.3, "mining": 0.4, "fishing": 0.5, "combat": 1.3, "social": 0.6, "crafting": 1.1}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.0
		biodata.grudge_holding = 0.6; biodata.forgiveness = 0.4
		biodata.preferred_topics = ["tracking", "game behavior", "bows", "traps", "the deep woods", "spirits", "survival"]
		biodata.avoided_topics = ["trophy hunting", "waste", "cities", "his family", "the white stag"]
		biodata.speech_patterns = ["*nocks arrow*", "*reads tracks*", "The forest watches.", "Waste nothing.", "Silence is a weapon."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		hunter_work_step()

func hunter_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_hunter_work(level)
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

func _prepare_hunter_work(level: Node) -> void:
	# Henrik checks traps, hunts game, maintains territory
	var hunt_spots := [
		Vector2(-300, 100),
		Vector2(-350, 150),
		Vector2(-250, 50),
		Vector2(-400, 0),
		Vector2(-350, -50),
	]
	var spot: Vector2 = hunt_spots[worker_work_phase % hunt_spots.size()]
	worker_target_position = spot
	
	# Alternate between trapping (hoe), hunting (axe), checking traps (shovel)
	var tools := [Enum.Tool.HOE, Enum.Tool.AXE, Enum.Tool.HOE]
	worker_target_tool = tools[worker_work_phase % tools.size()]

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"henrik_give_pelt": _give_pelt()
			"henrik_teach_tracking": _teach_tracking()
			"henrik_give_bow": _give_bow()
		return
	super._on_dialogic_signal(argument)

func _give_pelt() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var pelts := ["deer_pelt", "wolf_pelt", "bear_pelt", "fox_pelt", "rare_white_pelt"]
		level.give_item_to_player(pelts.pick_random(), 1)
	modify_relationship("player", 8.0, "gifted pelt")

func _teach_tracking() -> void:
	modify_relationship("player", 10.0, "taught tracking")
	npc_memory.learn_fact("tracking_known", true, 0.9, "player")

func _give_bow() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("hunter_bow", 1)
	modify_relationship("player", 15.0, "gifted bow")

func get_inventory_items() -> Array[String]:
	return ["deer_pelt", "wolf_pelt", "bear_pelt", "fox_pelt", "hunter_bow", "arrows", "trap", "tracking_knife"]

func get_item_value(item: String) -> int:
	var values := {"deer_pelt": 60, "wolf_pelt": 100, "bear_pelt": 200, "fox_pelt": 40, "hunter_bow": 250, "arrows": 5, "trap": 30, "tracking_knife": 80}
	return values.get(item, 30)

func add_inventory_item(item: String) -> void:
	if not (henrik_inventory != null): henrik_inventory = []
	henrik_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (henrik_inventory != null) and item in henrik_inventory: henrik_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["henrik_inventory"] = henrik_inventory if (henrik_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	henrik_inventory = data.get("henrik_inventory", [])