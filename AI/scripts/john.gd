extends "res://scripts/npc_enhanced.gd"
class_name JohnEnhanced

var john_inventory: Array = []
## John - Enhanced Farmer NPC with full social, memory, and pathfinding systems

@export var farmer_seed: Enum.Seed = Enum.Seed.WHEAT

func _ready() -> void:
	# Set John-specific defaults before calling super
	npc_name = "John"
	groq_character_id = "John"
	base_speed = 25.0
	work_efficiency = 1.0
	worker_seed = farmer_seed
	
	# Call parent _ready which initializes all components
	super._ready()
	
	# John-specific setup
	_setup_john_personality()

func _setup_john_personality() -> void:
	if biodata:
		# Enhance biodata with John's specific traits
		biodata.social_traits = {
			"friendliness": 70,
			"trustfulness": 60,
			"generosity": 65,
			"loyalty": 80,
			"competitiveness": 30,
			"aggressiveness": 10,
			"curiosity": 55,
			"extraversion": 60,
		}
		biodata.skill_affinities = {
			"farming": 1.3,
			"mining": 0.8,
			"fishing": 1.0,
			"combat": 0.5,
			"social": 1.1,
			"crafting": 0.9,
		}
		biodata.memory_retention = 1.1
		biodata.learning_rate = 1.0
		biodata.grudge_holding = 0.3
		biodata.forgiveness = 0.8
		biodata.preferred_topics = ["farming", "weather", "crops", "seasons", "family", "island history"]
		biodata.avoided_topics = ["violence", "dark magic", "mainland politics"]
		biodata.speech_patterns = ["*wipes brow*", "*adjusts hat*", "Y'know,", "Back on the farm,"]

func _physics_process(delta: float) -> void:
	# Call parent for movement, pathfinding, social updates
	super._physics_process(delta)
	
	# John-specific behavior: work during work hours
	if behavior_state == "work" and not dialogue_running:
		worker_work_step()

## Override worker work to use John's specific logic

func _prepare_worker_work(level: Node) -> void:
	# John alternates: farm -> woodcut -> farm -> woodcut
	if worker_work_phase % 2 == 0:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Enum.Tool.SEED
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_nearest_tree_position()
			worker_target_tool = Enum.Tool.AXE
	else:
		worker_target_position = _find_nearest_tree_position()
		worker_target_tool = Enum.Tool.AXE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Enum.Tool.SEED

## Override relationship responses for John's personality

func _on_relationship_changed(target_id: String, old_tier: int, new_tier: int, affinity_change: float) -> void:
	super._on_relationship_changed(target_id, old_tier, new_tier, affinity_change)
	
	# John reacts to relationship milestones
	if new_tier == 2 and old_tier < 2:  # Became friend
		if dialogic and not dialogue_running:
			dialogic.call("start", "res://AI/timelines/john_friendship.dtl")
	elif new_tier == 4 and old_tier < 4:  # Became best friend
		if dialogic and not dialogue_running:
			dialogic.call("start", "res://AI/timelines/john_best_friend.dtl")
	elif new_tier <= -1 and old_tier > -1:  # Became enemy/rival
		npc_memory.add_event_memory("betrayal", "Relationship with %s soured" % target_id, [target_id], "", -0.7)

## Custom dialogue signals for John

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		# Handle local timeline signals
		match sig_str:
			"john_give_seed":
				_give_player_seed()
			"john_give_advice":
				_give_farming_advice()
			"john_ask_help":
				_ask_player_help()
		return
	
	# Delegate to parent for Groq signals
	super._on_dialogic_signal(argument)

func _give_player_seed() -> void:
	# Give player a seed packet
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("wheat_seeds", 5)
	modify_relationship("player", 5.0, "gifted seeds")

func _give_farming_advice() -> void:
	# Share farming knowledge
	var tips := [
		"Water your crops daily for best growth!",
		"Plant near water for automatic irrigation.",
		"Different crops like different seasons.",
		"Trees drop wood when chopped - useful for building.",
		"Fertilized soil grows crops faster.",
	]
	modify_relationship("player", 2.0, "shared knowledge")

func _ask_player_help() -> void:
	# John asks player for help with something
	modify_relationship("player", 3.0, "asked for help")

## Inventory interface for social trading

func get_inventory_items() -> Array[String]:
	# Return items John carries for trading
	var items := []
	if (john_inventory != null):
		for item in john_inventory:
			items.append(item)
	return items

func get_item_value(item: String) -> int:
	var values := {
		"wheat": 10,
		"wheat_seeds": 5,
		"potato": 15,
		"potato_seeds": 8,
		"cabbage": 20,
		"cabbage_seeds": 12,
		"wood": 8,
		"stone": 5,
	}
	return values.get(item, 10)

func add_inventory_item(item: String) -> void:
	if not (john_inventory != null):
		john_inventory = []
	john_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (john_inventory != null) and item in john_inventory:
		john_inventory.erase(item)

## Save/Load integration

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["john_inventory"] = john_inventory if (john_inventory != null) else []
	data["farmer_seed"] = int(farmer_seed)
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	john_inventory = data.get("john_inventory", [])
	farmer_seed = Enum.Seed.WHEAT
	var seed_val: int = int(data.get("farmer_seed", Enum.Seed.WHEAT))
	if seed_val >= 0 and seed_val < Enum.Seed.size():
		farmer_seed = seed_val as Enum.Seed
