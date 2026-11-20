extends "res://scripts/npc_enhanced.gd"
class_name ViktorEnhanced

var viktor_inventory: Array = []
## Viktor - Rival Merchant NPC

func _ready() -> void:
	npc_name = "Viktor"
	groq_character_id = "Viktor"
	base_speed = 20.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_viktor_personality()

func _setup_viktor_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 65, "trustfulness": 20, "generosity": 15, "loyalty": 30,
			"competitiveness": 95, "aggressiveness": 40, "curiosity": 70, "extraversion": 70
		}
		biodata.skill_affinities = {"farming": 0.6, "mining": 0.5, "fishing": 0.5, "combat": 0.7, "social": 1.4, "crafting": 0.8}
		biodata.memory_retention = 1.1; biodata.learning_rate = 1.3
		biodata.grudge_holding = 0.8; biodata.forgiveness = 0.2
		biodata.preferred_topics = ["market manipulation", "contracts", "leverage", "Marcus", "opportunity", "the long game", "weakness"]
		biodata.avoided_topics = ["his past", "conscience", "fair play", "his creditors", "the mainland warrant"]
		biodata.speech_patterns = ["*steeples fingers*", "*checks ledger*", "Every man has his price.", "Contracts are... flexible.", "I'm not the villain. I'm the inevitable."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		rival_merchant_work_step()

func rival_merchant_work_step() -> bool:
	# Works at competing shop
	var shop_pos := Vector2(80, 180)
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
			"viktor_undercut": _undercut()
			"viktor_blackmail": _blackmail()
			"viktor_buy_debt": _buy_debt()
		return
	super._on_dialogic_signal(argument)

func _undercut() -> void:
	modify_relationship("player", -5.0, "undercut prices")
	npc_memory.add_event_memory("undercut", "Viktor undercut player's prices", ["player"], "", -0.3)

func _blackmail() -> void:
	modify_relationship("player", -10.0, "blackmailed")
	npc_memory.add_grudge("player", "Blackmail attempt", 8.0)

func _buy_debt() -> void:
	modify_relationship("player", -3.0, "bought debt")
	npc_memory.add_favor_owed("player", "Debt bought by Viktor", 100.0)

func get_inventory_items() -> Array[String]:
	return ["predatory_contract", "blackmail_letter", "debt_ledger", "mainland_warrant", "stolen_route_map"]

func get_item_value(item: String) -> int:
	var values := {"predatory_contract": 200, "blackmail_letter": 500, "debt_ledger": 300, "mainland_warrant": 1000, "stolen_route_map": 800}
	return values.get(item, 200)

func add_inventory_item(item: String) -> void:
	if not (viktor_inventory != null): viktor_inventory = []
	viktor_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (viktor_inventory != null) and item in viktor_inventory: viktor_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["viktor_inventory"] = viktor_inventory if (viktor_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	viktor_inventory = data.get("viktor_inventory", [])