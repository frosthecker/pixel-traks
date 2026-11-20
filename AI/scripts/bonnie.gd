extends "res://scripts/npc_enhanced.gd"
class_name BonnieEnhanced

var bonnie_inventory: Array = []
## Chef Bonnie - Cook/Restaurateur NPC

func _ready() -> void:
	npc_name = "Chef Bonnie"
	groq_character_id = "Bonnie"
	base_speed = 18.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_bonnie_personality()

func _setup_bonnie_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 85, "trustfulness": 70, "generosity": 90, "loyalty": 75,
			"competitiveness": 20, "aggressiveness": 10, "curiosity": 70, "extraversion": 85
		}
		biodata.skill_affinities = {"farming": 1.1, "mining": 0.3, "fishing": 0.9, "combat": 0.3, "social": 1.4, "crafting": 1.2}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.2; biodata.forgiveness = 0.9
		biodata.preferred_topics = ["recipes", "ingredients", "flavors", "feeding people", "comfort food", "her mother", "the perfect dish"]
		biodata.avoided_topics = ["food critics", "waste", "her failed restaurant", "diets", "portion control"]
		biodata.speech_patterns = ["*tastes spoon*", "*wipes hands*", "Hungry? Sit.", "Food is love made visible.", "Secret ingredient? Care."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		chef_work_step()
	elif behavior_state == "socialize" and not dialogue_running:
		restaurant_social_step()

func chef_work_step() -> bool:
	# Works in kitchen
	var kitchen_pos := Vector2(20, 100)
	if global_position.distance_to(kitchen_pos) > 10.0:
		var dir := global_position.direction_to(kitchen_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_work_phase += 1
	return true

func restaurant_social_step() -> bool:
	# Serves customers in dining area
	var dining_pos := Vector2(50, 120)
	if global_position.distance_to(dining_pos) > 10.0:
		var dir := global_position.direction_to(dining_pos)
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
			"bonnie_feed": _feed_player()
			"bonnie_recipe": _share_recipe()
			"bonnie_cater": _cater_event()
		return
	super._on_dialogic_signal(argument)

func _feed_player() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var foods := ["hearty_stew", "fresh_bread", "grilled_fish", "vegetable_medley", "comfort_pie"]
		level.give_item_to_player(foods.pick_random(), 1)
		if level.has_method("heal_player"):
			level.heal_player(30)
	modify_relationship("player", 8.0, "fed player")

func _share_recipe() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		level.give_item_to_player("bonnie_recipe_card", 1)
	modify_relationship("player", 5.0, "shared recipe")

func _cater_event() -> void:
	modify_relationship("player", 10.0, "catered event")
	npc_memory.add_event_memory("event_catered", "Bonnie catered player's event", ["player"], "", 0.5)

func get_inventory_items() -> Array[String]:
	return ["hearty_stew", "fresh_bread", "grilled_fish", "vegetable_medley", "comfort_pie", "bonnie_recipe_card", "secret_spice_blend"]

func get_item_value(item: String) -> int:
	var values := {"hearty_stew": 40, "fresh_bread": 15, "grilled_fish": 50, "vegetable_medley": 30, "comfort_pie": 60, "bonnie_recipe_card": 100, "secret_spice_blend": 200}
	return values.get(item, 25)

func add_inventory_item(item: String) -> void:
	if not (bonnie_inventory != null): bonnie_inventory = []
	bonnie_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (bonnie_inventory != null) and item in bonnie_inventory: bonnie_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["bonnie_inventory"] = bonnie_inventory if (bonnie_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	bonnie_inventory = data.get("bonnie_inventory", [])