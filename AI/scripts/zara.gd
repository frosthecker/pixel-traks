extends "res://scripts/npc_enhanced.gd"
class_name ZaraEnhanced

var zara_inventory: Array = []
## Zara - Fortune Teller NPC

func _ready() -> void:
	npc_name = "Zara"
	groq_character_id = "Zara"
	base_speed = 14.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_zara_personality()

func _setup_zara_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 55, "trustfulness": 45, "generosity": 50, "loyalty": 60,
			"competitiveness": 30, "aggressiveness": 10, "curiosity": 90, "extraversion": 35
		}
		biodata.skill_affinities = {"farming": 0.5, "mining": 0.4, "fishing": 0.5, "combat": 0.2, "social": 1.4, "crafting": 0.7}
		biodata.memory_retention = 1.4; biodata.learning_rate = 1.1
		biodata.grudge_holding = 0.3; biodata.forgiveness = 0.7
		biodata.preferred_topics = ["fortunes", "destiny", "tea leaves", "cards", "dreams", "omens", "choices"]
		biodata.avoided_topics = ["her own future", "how it works", "skeptics", "the price of knowing", "her teacher"]
		biodata.speech_patterns = ["*shuffles cards*", "*swirls cup*", "The leaves show...", "Two paths. One choice.", "Fortune favors the informed."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "meditate" and not dialogue_running:
		meditate_step()
	elif behavior_state == "work" and not dialogue_running:
		fortune_teller_work_step()

func meditate_step() -> bool:
	var meditation_spot := Vector2(50, -200)
	if global_position.distance_to(meditation_spot) > 10.0:
		var dir := global_position.direction_to(meditation_spot)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	worker_work_phase += 1
	return true

func fortune_teller_work_step() -> bool:
	var reading_spot := Vector2(0, -250)
	if global_position.distance_to(reading_spot) > 10.0:
		var dir := global_position.direction_to(reading_spot)
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
			"zara_read_fortune": _read_fortune()
			"zara_read_cards": _read_cards()
			"zara_warn": _warn_player()
		return
	super._on_dialogic_signal(argument)

func _read_fortune() -> void:
	var fortunes := ["A stranger brings news.", "Lost thing returns.", "Choice at crossroads.", "Wealth in unexpected place.", "Old friend reappears."]
	modify_relationship("player", 5.0, "read fortune")
	npc_memory.add_event_memory("fortune_told", "Zara told fortune: " + fortunes.pick_random(), ["player"], "", 0.3)

func _read_cards() -> void:
	var cards := ["The Tower - sudden change.", "The Star - hope renewed.", "Death - ending and beginning.", "The Lovers - choice of heart."]
	modify_relationship("player", 8.0, "read cards")
	npc_memory.add_event_memory("cards_read", "Zara read: " + cards.pick_random(), ["player"], "", 0.4)

func _warn_player() -> void:
	var warnings := ["Beware the northern cave.", "Trust not the smiling merchant.", "The sea takes what it's owed."]
	modify_relationship("player", 3.0, "warned player")
	npc_memory.add_event_memory("warning_received", "Zara warned: " + warnings.pick_random(), ["player"], "", -0.2)

func get_inventory_items() -> Array[String]:
	return ["tarot_deck", "tea_cup_set", "crystal_ball", "rune_stones", "dream_journal", "protective_charm"]

func get_item_value(item: String) -> int:
	var values := {"tarot_deck": 200, "tea_cup_set": 150, "crystal_ball": 500, "rune_stones": 300, "dream_journal": 100, "protective_charm": 250}
	return values.get(item, 150)

func add_inventory_item(item: String) -> void:
	if not (zara_inventory != null): zara_inventory = []
	zara_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (zara_inventory != null) and item in zara_inventory: zara_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["zara_inventory"] = zara_inventory if (zara_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	zara_inventory = data.get("zara_inventory", [])