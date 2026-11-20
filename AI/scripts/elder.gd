extends "res://scripts/npc_enhanced.gd"
class_name ElderEnhanced

var thom_inventory: Array = []
## Elder Thom - Island Historian/Spiritual Guide NPC

func _ready() -> void:
	npc_name = "Elder Thom"
	groq_character_id = "Thom"
	base_speed = 12.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_elder_personality()

func _setup_elder_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 80,
			"trustfulness": 75,
			"generosity": 85,
			"loyalty": 90,
			"competitiveness": 5,
			"aggressiveness": 0,
			"curiosity": 70,
			"extraversion": 30,
		}
		biodata.skill_affinities = {
			"farming": 1.0,
			"mining": 0.4,
			"fishing": 0.6,
			"combat": 0.2,
			"social": 1.5,
			"crafting": 0.8,
		}
		biodata.memory_retention = 1.5
		biodata.learning_rate = 0.7
		biodata.grudge_holding = 0.1
		biodata.forgiveness = 0.95
		biodata.preferred_topics = ["island history", "ancient ruins", "legends", "spirits", "the old ways", "seasons", "wisdom", "balance"]
		biodata.avoided_topics = ["modern technology", "mainland wars", "greed", "his true age"]
		biodata.speech_patterns = ["*strokes beard*", "*gazes at horizon*", "In the old days...", "The island remembers.", "Balance in all things."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Elder mostly stays at his spot, occasionally wanders slowly
	if behavior_state == "work" and not dialogue_running:
		elder_work_step()

func elder_work_step() -> bool:
	# Elder meditates, tends a small garden, records history
	var home_pos := Vector2(-50, -50)
	
	if global_position.distance_to(home_pos) > 10.0:
		var dir := global_position.direction_to(home_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	# At home - simulate meditation/recording
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"thom_give_blessing":
				_give_blessing()
			"thom_reveal_lore":
				_reveal_lore()
			"thom_give_artifact":
				_give_artifact()
		return
	super._on_dialogic_signal(argument)

func _give_blessing() -> void:
	# Temporary buff to player
	modify_relationship("player", 10.0, "blessing received")
	npc_memory.learn_fact("thom_blessing", true, 1.0, "player")
	var level := get_tree().current_scene
	if level and level.has_method("apply_blessing"):
		level.apply_blessing()

func _reveal_lore() -> void:
	# Share island secret/lore
	var secrets := [
		"There's a cave behind the waterfall with ancient carvings.",
		"The lighthouse lens focuses more than light on certain nights.",
		"Old Thom's walking staff was once a king's scepter.",
		"The trees in the deep forest whisper if you listen.",
		"Buried beneath the town square lies the first settlement's heart.",
	]
	modify_relationship("player", 8.0, "shared lore")
	npc_memory.add_event_memory("lore_revealed", "Elder Thom revealed: " + secrets.pick_random(), ["player"], "", 0.5)

func _give_artifact() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var artifacts := ["ancient_coin", "spirit_charm", "old_map", "crystal_shard", "weathered_journal"]
		level.give_item_to_player(artifacts.pick_random(), 1)
	modify_relationship("player", 15.0, "gifted artifact")

func get_inventory_items() -> Array[String]:
	return ["ancient_coin", "spirit_charm", "old_map", "crystal_shard", "weathered_journal", "herbal_tea", "walking_staff"]

func get_item_value(item: String) -> int:
	var values := {
		"ancient_coin": 200,
		"spirit_charm": 300,
		"old_map": 500,
		"crystal_shard": 400,
		"weathered_journal": 600,
		"herbal_tea": 20,
		"walking_staff": 150,
	}
	return values.get(item, 100)

func add_inventory_item(item: String) -> void:
	if not (thom_inventory != null):
		thom_inventory = []
	thom_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (thom_inventory != null) and item in thom_inventory:
		thom_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["thom_inventory"] = thom_inventory if (thom_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	thom_inventory = data.get("thom_inventory", [])