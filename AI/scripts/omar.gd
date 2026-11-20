extends "res://scripts/npc_enhanced.gd"
class_name OmarEnhanced

var omar_inventory: Array = []
## Omar - Exotic Goods Dealer NPC

func _ready() -> void:
	npc_name = "Omar"
	groq_character_id = "Omar"
	base_speed = 18.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_omar_personality()

func _setup_omar_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 50, "trustfulness": 25, "generosity": 40, "loyalty": 50,
			"competitiveness": 60, "aggressiveness": 20, "curiosity": 95, "extraversion": 55
		}
		biodata.skill_affinities = {"farming": 0.4, "mining": 0.5, "fishing": 0.4, "combat": 0.6, "social": 1.2, "crafting": 1.1}
		biodata.memory_retention = 1.3; biodata.learning_rate = 1.2
		biodata.grudge_holding = 0.4; biodata.forgiveness = 0.6
		biodata.preferred_topics = ["artifacts", "ruins", "forbidden knowledge", "strange creatures", "ancient tech", "collectors", "curses"]
		biodata.avoided_topics = ["his suppliers", "the Inquisition", "provenance", "guarantees", "refunds"]
		biodata.speech_patterns = ["*polishes oddity*", "*weighs coin*", "Curiosity costs.", "Some doors open once.", "I don't sell. I place."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		dealer_work_step()

func dealer_work_step() -> bool:
	# Omar stays at his shop, organizing curiosities
	var shop_pos := Vector2(120, 280)
	if global_position.distance_to(shop_pos) > 10.0:
		var dir := global_position.direction_to(shop_pos)
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
			"omar_sell_artifact": _sell_artifact()
			"omar_identify_item": _identify_item()
			"omar_trade_secret": _trade_secret()
		return
	super._on_dialogic_signal(argument)

func _sell_artifact() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var artifacts := ["ancient_coin", "glowing_orb", "whispering_shell", "star_metal", "void_glass", "memory_vial"]
		level.give_item_to_player(artifacts.pick_random(), 1)
	modify_relationship("player", 10.0, "sold artifact")

func _identify_item() -> void:
	modify_relationship("player", 8.0, "identified item")
	npc_memory.learn_fact("item_identified_by_omar", true, 0.9, "player")

func _trade_secret() -> void:
	var secrets := ["The lighthouse lens focuses moonlight.", "There's a door under the mayor's house.", "The trees talk on moonless nights."]
	modify_relationship("player", 15.0, "traded secret")
	npc_memory.hear_rumor(secrets.pick_random(), "Omar")

func get_inventory_items() -> Array[String]:
	return ["ancient_coin", "glowing_orb", "whispering_shell", "star_metal", "void_glass", "memory_vial", "cursed_dagger"]

func get_item_value(item: String) -> int:
	var values := {"ancient_coin": 500, "glowing_orb": 800, "whispering_shell": 400, "star_metal": 1000, "void_glass": 600, "memory_vial": 700, "cursed_dagger": 1200}
	return values.get(item, 500)

func add_inventory_item(item: String) -> void:
	if not (omar_inventory != null): omar_inventory = []
	omar_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (omar_inventory != null) and item in omar_inventory: omar_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["omar_inventory"] = omar_inventory if (omar_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	omar_inventory = data.get("omar_inventory", [])