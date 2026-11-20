extends "res://scripts/npc_enhanced.gd"
class_name SerafinaEnhanced

var serafina_inventory: Array = []
## Serafina - Rival Artisan NPC

func _ready() -> void:
	npc_name = "Serafina"
	groq_character_id = "Serafina"
	base_speed = 22.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_serafina_personality()

func _setup_serafina_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 70, "trustfulness": 25, "generosity": 30, "loyalty": 35,
			"competitiveness": 90, "aggressiveness": 45, "curiosity": 75, "extraversion": 75
		}
		biodata.skill_affinities = {"farming": 0.3, "mining": 0.5, "fishing": 0.3, "combat": 0.5, "social": 1.3, "crafting": 1.5}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.3
		biodata.grudge_holding = 0.7; biodata.forgiveness = 0.3
		biodata.preferred_topics = ["glassblowing", "light", "color", "perfection", "rivals", "legacy", "immortality through art"]
		biodata.avoided_topics = ["her childhood", "the void", "failure", "love", "rest"]
		biodata.speech_patterns = ["*blows gently*", "*rotates pipe*", "Fire reveals truth.", "Beauty is a weapon.", "They'll remember this."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		rival_artisan_work_step()

func rival_artisan_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_artisan_work(level)
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

func _prepare_artisan_work(level: Node) -> void:
	# Serafina works at her studio
	var studio_pos := Vector2(-150, 80)
	if global_position.distance_to(studio_pos) > 10.0:
		var dir := global_position.direction_to(studio_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return
	
	worker_target_position = studio_pos
	worker_target_tool = Tool.HAMMER  # Glassblowing uses hammer-like tools
	worker_work_phase += 1

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"serafina_sabotage": _sabotage()
			"serafina_poach": _poach()
			"serafina_showpiece": _showpiece()
		return
	super._on_dialogic_signal(argument)

func _sabotage() -> void:
	modify_relationship("player", -8.0, "sabotaged")
	npc_memory.add_event_memory("sabotage", "Serafina sabotaged player's work", ["player"], "", -0.5)

func _poach() -> void:
	modify_relationship("player", -5.0, "poached contact")
	npc_memory.add_grudge("player", "Poached customer", 5.0)

func _showpiece() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var pieces := ["prismatic_vase", "light_catching_bowl", "color_shifting_goblet", "eternal_flame_lamp"]
		level.give_item_to_player(pieces.pick_random(), 1)
	modify_relationship("player", 10.0, "showed masterpiece")

func get_inventory_items() -> Array[String]:
	return ["prismatic_vase", "light_catching_bowl", "color_shifting_goblet", "eternal_flame_lamp", "perfect_sphere", "glass_heart"]

func get_item_value(item: String) -> int:
	var values := {"prismatic_vase": 800, "light_catching_bowl": 600, "color_shifting_goblet": 1000, "eternal_flame_lamp": 1200, "perfect_sphere": 1500, "glass_heart": 2000}
	return values.get(item, 500)

func add_inventory_item(item: String) -> void:
	if not (serafina_inventory != null): serafina_inventory = []
	serafina_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (serafina_inventory != null) and item in serafina_inventory: serafina_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["serafina_inventory"] = serafina_inventory if (serafina_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	serafina_inventory = data.get("serafina_inventory", [])