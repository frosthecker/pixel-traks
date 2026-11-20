extends "res://scripts/npc_enhanced.gd"
class_name LydiaEnhanced

var lydia_inventory: Array = []
## Lydia - Traveling Trader NPC

func _ready() -> void:
	npc_name = "Lydia"
	groq_character_id = "Lydia"
	base_speed = 22.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_lydia_personality()

func _setup_lydia_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 60, "trustfulness": 35, "generosity": 45, "loyalty": 55,
			"competitiveness": 70, "aggressiveness": 25, "curiosity": 85, "extraversion": 75
		}
		biodata.skill_affinities = {"farming": 0.8, "mining": 0.6, "fishing": 0.7, "combat": 0.8, "social": 1.3, "crafting": 0.9}
		biodata.memory_retention = 1.0; biodata.learning_rate = 1.3
		biodata.grudge_holding = 0.6; biodata.forgiveness = 0.5
		biodata.preferred_topics = ["trade routes", "exotic goods", "sea lanes", "port gossip", "currency exchange", "smuggling", "monsoons"]
		biodata.avoided_topics = ["her family", "the mainland war", "pirates", "settling down", "her lost ship"]
		biodata.speech_patterns = ["*checks compass*", "*tastes wind*", "The tide waits for no merchant.", "Profit favors the bold.", "Every port has its price."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "travel" and not dialogue_running:
		travel_step()
	elif behavior_state == "trade" and not dialogue_running:
		trade_step()

func travel_step() -> bool:
	# Lydia travels between ports
	var travel_points := [Vector2(-50, 250), Vector2(0, 300), Vector2(50, 200)]
	var target := travel_points[worker_work_phase % travel_points.size()]
	
	if global_position.distance_to(target) > 15.0:
		var dir := global_position.direction_to(target)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_work_phase += 1
	return true

func trade_step() -> bool:
	# At trading post - stationary
	var trade_pos := Vector2(-50, 250)
	if global_position.distance_to(trade_pos) > 10.0:
		var dir := global_position.direction_to(trade_pos)
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
			"lydia_sell_exotic": _sell_exotic()
			"lydia_share_gossip": _share_gossip()
			"lydia_buy_cargo": _buy_cargo()
		return
	super._on_dialogic_signal(argument)

func _sell_exotic() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var exotics := ["spices", "silk", "porcelain", "exotic_fruit", "rare_tea", "foreign_coin"]
		level.give_item_to_player(exotics.pick_random(), randi_range(1, 2))
	modify_relationship("player", 5.0, "sold exotic goods")

func _share_gossip() -> void:
	var rumors := ["Pirates near Coral Isle.", "Mainland prices rising.", "New trade route opening.", "Storm sank a fleet."]
	modify_relationship("player", 3.0, "shared gossip")
	npc_memory.hear_rumor(rumors.pick_random(), "Lydia")

func _buy_cargo() -> void:
	modify_relationship("player", 5.0, "bought cargo")
	npc_memory.add_event_memory("trade", "Bought cargo from player", ["player"], "", 0.2)

func get_inventory_items() -> Array[String]:
	return ["spices", "silk", "porcelain", "exotic_fruit", "rare_tea", "foreign_coin", "trade_map"]

func get_item_value(item: String) -> int:
	var values := {"spices": 80, "silk": 150, "porcelain": 200, "exotic_fruit": 40, "rare_tea": 60, "foreign_coin": 100, "trade_map": 300}
	return values.get(item, 50)

func add_inventory_item(item: String) -> void:
	if not (lydia_inventory != null): lydia_inventory = []
	lydia_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (lydia_inventory != null) and item in lydia_inventory: lydia_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["lydia_inventory"] = lydia_inventory if (lydia_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	lydia_inventory = data.get("lydia_inventory", [])