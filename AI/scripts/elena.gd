extends "res://scripts/npc_enhanced.gd"
class_name ElenaEnhanced

var elena_inventory: Array = []
## Elena - Potter NPC

func _ready() -> void:
	npc_name = "Elena"
	groq_character_id = "Elena"
	base_speed = 18.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_elena_personality()

func _setup_elena_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 65, "trustfulness": 60, "generosity": 70, "loyalty": 75,
			"competitiveness": 20, "aggressiveness": 5, "curiosity": 75, "extraversion": 40
		}
		biodata.skill_affinities = {"farming": 0.8, "mining": 0.7, "fishing": 0.4, "combat": 0.3, "social": 1.0, "crafting": 1.5}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.0
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.8
		biodata.preferred_topics = ["clay bodies", "glaze chemistry", "kiln gods", "centering", "wabi-sabi", "ancient forms", "fire"]
		biodata.avoided_topics = ["mass production", "perfectionism", "her failed marriage", "the kiln accident", "plastic"]
		biodata.speech_patterns = ["*wets fingers*", "*spins wheel*", "Clay has memory.", "The kiln decides.", "Centering is a prayer."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		potter_work_step()

func potter_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_potter_work(level)
		if worker_target_position == Vector2.INF: return true
	
	if global_position.distance_to(worker_target_position) > 12.0:
		var dir := global_position.direction_to(worker_target_position)
		last_direction = dir.round()
		move(dir, base_speed * work_efficiency)
		return false
	
	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(worker_target_position).round()
	if last_direction.is_zero_approx(): last_direction = Vector2.RIGHT
	level.npc_tool_use(worker_target_tool, worker_target_position, false, Seed.WHEAT)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_potter_work(level: Node) -> void:
	# Elena works at wheel (hoe), kiln (axe), clay pit (shovel)
	var activities := [
		{"tool": Tool.HOE, "spot": _find_wheel_spot},      # Wheel throwing
		{"tool": Tool.AXE, "spot": _find_kiln_spot},       # Kiln firing
		{"tool": Tool.HOE, "spot": _find_clay_spot},    # Clay digging
	]
	var act := activities[worker_work_phase % activities.size()]
	worker_target_tool = act.tool
	worker_target_position = act.spot(level)

func _find_wheel_spot(level: Node) -> Vector2:
	return Vector2(-200, -100)  # Workshop wheel

func _find_kiln_spot(level: Node) -> Vector2:
	return Vector2(-250, -150)  # Kiln location

func _find_clay_spot(level: Node) -> Vector2:
	return Vector2(-150, -50)   # Clay deposit

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"elena_give_pot": _give_pot()
			"elena_teach_centering": _teach_centering()
			"elena_fire_piece": _fire_piece()
		return
	super._on_dialogic_signal(argument)

func _give_pot() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var pots := ["tea_cup", "storage_jar", "cooking_pot", "vase", "offering_bowl"]
		level.give_item_to_player(pots.pick_random(), 1)
	modify_relationship("player", 8.0, "gifted pottery")

func _teach_centering() -> void:
	modify_relationship("player", 10.0, "taught centering")
	npc_memory.learn_fact("centering_known", true, 0.9, "player")

func _fire_piece() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("fire_player_pottery"):
		level.fire_player_pottery()
	modify_relationship("player", 5.0, "fired piece")

func get_inventory_items() -> Array[String]:
	return ["tea_cup", "storage_jar", "cooking_pot", "vase", "offering_bowl", "kiln_tongs", "glaze_brush"]

func get_item_value(item: String) -> int:
	var values := {"tea_cup": 30, "storage_jar": 50, "cooking_pot": 80, "vase": 100, "offering_bowl": 150, "kiln_tongs": 40, "glaze_brush": 35}
	return values.get(item, 30)

func add_inventory_item(item: String) -> void:
	if not (elena_inventory != null): elena_inventory = []
	elena_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (elena_inventory != null) and item in elena_inventory: elena_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["elena_inventory"] = elena_inventory if (elena_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	elena_inventory = data.get("elena_inventory", [])