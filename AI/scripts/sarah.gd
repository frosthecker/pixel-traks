extends "res://scripts/npc_enhanced.gd"
class_name SarahEnhanced

var sarah_inventory: Array = []
## Sarah - Beekeeper NPC

func _ready() -> void:
	npc_name = "Sarah"
	groq_character_id = "Sarah"
	base_speed = 16.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_sarah_personality()

func _setup_sarah_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 80, "trustfulness": 70, "generosity": 85, "loyalty": 75,
			"competitiveness": 5, "aggressiveness": 0, "curiosity": 60, "extraversion": 30
		}
		biodata.skill_affinities = {"farming": 1.3, "mining": 0.3, "fishing": 0.4, "combat": 0.1, "social": 1.2, "crafting": 1.0}
		biodata.memory_retention = 1.2; biodata.learning_rate = 0.9
		biodata.grudge_holding = 0.1; biodata.forgiveness = 0.95
		biodata.preferred_topics = ["bees", "honey", "pollination", "hive mind", "royal jelly", "mead", "wax crafts"]
		biodata.avoided_topics = ["pesticides", "loud noises", "hurrying", "killing insects", "bear attacks"]
		biodata.speech_patterns = ["*whispers*", "*adjusts veil*", "The queen is restless.", "Honey remembers every flower.", "Six legs, one heart."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		beekeeper_work_step()

func beekeeper_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_beekeeper_work(level)
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

func _prepare_beekeeper_work(level: Node) -> void:
	# Sarah tends hives at specific locations
	var hive_spots := [
		Vector2(-100, 200),
		Vector2(-150, 250),
		Vector2(-50, 150),
		Vector2(-80, 180),
	]
	var spot := hive_spots[worker_work_phase % hive_spots.size()]
	worker_target_position = spot
	
	# Alternate between checking hives (hoe action) and harvesting (axe)
	worker_target_tool = Tool.HOE if worker_work_phase % 2 == 0 else Tool.AXE

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"sarah_give_honey": _give_honey()
			"sarah_teach_bees": _teach_beekeeping()
			"sarah_give_wax": _give_wax()
		return
	super._on_dialogic_signal(argument)

func _give_honey() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var honey := ["wildflower_honey", "clover_honey", "dark_honey", "royal_jelly"]
		level.give_item_to_player(honey.pick_random(), randi_range(1, 3))
	modify_relationship("player", 5.0, "gifted honey")

func _teach_beekeeping() -> void:
	modify_relationship("player", 8.0, "taught beekeeping")
	npc_memory.learn_fact("beekeeping_known", true, 0.9, "player")

func _give_wax() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("beeswax", randi_range(2, 5))
	modify_relationship("player", 3.0, "gifted wax")

func get_inventory_items() -> Array[String]:
	return ["wildflower_honey", "clover_honey", "dark_honey", "royal_jelly", "beeswax", "propolis", "bee_veil"]

func get_item_value(item: String) -> int:
	var values := {"wildflower_honey": 30, "clover_honey": 25, "dark_honey": 40, "royal_jelly": 200, "beeswax": 20, "propolis": 50, "bee_veil": 100}
	return values.get(item, 20)

func add_inventory_item(item: String) -> void:
	if not (sarah_inventory != null): sarah_inventory = []
	sarah_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (sarah_inventory != null) and item in sarah_inventory: sarah_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["sarah_inventory"] = sarah_inventory if (sarah_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	sarah_inventory = data.get("sarah_inventory", [])