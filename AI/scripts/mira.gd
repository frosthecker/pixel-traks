extends "res://scripts/npc_enhanced.gd"
class_name MiraEnhanced

var mira_inventory: Array = []
## Mira - Herbalist/Alchemist NPC

@export var herbalist_focus: Enum.Seed = Enum.Seed.WHEAT

func _ready() -> void:
	npc_name = "Mira"
	groq_character_id = "Mira"
	base_speed = 22.0
	work_efficiency = 1.0
	worker_seed = herbalist_focus
	
	super._ready()
	_setup_mira_personality()

func _setup_mira_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 65,
			"trustfulness": 55,
			"generosity": 60,
			"loyalty": 70,
			"competitiveness": 25,
			"aggressiveness": 10,
			"curiosity": 90,
			"extraversion": 50,
		}
		biodata.skill_affinities = {
			"farming": 1.2,
			"mining": 0.7,
			"fishing": 0.8,
			"combat": 0.4,
			"social": 1.0,
			"crafting": 1.4,
		}
		biodata.memory_retention = 1.2
		biodata.learning_rate = 1.3
		biodata.grudge_holding = 0.4
		biodata.forgiveness = 0.7
		biodata.preferred_topics = ["herbs", "potions", "alchemy", "rare plants", "ancient remedies", "lore", "recipes"]
		biodata.avoided_topics = ["her past", "why she came here", "violence", "dark magic"]
		biodata.speech_patterns = ["*scribbles in notebook*", "*sniffs herb*", "Fascinating...", "In my studies,", "The properties of"]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if behavior_state == "work" and not dialogue_running:
		herbalist_work_step()

func herbalist_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true
	
	if worker_target_position == Vector2.INF:
		_prepare_herbalist_work(level)
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
	
	# Herbalist uses hoe to prepare soil, then seeds for special herbs
	level.npc_tool_use(worker_target_tool, worker_target_position, false, worker_seed)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_herbalist_work(level: Node) -> void:
	# Mira focuses on special herb spots and foraging
	if worker_work_phase % 3 == 0:
		worker_target_position = _find_herb_spot(level)
		worker_target_tool = Enum.Tool.HOE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Enum.Tool.SEED
	elif worker_work_phase % 3 == 1:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Enum.Tool.SEED
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_foraging_spot()
			worker_target_tool = Enum.Tool.AXE
	else:
		worker_target_position = _find_foraging_spot()
		worker_target_tool = Enum.Tool.AXE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_herb_spot(level)
			worker_target_tool = Enum.Tool.HOE

func _find_herb_spot(level: Node) -> Vector2:
	# Look for dark dirt (watered soil) for special herbs
	var dark_dirt: TileMapLayer = level.get_node_or_null("Layers/DarkDirtLayer")
	if dark_dirt == null:
		return Vector2.INF
	
	var cells := dark_dirt.get_used_cells()
	if cells.is_empty():
		return Vector2.INF
	
	var best_pos := Vector2.INF
	var best_dist := INF
	for cell in cells:
		var pos := dark_dirt.to_global(dark_dirt.map_to_local(cell))
		var dist := global_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos

func _find_foraging_spot() -> Vector2:
	# Look for wild plants/bushes to forage
	var best_pos := Vector2.INF
	var best_dist := INF
	for obj in get_tree().get_nodes_in_group("Objects"):
		if not is_instance_valid(obj):
			continue
		# Check for forageable objects (berry bushes, herb patches, etc.)
		if obj.has_method("is_forageable") and obj.is_forageable():
			var dist := global_position.distance_squared_to(obj.global_position)
			if dist < best_dist:
				best_dist = dist
				best_pos = obj.global_position
	return best_pos

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"mira_give_potion":
				_give_potion()
			"mira_teach_recipe":
				_teach_recipe()
			"mira_identify_plant":
				_identify_plant()
		return
	super._on_dialogic_signal(argument)

func _give_potion() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var potions := ["health_potion", "stamina_potion", "speed_potion", "night_vision_potion"]
		level.give_item_to_player(potions.pick_random(), 1)
	modify_relationship("player", 8.0, "gifted potion")

func _teach_recipe() -> void:
	# Teach player a crafting recipe
	modify_relationship("player", 5.0, "shared knowledge")
	npc_memory.learn_fact("recipe_taught", true, 0.9, "player")

func _identify_plant() -> void:
	# Identify a plant for the player
	modify_relationship("player", 3.0, "identified plant")

func get_inventory_items() -> Array[String]:
	var items := ["health_potion", "stamina_potion", "herb_bundle", "rare_seed"]
	return items

func get_item_value(item: String) -> int:
	var values := {
		"health_potion": 50,
		"stamina_potion": 40,
		"speed_potion": 60,
		"night_vision_potion": 80,
		"herb_bundle": 25,
		"rare_seed": 100,
	}
	return values.get(item, 20)

func add_inventory_item(item: String) -> void:
	if not (mira_inventory != null):
		mira_inventory = []
	mira_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (mira_inventory != null) and item in mira_inventory:
		mira_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["mira_inventory"] = mira_inventory if (mira_inventory != null) else []
	data["herbalist_focus"] = int(herbalist_focus)
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	mira_inventory = data.get("mira_inventory", [])
	herbalist_focus = Enum.Seed.WHEAT
	var seed_val: int = data.get("herbalist_focus", int(Enum.Seed.WHEAT))
	if seed_val:
		herbalist_focus = seed_val