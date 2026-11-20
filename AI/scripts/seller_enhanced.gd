extends "res://scripts/npc_enhanced.gd"
class_name SellerEnhanced

var marcus_inventory: Array = []
## Marcus - Traveling Merchant/Shopkeeper NPC

func _ready() -> void:
	npc_name = "Marcus"
	groq_character_id = "Marcus"
	base_speed = 18.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_marcus_personality()

func _setup_marcus_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 70,
			"trustfulness": 45,
			"generosity": 35,
			"loyalty": 60,
			"competitiveness": 70,
			"aggressiveness": 15,
			"curiosity": 75,
			"extraversion": 80,
		}
		biodata.skill_affinities = {
			"farming": 1.0,
			"mining": 0.8,
			"fishing": 0.8,
			"combat": 0.6,
			"social": 1.4,
			"crafting": 1.0,
		}
		biodata.memory_retention = 1.0
		biodata.learning_rate = 1.2
		biodata.grudge_holding = 0.5
		biodata.forgiveness = 0.6
		biodata.preferred_topics = ["trade", "prices", "market trends", "rare goods", "mainland news", "shipping", "barter", "investments"]
		biodata.avoided_topics = ["his suppliers", "past debts", "the mainland authorities", "personal life"]
		biodata.speech_patterns = ["*calculates on abacus*", "*polishes scales*", "A fair trade.", "Everything has its price.", "Buy low, sell high."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Marcus mostly stays at his shop, occasionally wanders
	if behavior_state == "work" and not dialogue_running:
		shopkeeper_work_step()

func shopkeeper_work_step() -> bool:
	# Marcus tends his shop - organizes goods, restocks, etc.
	var level := get_tree().current_scene
	if level == null:
		return true
	
	# Shopkeeper "work" is mostly staying at the shop location
	var shop_pos := Vector2(50, 200)
	if global_position.distance_to(shop_pos) > 20.0:
		var dir := global_position.direction_to(shop_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	# At shop - simulate shopkeeping activities
	worker_work_phase += 1
	return true

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		match sig_str:
			"marcus_buy_crops":
				_buy_crops()
			"marcus_sell_seeds":
				_sell_seeds()
			"marcus_sell_tools":
				_sell_tools()
			"marcus_market_info":
				_share_market_info()
		return
	super._on_dialogic_signal(argument)

func _buy_crops() -> void:
	# This connects to the existing seller functionality
	var earnings := PlayerInventory.sell_all_crops()
	if earnings > 0:
		modify_relationship("player", 5.0, "bought crops")
		npc_memory.add_event_memory("trade", "Bought crops from player for %d gold" % earnings, ["player"], "", 0.2)

func _sell_seeds() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var seeds := ["wheat_seeds", "potato_seeds", "cabbage_seeds", "tomato_seeds", "corn_seeds"]
		level.give_item_to_player(seeds.pick_random(), randi_range(5, 15))
	modify_relationship("player", 3.0, "sold seeds")

func _sell_tools() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var tools := ["copper_hoe", "copper_axe", "copper_pickaxe", "fishing_rod"]
		level.give_item_to_player(tools.pick_random(), 1)
	modify_relationship("player", 8.0, "sold tool")

func _share_market_info() -> void:
	modify_relationship("player", 2.0, "shared market info")
	npc_memory.learn_fact("market_tip", "Prices rising for " + ["wheat", "potatoes", "cabbage", "fish", "ore"].pick_random(), 0.7, "marcus")

func get_inventory_items() -> Array[String]:
	return ["wheat_seeds", "potato_seeds", "cabbage_seeds", "copper_hoe", "copper_axe", "fishing_rod", "fertilizer", "rare_item"]

func get_item_value(item: String) -> int:
	var values := {
		"wheat_seeds": 5,
		"potato_seeds": 8,
		"cabbage_seeds": 12,
		"tomato_seeds": 15,
		"corn_seeds": 10,
		"copper_hoe": 150,
		"copper_axe": 150,
		"copper_pickaxe": 150,
		"fishing_rod": 200,
		"fertilizer": 25,
		"rare_item": 500,
	}
	return values.get(item, 10)

func add_inventory_item(item: String) -> void:
	if not (marcus_inventory != null):
		marcus_inventory = []
	marcus_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (marcus_inventory != null) and item in marcus_inventory:
		marcus_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["marcus_inventory"] = marcus_inventory if (marcus_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	marcus_inventory = data.get("marcus_inventory", [])