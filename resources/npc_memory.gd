class_name NPCMemory extends Resource

@export var npc_id: String = ""
@export var known_entities: Dictionary = {}
@export var location_memories: Dictionary = {}
@export var event_memories: Array[Dictionary] = []
@export var knowledge: Dictionary = {}
@export var rumors_known: Array[Dictionary] = []
@export var personal_goals: Array[Dictionary] = []
@export var grudges: Dictionary = {}
@export var favors_owed: Dictionary = {}
@export var promises_made: Array[Dictionary] = []
@export var daily_reflection: String = ""

const MEMORY_DECAY_RATE: float = 0.98
const EVENT_MEMORY_MAX: int = 100
const RUMOR_MAX: int = 30
const KNOWLEDGE_DECAY_DAYS: int = 30

func _init() -> void:
	pass

func record_meeting(entity_id: String, entity_type: String, entity_name: String = "") -> void:
	if not known_entities.has(entity_id):
		known_entities[entity_id] = {
			"type": entity_type, "name": entity_name, "first_met_time": 0, "first_met_day": 0,
			"last_seen_time": 0, "last_seen_day": 0, "times_met": 1, "total_interaction_time": 0
		}
	else:
		known_entities[entity_id]["times_met"] += 1

func record_location_visit(location_id: String, activity: String = "") -> void:
	if not location_memories.has(location_id):
		location_memories[location_id] = {"visits": 0, "first_visit_day": 0, "last_visit_day": 0, "activities_done": [], "importance": 0.0}
	var mem: Dictionary = location_memories[location_id]
	mem["visits"] += 1
	if activity and activity not in mem["activities_done"]:
		mem["activities_done"].append(activity)
	mem["importance"] = min(100.0, mem["importance"] + 1.0)

func add_event_memory(event_type: String, description: String, participants: Array[String] = [], location: String = "", emotional_impact: float = 0.0) -> void:
	var memory: Dictionary = {
		"type": event_type, "description": description, "participants": participants,
		"location": location, "emotional_impact": emotional_impact, "time": 0, "day": 0,
		"importance": abs(emotional_impact) * 10.0 + 1.0
	}
	event_memories.append(memory)
	event_memories.sort_custom(_compare_memory_importance.bind())
	if event_memories.size() > 100:
		event_memories.resize(100)

func _compare_memory_importance(a: Dictionary, b: Dictionary) -> int:
	var imp_a: float = a.get("importance", 0.0)
	var imp_b: float = b.get("importance", 0.0)
	if imp_a != imp_b:
		return -1 if imp_a > imp_b else 1
	var day_a: int = a.get("day", 0)
	var day_b: int = b.get("day", 0)
	return -1 if day_a > day_b else 1

func learn_fact(fact_key: String, value: Variant, confidence: float = 1.0, source: String = "") -> void:
	knowledge[fact_key] = {"value": value, "confidence": clampf(confidence, 0.0, 1.0), "source": source, "time_learned": 0, "day_learned": 0, "times_reinforced": 1}

func update_fact(fact_key: String, new_value: Variant, confidence_delta: float) -> void:
	if knowledge.has(fact_key):
		var fact: Dictionary = knowledge[fact_key]
		fact["confidence"] = clampf(fact["confidence"] + confidence_delta, 0.0, 1.0)
		fact["times_reinforced"] += 1
		if confidence_delta > 0:
			fact["value"] = new_value
		if fact["confidence"] < 0.1:
			knowledge.erase(fact_key)

func hear_rumor(content: String, source: String, believed: bool = true) -> void:
	rumors_known.append({"content": content, "source": source, "time_heard": 0, "day_heard": 0, "believed": believed, "spread_count": 0})
	if rumors_known.size() > 30:
		rumors_known.remove_at(0)

func add_goal(description: String, priority: float = 1.0) -> void:
	personal_goals.append({"description": description, "priority": clampf(priority, 0.0, 10.0), "progress": 0.0, "created_time": 0, "created_day": 0, "completed": false})

func update_goal_progress(goal_index: int, progress: float) -> void:
	if goal_index >= 0 and goal_index < personal_goals.size():
		personal_goals[goal_index]["progress"] = clampf(progress, 0.0, 1.0)
		if personal_goals[goal_index]["progress"] >= 1.0:
			personal_goals[goal_index]["completed"] = true

