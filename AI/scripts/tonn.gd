extends "res://scripts/npc_enhanced.gd"
class_name TonnEnhanced

var tonn_inventory: Array = []
## Corporal Tonn - Guard Scout NPC

func _ready() -> void:
	npc_name = "Corporal Tonn"
	groq_character_id = "Tonn"
	base_speed = 28.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_tonn_personality()

func _setup_tonn_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 50, "trustfulness": 45, "generosity": 50, "loyalty": 80,
			"competitiveness": 40, "aggressiveness": 35, "curiosity": 80, "extraversion": 30
		}
		biodata.skill_affinities = {"farming": 0.3, "mining": 0.4, "fishing": 0.5, "combat": 1.2, "social": 0.7, "crafting": 0.9}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.4; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["scouting", "coastline", "smugglers", "maps", "stealth", "the mainland", "novels"]
		biodata.avoided_topics = ["his debt", "his family", "promotion", "close combat", "feelings"]
		biodata.speech_patterns = ["*sketches rapidly*", "*listens*", "Tracks lead north.", "Nothing moves unseen.", "Report."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		scout_work_step()

func scout_work_step() -> bool:
	# Scout patrols coastline and inland
	var scout_points := [
		Vector2(50, -220), Vector2(-50, -220), Vector2(100, -250),
		Vector2(0, -200), Vector2(150, -180), Vector2(-100, -250),
	]
	var target: Vector2 = scout_points[worker_work_phase % scout_points.size()]
	
	if global_position.distance_to(target) > 15.0:
		var dir := global_position.direction_to(target)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"tonn_give_map": _give_map()
			"tonn_teach_stealth": _teach_stealth()
			"tonn_report": _give_report()
		return
	super._on_dialogic_signal(argument)

func _give_map() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var maps := ["coastal_map", "smuggler_map", "inland_map", "cave_map"]
		level.give_item_to_player(maps.pick_random(), 1)
	modify_relationship("player", 8.0, "gave map")

func _teach_stealth() -> void:
	modify_relationship("player", 10.0, "taught stealth")
	npc_memory.learn_fact("stealth_known", true, 0.9, "player")

func _give_report() -> void:
	var reports := ["Smugglers at Cove 3.", "Wreckage on North Beach.", "Strange lights in caves."]
	modify_relationship("player", 3.0, "gave report")
	npc_memory.add_event_memory("scout_report", "Tonn reported: " + reports.pick_random(), ["player"], "", 0.2)

func get_inventory_items() -> Array[String]:
	return ["coastal_map", "smuggler_map", "inland_map", "cave_map", "spyglass", "silent_boots", "signal_mirror"]

func get_item_value(item: String) -> int:
	var values := {"coastal_map": 100, "smuggler_map": 200, "inland_map": 150, "cave_map": 250, "spyglass": 300, "silent_boots": 200, "signal_mirror": 80}
	return values.get(item, 100)

func add_inventory_item(item: String) -> void:
	if not (tonn_inventory != null): tonn_inventory = []
	tonn_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (tonn_inventory != null) and item in tonn_inventory: tonn_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["tonn_inventory"] = tonn_inventory if (tonn_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	tonn_inventory = data.get("tonn_inventory", [])