extends "res://scripts/npc_enhanced.gd"
class_name OrinEnhanced

var orin_inventory: Array = []
## Orin - Veteran Fisherman NPC

func _ready() -> void:
	npc_name = "Orin"
	groq_character_id = "Orin"
	base_speed = 20.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_orin_personality()

func _setup_orin_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 50,
			"trustfulness": 40,
			"generosity": 55,
			"loyalty": 85,
			"competitiveness": 40,
			"aggressiveness": 30,
			"curiosity": 60,
			"extraversion": 45,
		}
		biodata.skill_affinities = {
			"farming": 0.6,
			"mining": 0.5,
			"fishing": 1.5,
			"combat": 1.1,
			"social": 0.8,
			"crafting": 0.9,
		}
		biodata.memory_retention = 1.0
		biodata.learning_rate = 0.8
		biodata.grudge_holding = 0.7
		biodata.forgiveness = 0.4
		biodata.preferred_topics = ["fishing", "the sea", "tides", "storms", "shipwrecks", "island history", "marine life", "knots"]
		biodata.avoided_topics = ["mainland", "modern technology", "his family", "the lighthouse incident"]
		biodata.speech_patterns = ["*spits over shoulder*", "*mends net*", "Ay, the tide...", "Back in my day,", "The sea doesn't forgive"]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if behavior_state == "work" and not dialogue_running:
		fisherman_work_step()

func fisherman_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true
	
	if worker_target_position == Vector2.INF:
		_prepare_fisherman_work(level)
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
	
	# Fisherman uses fishing tool at water spots
	level.npc_tool_use(worker_target_tool, worker_target_position, false, Enum.Seed.WHEAT)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_fisherman_work(level: Node) -> void:
	# Orin fishes at specific water locations
	var fishing_spots := [
		Vector2(-200, 300),
		Vector2(-250, 350),
		Vector2(-150, 280),
		Vector2(-180, 320),
	]
	
	# Cycle through fishing spots
	var spot_index := worker_work_phase % fishing_spots.size()
	worker_target_position = fishing_spots[spot_index]
	worker_target_tool = Enum.Tool.FISH

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"orin_give_fish":
				_give_fish()
			"orin_teach_fishing":
				_teach_fishing()
			"orin_tell_story":
				_tell_story()
		return
	super._on_dialogic_signal(argument)

func _give_fish() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var fish := ["fish_small", "fish_medium", "fish_large", "rare_fish"]
		level.give_item_to_player(fish.pick_random(), randi_range(1, 3))
	modify_relationship("player", 5.0, "gifted fish")

func _teach_fishing() -> void:
	modify_relationship("player", 8.0, "taught fishing")
	npc_memory.learn_fact("fishing_taught_by_orin", true, 0.9, "player")

func _tell_story() -> void:
	modify_relationship("player", 3.0, "shared story")
	npc_memory.add_event_memory("story_told", "Orin told a story about the sea", ["player"], "", 0.2)

func get_inventory_items() -> Array[String]:
	return ["fish_small", "fish_medium", "fishing_rod", "net", "rope", "shell"]

func get_item_value(item: String) -> int:
	var values := {
		"fish_small": 15,
		"fish_medium": 30,
		"fish_large": 60,
		"rare_fish": 200,
		"fishing_rod": 100,
		"net": 50,
		"rope": 20,
		"shell": 10,
	}
	return values.get(item, 15)

func add_inventory_item(item: String) -> void:
	if not (orin_inventory != null):
		orin_inventory = []
	orin_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (orin_inventory != null) and item in orin_inventory:
		orin_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["orin_inventory"] = orin_inventory if (orin_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	orin_inventory = data.get("orin_inventory", [])