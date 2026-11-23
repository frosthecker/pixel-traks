extends "res://scripts/npc_enhanced.gd"
class_name PlexEnhanced

var plex_inventory: Array = []
## Plex - Tinkerer/Engineer NPC

func _ready() -> void:
	npc_name = "Plex"
	groq_character_id = "Plex"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_plex_personality()

func _setup_plex_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 65, "trustfulness": 60, "generosity": 70, "loyalty": 65,
			"competitiveness": 40, "aggressiveness": 15, "curiosity": 95, "extraversion": 55
		}
		biodata.skill_affinities = {"farming": 0.6, "mining": 0.7, "fishing": 0.4, "combat": 0.4, "social": 1.0, "crafting": 1.6}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.4
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.7
		biodata.preferred_topics = ["mechanics", "flight", "gears", "steam", "scavenging", "impossible", "perpetual motion"]
		biodata.avoided_topics = ["safety regulations", "her failed glider", "the mainland academy", "practicality", "impossible"]
		biodata.speech_patterns = ["*tightens bolt*", "*oils gear*", "What if...", "Physics is a suggestion.", "It almost flew."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		tinkerer_work_step()

func tinkerer_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_tinkerer_work(level)
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

func _prepare_tinkerer_work(level: Node) -> void:
	# Plex works at workshop, scavenges, tests flying machine
	var sites := [
		{"pos": Vector2(250, -180), "tool": Enum.Tool.HAMMER},   # Workshop
		{"pos": Vector2(300, -200), "tool": Enum.Tool.HAMMER},   # Glider test site
		{"pos": Vector2(200, -150), "tool": Enum.Tool.AXE},      # Scavenging
	]
	var site: Dictionary = sites[worker_work_phase % sites.size()]
	worker_target_position = site.pos
	worker_target_tool = site.tool

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"plex_give_gadget": _give_gadget()
			"plex_teach_mechanics": _teach_mechanics()
			"plex_test_flight": _test_flight()
		return
	super._on_dialogic_signal(argument)

func _give_gadget() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var gadgets := ["gear_mechanism", "steam_valve", "pressure_gauge", "spring_coil", "flywheel"]
		level.give_item_to_player(gadgets.pick_random(), randi_range(1, 3))
	modify_relationship("player", 5.0, "gave gadget")

func _teach_mechanics() -> void:
	modify_relationship("player", 10.0, "taught mechanics")
	npc_memory.learn_fact("mechanics_known", true, 0.9, "player")

func _test_flight() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("flight_log", 1)
	modify_relationship("player", 8.0, "tested flight")
	npc_memory.add_event_memory("flight_test", "Plex tested glider with player watching", ["player"], "", 0.4)

func get_inventory_items() -> Array[String]:
	return ["gear_mechanism", "steam_valve", "pressure_gauge", "spring_coil", "flywheel", "glider_wing", "flight_log", "blueprint"]

func get_item_value(item: String) -> int:
	var values := {"gear_mechanism": 40, "steam_valve": 60, "pressure_gauge": 80, "spring_coil": 30, "flywheel": 100, "glider_wing": 500, "flight_log": 200, "blueprint": 300}
	return values.get(item, 40)

func add_inventory_item(item: String) -> void:
	if not (plex_inventory != null): plex_inventory = []
	plex_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (plex_inventory != null) and item in plex_inventory: plex_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["plex_inventory"] = plex_inventory if (plex_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	plex_inventory = data.get("plex_inventory", [])