func add_grudge(entity_id: String, reason: String, intensity: float = 1.0) -> void:
	grudges[entity_id] = {"reason": reason, "intensity": clampf(intensity, 0.0, 10.0), "created_day": 0}

func resolve_grudge(entity_id: String) -> void:
	if grudges.has(entity_id):
		grudges.erase(entity_id)

func add_favor_owed(entity_id: String, description: String, value: float) -> void:
	favors_owed[entity_id] = {"description": description, "value": value, "created_day": 0, "repaid": false}

func repay_favor(entity_id: String) -> void:
	if favors_owed.has(entity_id):
		favors_owed[entity_id]["repaid"] = true

func make_promise(to_entity: String, description: String, deadline_days: int = 7) -> void:
	promises_made.append({"to_entity": to_entity, "description": description, "deadline_day": deadline_days, "fulfilled": false, "made_day": 0})

func fulfill_promise(promise_index: int) -> void:
	if promise_index >= 0 and promise_index < promises_made.size():
		promises_made[promise_index]["fulfilled"] = true

func apply_daily_decay(current_day: int = 0) -> void:
	if current_day == 0:
		return
	var keys_to_remove: Array[String] = []
	for fact_key in knowledge:
		var fact: Dictionary = knowledge[fact_key]
		var days_old: int = current_day - fact.get("day_learned", current_day)
		if days_old > 30:
			fact["confidence"] *= 0.98
			if fact["confidence"] < 0.1:
				keys_to_remove.append(fact_key)
	for key in keys_to_remove:
		knowledge.erase(key)
	for rumor in rumors_known:
		var days_old: int = current_day - rumor.get("day_heard", current_day)
		if days_old > 7:
			rumor["believed"] = false
	for promise in promises_made:
		if not promise["fulfilled"] and current_day > promise["deadline_day"]:
			promise["overdue"] = true

func write_daily_reflection(current_day: int = 0) -> void:
	if current_day == 0:
		return
	var events_today: Array[Dictionary] = []
	for m in event_memories:
		if m.get("day", 0) == current_day:
			events_today.append(m)
	var met_today: Array[Dictionary] = []
	for k in known_entities:
		var v: Dictionary = known_entities[k]
		if v.get("last_seen_day", 0) == current_day:
			met_today.append(v)
	var reflection: String = "Day %d: " % current_day
	if events_today.size() > 0:
		reflection += "Witnessed %d events. " % events_today.size()
	if met_today.size() > 0:
		reflection += "Met %d people. " % met_today.size()
	if events_today.size() > 0:
		var top_event: Dictionary = events_today[0]
		for m in events_today:
			if m.get("importance", 0.0) > top_event.get("importance", 0.0):
				top_event = m
		reflection += "Most memorable: %s. " % top_event.get("description", "")
	daily_reflection = reflection

func get_relevant_memories(context_keywords: Array[String], max_results: int = 5) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for memory in event_memories:
		var desc: String = memory.get("description", "").to_lower()
		for keyword in context_keywords:
			if desc.contains(keyword.to_lower()):
				results.append(memory)
				break
	results.sort_custom(_compare_memory_importance.bind())
	return results.slice(0, min(max_results, results.size()))

func get_knowledge(topic: String) -> Variant:
	if knowledge.has(topic):
		return knowledge[topic]["value"]
	return null

func to_dict() -> Dictionary:
	return {
		"npc_id": npc_id, "known_entities": known_entities, "location_memories": location_memories,
		"event_memories": event_memories, "knowledge": knowledge, "rumors_known": rumors_known,
		"personal_goals": personal_goals, "grudges": grudges, "favors_owed": favors_owed,
		"promises_made": promises_made, "daily_reflection": daily_reflection
	}

static func from_dict(data: Dictionary) -> NPCMemory:
	var mem := NPCMemory.new()
	mem.npc_id = data.get("npc_id", "")
	mem.known_entities = data.get("known_entities", {})
	mem.location_memories = data.get("location_memories", {})
	mem.event_memories = data.get("event_memories", [])
	mem.knowledge = data.get("knowledge", {})
	mem.rumors_known = data.get("rumors_known", [])
	mem.personal_goals = data.get("personal_goals", [])
	mem.grudges = data.get("grudges", {})
	mem.favors_owed = data.get("favors_owed", {})
	mem.promises_made = data.get("promises_made", [])
	mem.daily_reflection = data.get("daily_reflection", "")
	return mem