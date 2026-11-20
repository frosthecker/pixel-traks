extends "res://scripts/npc_enhanced.gd"
class_name KaiaEnhanced

var kaia_inventory: Array = []
## Kaia - Blacksmith/Miner NPC

func _ready() -> void:
	npc_name = "Kaia"
	groq_character_id = "Kaia"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_kaia_personality()

func _setup_kaia_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 45,
			"trustfulness": 50,
			"generosity": 50,
			"loyalty": 80,
			"competitiveness": 60,
			"aggressiveness": 40,
			"curiosity": 55,
			"extraversion": 40,
		}
		biodata.skill_affinities = {
			"farming": 0.7,
			"mining": 1.5,
			"fishing": 0.5,
			"combat": 1.3,
			"social": 0.7,
			"crafting": 1.5,
		}
		biodata.memory_retention = 1.1
		biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.6
		biodata.forgiveness = 0.5
		biodata.preferred_topics = ["mining", "smithing", "ores", "tools", "weapons", "craftsmanship", "geology", "metalworking"]
		biodata.avoided_topics = ["magic", "politics", "romance", "her wooden carvings"]
		biodata.speech_patterns = ["*wipes soot from cheek*", "*tests blade edge*", "Iron doesn't lie.", "Strike while it's hot.", "Quality takes time."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if behavior_state == "work" and not dialogue_running:
		blacksmith_work_step()

func blacksmith_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true
	
	if worker_target_position == Vector2.INF:
		_prepare_blacksmith_work(level)
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
	
	# Kaia mines with axe/hammer and works at forge
	level.npc_tool_use(worker_target_tool, worker_target_position, false, Seed.WHEAT)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_blacksmith_work(level: Node) -> void:
	# Kaia alternates between mining and forge work
	var mining_spots := [
		Vector2(350, -150),
		Vector2(400, -200),
		Vector2(450, -100),
		Vector2(300, -200),
	]
	var forge_pos := Vector2(300, -100)
	
	if worker_work_phase % 2 == 0:
		# Mining
		var spot_index := (worker_work_phase / 2) % mining_spots.size()
		worker_target_position = mining_spots[spot_index]
		worker_target_tool = Tool.AXE
	else:
		# Forge work (hammer at forge)
		worker_target_position = forge_pos
		worker_target_tool = Tool.HAMMER

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"kaia_repair_tool":
				_repair_tool()
			"kaia_craft_weapon":
				_craft_weapon()
			"kaia_sell_ore":
				_sell_ore()
		return
	super._on_dialogic_signal(argument)

func _repair_tool() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("repair_player_tool"):
		level.repair_player_tool()
	modify_relationship("player", 10.0, "repaired tool")

func _craft_weapon() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var weapons := ["iron_sword", "steel_axe", "iron_hammer", "steel_pickaxe"]
		level.give_item_to_player(weapons.pick_random(), 1)
	modify_relationship("player", 15.0, "crafted weapon")

func _sell_ore() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var ores := ["iron_ore", "copper_ore", "silver_ore", "gold_ore"]
		level.give_item_to_player(ores.pick_random(), randi_range(3, 8))
	modify_relationship("player", 5.0, "sold ore")

func get_inventory_items() -> Array[String]:
	return ["iron_ore", "copper_ore", "iron_ingot", "steel_ingot", "iron_sword", "steel_axe", "hammer", "pickaxe"]

func get_item_value(item: String) -> int:
	var values := {
		"iron_ore": 15,
		"copper_ore": 12,
		"silver_ore": 40,
		"gold_ore": 100,
		"iron_ingot": 30,
		"steel_ingot": 60,
		"iron_sword": 200,
		"steel_axe": 300,
		"hammer": 80,
		"pickaxe": 100,
	}
	return values.get(item, 20)

func add_inventory_item(item: String) -> void:
	if not (kaia_inventory != null):
		kaia_inventory = []
	kaia_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (kaia_inventory != null) and item in kaia_inventory:
		kaia_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["kaia_inventory"] = kaia_inventory if (kaia_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	kaia_inventory = data.get("kaia_inventory", [])