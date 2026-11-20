extends "res://scripts/npc_enhanced.gd"
class_name GrundyEnhanced

var grundy_inventory: Array = []
## Grundy - Deep Miner NPC

func _ready() -> void:
	npc_name = "Grundy"
	groq_character_id = "Grundy"
	base_speed = 20.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_grundy_personality()

func _setup_grundy_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 45, "trustfulness": 55, "generosity": 60, "loyalty": 85,
			"competitiveness": 30, "aggressiveness": 25, "curiosity": 60, "extraversion": 30
		}
		biodata.skill_affinities = {"farming": 0.2, "mining": 1.7, "fishing": 0.2, "combat": 1.1, "social": 0.6, "crafting": 0.9}
		biodata.memory_retention = 1.1; biodata.learning_rate = 0.8
		biodata.grudge_holding = 0.5; biodata.forgiveness = 0.5
		biodata.preferred_topics = ["ore veins", "deep dark", "cave-ins", "the Heart", "pickaxes", "lamps", "the mountain's bones"]
		biodata.avoided_topics = ["the surface", "his lost crew", "open sky", "women", "retirement"]
		biodata.speech_patterns = ["*taps rock*", "*listens to earth*", "The mountain speaks.", "Deeper. Always deeper.", "Stone remembers."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		miner_work_step()

func miner_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"): return true
	
	if worker_target_position == Vector2.INF:
		_prepare_miner_work(level)
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

func _prepare_miner_work(level: Node) -> void:
	# Grundy mines deep veins
	var veins := [
		Vector2(400, -200),
		Vector2(450, -250),
		Vector2(350, -150),
		Vector2(500, -300),
	]
	var vein := veins[worker_work_phase % veins.size()]
	worker_target_position = vein
	worker_target_tool = Tool.AXE  # Pickaxe

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"grundy_give_ore": _give_ore()
			"grundy_teach_mining": _teach_mining()
			"grundy_warn": _warn_deep()
		return
	super._on_dialogic_signal(argument)

func _give_ore() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var ores := ["deep_iron", "star_iron", "moon_silver", "heart_gold", "void_crystal"]
		level.give_item_to_player(ores.pick_random(), randi_range(2, 5))
	modify_relationship("player", 8.0, "gave ore")

func _teach_mining() -> void:
	modify_relationship("player", 10.0, "taught deep mining")
	npc_memory.learn_fact("deep_mining_known", true, 0.9, "player")

func _warn_deep() -> void:
	var warnings := ["Gas at level 40.", "The walls breathe down there.", "Don't mine the pulsing vein."]
	modify_relationship("player", 3.0, "warned")
	npc_memory.add_event_memory("deep_warning", "Grundy warned: " + warnings.pick_random(), ["player"], "", -0.2)

func get_inventory_items() -> Array[String]:
	return ["deep_iron", "star_iron", "moon_silver", "heart_gold", "void_crystal", "miner_lamp", "pickaxe", "canary"]

func get_item_value(item: String) -> int:
	var values := {"deep_iron": 50, "star_iron": 200, "moon_silver": 300, "heart_gold": 500, "void_crystal": 1000, "miner_lamp": 100, "pickaxe": 80, "canary": 50}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (grundy_inventory != null): grundy_inventory = []
	grundy_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (grundy_inventory != null) and item in grundy_inventory: grundy_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["grundy_inventory"] = grundy_inventory if (grundy_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	grundy_inventory = data.get("grundy_inventory", [])