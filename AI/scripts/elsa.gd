extends "res://scripts/npc_enhanced.gd"
class_name ElsaEnhanced

var elsa_inventory: Array = []
## Elsa - Forager NPC

func _ready() -> void:
	npc_name = "Elsa"
	groq_character_id = "Elsa"
	base_speed = 24.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_elsa_personality()

func _setup_elsa_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 50, "trustfulness": 40, "generosity": 55, "loyalty": 65,
			"competitiveness": 55, "aggressiveness": 20, "curiosity": 85, "extraversion": 35
		}
		biodata.skill_affinities = {"farming": 1.1, "mining": 0.4, "fishing": 0.5, "combat": 0.4, "social": 0.8, "crafting": 1.0}
		biodata.memory_retention = 1.2; biodata.learning_rate = 1.2
		biodata.grudge_holding = 0.4; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["mushrooms", "wild edibles", "poisonous plants", "seasonal cycles", "preservation", "flavors", "the deep forest"]
		biodata.avoided_topics = ["cultivation", "her buyers", "the bad trip incident", "trespassing", "domesticated plants"]
		biodata.speech_patterns = ["*sniffs air*", "*brushes fern*", "The forest provides.", "Know your mushrooms.", "Roots remember."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		forager_work_step()
	elif behavior_state == "wander" and not dialogue_running:
		forager_wander_step()

func forager_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_forager_work(level)
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

func _prepare_forager_work(level: Node) -> void:
	# Elsa forages at specific spots
	var forage_spots := [
		Vector2(-200, -200),
		Vector2(-250, -250),
		Vector2(-150, -150),
		Vector2(-300, -100),
	]
	var spot := forage_spots[worker_work_phase % forage_spots.size()]
	worker_target_position = spot
	
	# Uses hoe for digging roots, axe for cutting, shovel for tubers
	var tools := [Tool.HOE, Tool.AXE, Tool.HOE]
	worker_target_tool = tools[worker_work_phase % tools.size()]

func forager_wander_step() -> bool:
	# Elsa wanders looking for new spots
	if worker_target_position == Vector2.INF or global_position.distance_to(worker_target_position) < 20.0:
		var explore := [
			Vector2(-200, -200), Vector2(-250, -250), Vector2(-150, -150),
			Vector2(-300, -100), Vector2(-100, -300), Vector2(-350, -200),
		]
		worker_target_position = explore.pick_random()
	
	if global_position.distance_to(worker_target_position) > 10.0:
		var dir := global_position.direction_to(worker_target_position)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_target_position = Vector2.INF
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"elsa_give_mushroom": _give_mushroom()
			"elsa_identify_fungus": _identify_fungus()
			"elsa_share_spot": _share_spot()
		return
	super._on_dialogic_signal(argument)

func _give_mushroom() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var mushrooms := ["chantarelle", "morel", "porcini", "death_cap", "ghost_fungus", "bioluminescent_shroom"]
		level.give_item_to_player(mushrooms.pick_random(), randi_range(1, 3))
	modify_relationship("player", 5.0, "gifted mushroom")

func _identify_fungus() -> void:
	modify_relationship("player", 8.0, "identified fungus")
	npc_memory.learn_fact("fungus_id_known", true, 0.9, "player")

func _share_spot() -> void:
	var spots := ["Morels by the old oak.", "Chanterelles near the stream.", "Ghost fungus in the hollow log."]
	modify_relationship("player", 10.0, "shared foraging spot")
	npc_memory.add_event_memory("spot_shared", "Elsa shared: " + spots.pick_random(), ["player"], "", 0.4)

func get_inventory_items() -> Array[String]:
	return ["chantarelle", "morel", "porcini", "death_cap", "ghost_fungus", "bioluminescent_shroom", "foraging_basket", "field_guide"]

func get_item_value(item: String) -> int:
	var values := {"chantarelle": 40, "morel": 80, "porcini": 60, "death_cap": 200, "ghost_fungus": 150, "bioluminescent_shroom": 300, "foraging_basket": 50, "field_guide": 100}
	return values.get(item, 30)

func add_inventory_item(item: String) -> void:
	if not (elsa_inventory != null): elsa_inventory = []
	elsa_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (elsa_inventory != null) and item in elsa_inventory: elsa_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["elsa_inventory"] = elsa_inventory if (elsa_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	elsa_inventory = data.get("elsa_inventory", [])