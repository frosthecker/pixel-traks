extends "res://scripts/npc_enhanced.gd"
class_name FinnEnhanced

var finn_inventory: Array = []
## Finn - Carpenter NPC

func _ready() -> void:
	npc_name = "Finn"
	groq_character_id = "Finn"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_finn_personality()

func _setup_finn_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 75, "trustfulness": 65, "generosity": 70, "loyalty": 80,
			"competitiveness": 40, "aggressiveness": 20, "curiosity": 55, "extraversion": 80
		}
		biodata.skill_affinities = {"farming": 0.6, "mining": 0.5, "fishing": 0.5, "combat": 1.0, "social": 1.1, "crafting": 1.4}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.4; biodata.forgiveness = 0.7
		biodata.preferred_topics = ["joinery", "boat building", "wood grain", "tools", "the great boat", "apprentices", "storms"]
		biodata.avoided_topics = ["particle board", "nails over screws", "rushed work", "his father's workshop fire", "the boat's launch date"]
		biodata.speech_patterns = ["*planes a board*", "*sniffs wood*", "Wood breathes.", "Measure thrice.", "A good joint outlives us all."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		carpenter_work_step()

func carpenter_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_carpenter_work(level)
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

func _prepare_carpenter_work(level: Node) -> void:
	# Finn works at his shop, on his boat, or gathering wood
	var work_sites := [
		{"pos": Vector2(180, 220), "tool": Tool.HAMMER},   # Shop
		{"pos": Vector2(200, 250), "tool": Tool.HAMMER},   # Boat
		{"pos": Vector2(150, 180), "tool": Tool.AXE},      # Wood gathering
	]
	var site := work_sites[worker_work_phase % work_sites.size()]
	worker_target_position = site.pos
	worker_target_tool = site.tool

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"finn_give_tool": _give_tool()
			"finn_teach_joinery": _teach_joinery()
			"finn_build_boat_part": _build_boat_part()
		return
	super._on_dialogic_signal(argument)

func _give_tool() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var tools := ["carpenter_hammer", "chisel_set", "plane", "saw", "square"]
		level.give_item_to_player(tools.pick_random(), 1)
	modify_relationship("player", 8.0, "gifted tool")

func _teach_joinery() -> void:
	modify_relationship("player", 10.0, "taught joinery")
	npc_memory.learn_fact("joinery_known", true, 0.9, "player")

func _build_boat_part() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("boat_rib", 1)
	modify_relationship("player", 15.0, "built boat part")

func get_inventory_items() -> Array[String]:
	return ["carpenter_hammer", "chisel_set", "plane", "saw", "square", "boat_rib", "marine_glue"]

func get_item_value(item: String) -> int:
	var values := {"carpenter_hammer": 80, "chisel_set": 120, "plane": 100, "saw": 90, "square": 50, "boat_rib": 200, "marine_glue": 30}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (finn_inventory != null): finn_inventory = []
	finn_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (finn_inventory != null) and item in finn_inventory: finn_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["finn_inventory"] = finn_inventory if (finn_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	finn_inventory = data.get("finn_inventory", [])