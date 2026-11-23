extends "res://scripts/npc_enhanced.gd"
class_name TikoEnhanced

var tiko_inventory: Array = []
## Tiko - Apprentice NPC

func _ready() -> void:
	npc_name = "Tiko"
	groq_character_id = "Tiko"
	base_speed = 26.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_tiko_personality()

func _setup_tiko_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 70, "trustfulness": 65, "generosity": 60, "loyalty": 80,
			"competitiveness": 35, "aggressiveness": 10, "curiosity": 90, "extraversion": 55
		}
		biodata.skill_affinities = {"farming": 0.3, "mining": 0.5, "fishing": 0.4, "combat": 0.4, "social": 1.0, "crafting": 1.3}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.5
		biodata.grudge_holding = 0.2; biodata.forgiveness = 0.8
		biodata.preferred_topics = ["clockwork", "automata", "Kaia", "impossible machines", "gears", "springs", "music boxes"]
		biodata.avoided_topics = ["disappointment", "heavy lifting", "his parents", "wasted metal", "practicality"]
		biodata.speech_patterns = ["*sketches furiously*", "*tests gear*", "What if it...", "Kaia would say...", "Perpetual motion. Maybe."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		apprentice_work_step()

func apprentice_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_apprentice_work(level)
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

func _prepare_apprentice_work(level: Node) -> void:
	# Tiko helps Kaia at forge, works on own projects
	if worker_work_phase % 2 == 0:
		worker_target_position = Vector2(300, -100)  # Kaia's forge
		worker_target_tool = Enum.Tool.HAMMER
	else:
		worker_target_position = Vector2(250, -180)  # Plex's workshop
		worker_target_tool = Enum.Tool.HAMMER

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"tiko_show_gadget": _show_gadget()
			"tiko_ask_advice": _ask_advice()
			"tiko_give_sketch": _give_sketch()
		return
	super._on_dialogic_signal(argument)

func _show_gadget() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var gadgets := ["music_box", "clockwork_bird", "spring_toy", "gear_puzzle"]
		level.give_item_to_player(gadgets.pick_random(), 1)
	modify_relationship("player", 5.0, "showed gadget")

func _ask_advice() -> void:
	modify_relationship("player", 3.0, "asked advice")
	npc_memory.add_event_memory("advice_sought", "Tiko asked for advice", ["player"], "", 0.1)

func _give_sketch() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("tiko_sketch", 1)
	modify_relationship("player", 8.0, "gave sketch")

func get_inventory_items() -> Array[String]:
	return ["music_box", "clockwork_bird", "spring_toy", "gear_puzzle", "tiko_sketch", "brass_gears", "mainspring"]

func get_item_value(item: String) -> int:
	var values := {"music_box": 150, "clockwork_bird": 300, "spring_toy": 80, "gear_puzzle": 120, "tiko_sketch": 200, "brass_gears": 30, "mainspring": 50}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (tiko_inventory != null): tiko_inventory = []
	tiko_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (tiko_inventory != null) and item in tiko_inventory: tiko_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["tiko_inventory"] = tiko_inventory if (tiko_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	tiko_inventory = data.get("tiko_inventory", [])