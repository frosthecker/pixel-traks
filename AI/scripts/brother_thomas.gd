extends "res://scripts/npc_enhanced.gd"
class_name BrotherThomasEnhanced

var thomas_inventory: Array = []
## Brother Thomas - Healer Monk NPC

func _ready() -> void:
	npc_name = "Brother Thomas"
	groq_character_id = "BrotherThomas"
	base_speed = 16.0
	work_efficiency = 1.0
	
	super._ready()
	_setup_brother_thomas_personality()

func _setup_brother_thomas_personality() -> void:
	if biodata:
		biodata.social_traits = {
			"friendliness": 85, "trustfulness": 80, "generosity": 90, "loyalty": 95,
			"competitiveness": 0, "aggressiveness": 0, "curiosity": 50, "extraversion": 40
		}
		biodata.skill_affinities = {"farming": 1.0, "mining": 0.3, "fishing": 0.4, "combat": 0.1, "social": 1.5, "crafting": 0.8}
		biodata.memory_retention = 1.1; biodata.learning_rate = 0.9
		biodata.grudge_holding = 0.05; biodata.forgiveness = 0.99
		biodata.preferred_topics = ["healing", "faith", "suffering", "redemption", "herbs", "prayer", "the Order"]
		biodata.avoided_topics = ["violence", "wealth", "his past sins", "the mainland church schism", "miracles"]
		biodata.speech_patterns = ["*folds hands*", "*touches rosary*", "The Lord provides.", "Suffering teaches.", "Peace be with you."]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if behavior_state == "work" and not dialogue_running:
		healer_work_step()
	elif behavior_state == "prayer" and not dialogue_running:
		prayer_step()

func healer_work_step() -> bool:
	# Heals at clinic location
	var clinic_pos := Vector2(-80, -120)
	if global_position.distance_to(clinic_pos) > 10.0:
		var dir := global_position.direction_to(clinic_pos)
		last_direction = dir.round()
		move(dir, base_speed)
		return false
	
	worker_work_phase += 1
	return true

func prayer_step() -> bool:
	# Prays at chapel/shrine
	var shrine_pos := Vector2(0, -100)
	if global_position.distance_to(shrine_pos) > 10.0:
		var dir := global_position.direction_to(shrine_pos)
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
			"thomas_heal": _heal_player()
			"thomas_bless": _bless_player()
			"thomas_herb": _give_herb()
		return
	super._on_dialogic_signal(argument)

func _heal_player() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("heal_player"):
		level.heal_player(50)
	modify_relationship("player", 10.0, "healed player")

func _bless_player() -> void:
	modify_relationship("player", 8.0, "blessed player")
	npc_memory.learn_fact("thomas_blessing", true, 1.0, "player")
	var level := get_tree().current_scene
	if level and level.has_method("apply_blessing"):
		level.apply_blessing()

func _give_herb() -> void:
	var level := get_tree().current_scene
	if level and level.has_method("give_item_to_player"):
		var herbs := ["healing_herb", "calming_herb", "strength_herb", "vision_herb"]
		level.give_item_to_player(herbs.pick_random(), randi_range(2, 5))
	modify_relationship("player", 5.0, "gave herbs")

func get_inventory_items() -> Array[String]:
	return ["healing_herb", "calming_herb", "strength_herb", "vision_herb", "holy_water", "prayer_beads", "blessed_bandage"]

func get_item_value(item: String) -> int:
	var values := {"healing_herb": 30, "calming_herb": 25, "strength_herb": 40, "vision_herb": 60, "holy_water": 50, "prayer_beads": 100, "blessed_bandage": 35}
	return values.get(item, 25)

func add_inventory_item(item: String) -> void:
	if not (thomas_inventory != null): thomas_inventory = []
	thomas_inventory.append(item)

func remove_inventory_item(item: String) -> void:
	if (thomas_inventory != null) and item in thomas_inventory: thomas_inventory.erase(item)

func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["thomas_inventory"] = thomas_inventory if (thomas_inventory != null) else []
	return data

func load_save_data(data: Dictionary) -> void:
	super.load_save_data(data)
	thomas_inventory = data.get("thomas_inventory", [])