extends "res://scripts/npc_enhanced.gd"
class_name ChildEnhanced

var pip_inventory: Array = []
## Pip - Curious Child NPC

func _ready() -> void:
	npc_name = "Pip"
	groq_character_id = "Pip"
	base_speed = 35.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_pip_personality()

func _setup_pip_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 90,
			"trustfulness": 80,
			"generosity": 70,
			"loyalty": 60,
			"competitiveness": 40,
			"aggressiveness": 5,
			"curiosity": 100,
			"extraversion": 95,
		}
		biodata.skill_affinities = {
			"farming": 0.3,
			"mining": 0.2,
			"fishing": 0.5,
			"combat": 0.1,
			"social": 1.3,
			"crafting": 0.4,
		}
		biodata.memory_retention = 0.8
		biodata.learning_rate = 1.5
		biodata.grudge_holding = 0.1
		biodata.forgiveness = 0.9
		biodata.preferred_topics = ["animals", "bugs", "shiny things", "hiding spots", "games", "stories", "why?", "treasure", "friends"]
		biodata.avoided_topics = ["chores", "bedtime", "being careful", "adult problems", "sad things"]
		biodata.speech_patterns = ["*bounces on heels*", "*grabs your hand*", "Guess what?!", "Why why why?", "Look look look!"]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Pip is always wandering and exploring
	if behavior_state == "wander" and not dialogue_running:
		explore_step()

func explore_step() -> bool:
	# Pip explores randomly with high curiosity
	if worker_target_position == Vector2.INF or global_position.distance_to(worker_target_position) < 20.0:
		# Pick new exploration target
		var explore_spots := [
			Vector2(0, 0),
			Vector2(50, 50),
			Vector2(-50, 50),
			Vector2(100, 100),
			Vector2(-100, -100),
			Vector2(0, 150),
			Vector2(150, 0),
			Vector2(-150, 0),
			Vector2(0, -100),
			Vector2(200, 50),
		]
		worker_target_position = explore_spots.pick_random()
	
	if global_position.distance_to(worker_target_position) > 10.0:
		var dir := global_position.direction_to(worker_target_position)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"pip_give_treasure":
				_give_treasure()
			"pip_show_secret":
				_show_secret()
			"pip_ask_question":
				_ask_question()
		return
	super._on_dialogic_signal(argument)

func _give_treasure() -> void:
	# Pip gives something she found
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var treasures := ["shiny_rock", "feather", "seashell", "odd_button", "smooth_glass", "lost_coin"]
		level.give_item_to_player(treasures.pick_random(), 1)
	modify_relationship("player", 5.0, "shared treasure")

func _show_secret() -> void:
	# Pip shows a secret spot
	var secrets := [
		"There's a hollow tree near the pond with a nest!",
		"I found a cave behind the berry bushes!",
		"The old well has a shiny thing at the bottom!",
		"There's a path under the big oak roots!",
	]
	modify_relationship("player", 8.0, "showed secret")
	npc_memory.add_event_memory("secret_shown", "Pip showed a secret spot", ["player"], "", 0.4)

func _ask_question() -> void:
	# Pip asks an innocent question
	var questions := [
		"Why is the sky blue?",
		"Do fish sleep?",
		"Can trees talk to each other?",
		"What's on the other side of the ocean?",
		"Why do grown-ups drink bitter water?",
	]
	modify_relationship("player", 2.0, "asked question")

func get_inventory_items() -> Array[String]:
	return ["shiny_rock", "feather", "seashell", "odd_button", "smooth_glass", "lost_coin", "flower_crown", "bug_jar"]

func get_item_value(item: String) -> int:
	var values := {
		"shiny_rock": 10,
		"feather": 5,
		"seashell": 8,
		"odd_button": 3,
		"smooth_glass": 15,
		"lost_coin": 20,
		"flower_crown": 25,
		"bug_jar": 30,
	}
	return values.get(item, 5)

func add_inventory_item(item: String) -> void:
	if not (pip_inventory != null):
		pip_inventory = []
	pip_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (pip_inventory != null) and item in pip_inventory:
		pip_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["pip_inventory"] = pip_inventory if (pip_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	pip_inventory = data.get("pip_inventory", [])