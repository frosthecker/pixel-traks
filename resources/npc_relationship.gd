class_name NPCRelationship extends Resource

enum Tier { STRANGER = 0, ACQUAINTANCE = 1, FRIEND = 2, CLOSE_FRIEND = 3, BEST_FRIEND = 4, RIVAL = -1, ENEMY = -2 }

@export var target_id: String = ""
@export var target_type: String = "npc"
@export var current_tier: int = 0
@export var affinity: float = 0.0
@export var trust: float = 0.0
@export var familiarity: float = 0.0
@export var last_interaction_time: int = 0
@export var interaction_count: int = 0
@export var positive_interactions: int = 0
@export var negative_interactions: int = 0
@export var shared_memories: Array[Dictionary] = []
@export var gifts_given: Array[String] = []
@export var gifts_received: Array[String] = []
@export var quests_completed_together: int = 0
@export var fights_won_together: int = 0
@export var trades_completed: int = 0

const TIER_THRESHOLDS: Dictionary = {
	-2: -80, -1: -30, 0: 0, 1: 15, 2: 35, 3: 60, 4: 85
}

const TIER_MODIFIERS: Dictionary = {
	-2: {"trade_price_mult": 2.0, "dialogue_hostile": true, "assist_in_combat": false, "share_resources": false, "social_chance": 0.1},
	-1: {"trade_price_mult": 1.5, "dialogue_hostile": false, "assist_in_combat": false, "share_resources": false, "social_chance": 0.3},
	0:  {"trade_price_mult": 1.0, "dialogue_hostile": false, "assist_in_combat": false, "share_resources": false, "social_chance": 1.0},
	1:  {"trade_price_mult": 0.95, "dialogue_hostile": false, "assist_in_combat": false, "share_resources": false, "social_chance": 1.2},
	2:  {"trade_price_mult": 0.9, "dialogue_hostile": false, "assist_in_combat": true, "share_resources": true, "social_chance": 1.5},
	3:  {"trade_price_mult": 0.8, "dialogue_hostile": false, "assist_in_combat": true, "share_resources": true, "social_chance": 1.8},
	4:  {"trade_price_mult": 0.7, "dialogue_hostile": false, "assist_in_combat": true, "share_resources": true, "social_chance": 2.0},
}

func calculate_tier() -> int:
	var best_tier := 0
	for tier in TIER_THRESHOLDS:
		if affinity >= TIER_THRESHOLDS[tier]:
			best_tier = tier
	current_tier = best_tier
	return best_tier

func modify_affinity(amount: float, reason: String = "") -> void:
	affinity = clampf(affinity + amount, -100.0, 100.0)
	calculate_tier()
	if amount > 0:
		positive_interactions += 1
	else:
		negative_interactions += 1
	interaction_count += 1

func modify_trust(amount: float) -> void:
	trust = clampf(trust + amount, 0.0, 100.0)

func modify_familiarity(amount: float) -> void:
	familiarity = clampf(familiarity + amount, 0.0, 100.0)

func add_memory(memory_type: String, description: String, positive: bool) -> void:
	shared_memories.append({
		"type": memory_type,
		"description": description,
		"positive": positive,
		"time": 0,
		"day": 0,
	})
	if shared_memories.size() > 50:
		shared_memories.remove_at(0)

func get_tier_modifiers() -> Dictionary:
	return TIER_MODIFIERS.get(current_tier, TIER_MODIFIERS[0])

func get_relationship_description() -> String:
	match current_tier:
		-2: return "despises"
		-1: return "dislikes"
		0: return "doesn't know well"
		1: return "knows casually"
		2: return "considers a friend"
		3: return "is close friends with"
		4: return "trusts completely"
		_: return "has a complicated relationship with"

func to_dict() -> Dictionary:
	return {
		"target_id": target_id, "target_type": target_type, "current_tier": current_tier,
		"affinity": affinity, "trust": trust, "familiarity": familiarity,
		"last_interaction_time": last_interaction_time, "interaction_count": interaction_count,
		"positive_interactions": positive_interactions, "negative_interactions": negative_interactions,
		"shared_memories": shared_memories, "gifts_given": gifts_given, "gifts_received": gifts_received,
		"quests_completed_together": quests_completed_together, "fights_won_together": fights_won_together,
		"trades_completed": trades_completed,
	}

static func from_dict(data: Dictionary) -> NPCRelationship:
	var rel := NPCRelationship.new()
	rel.target_id = data.get("target_id", "")
	rel.target_type = data.get("target_type", "npc")
	rel.current_tier = data.get("current_tier", 0)
	rel.affinity = data.get("affinity", 0.0)
	rel.trust = data.get("trust", 0.0)
	rel.familiarity = data.get("familiarity", 0.0)
	rel.last_interaction_time = data.get("last_interaction_time", 0)
	rel.interaction_count = data.get("interaction_count", 0)
	rel.positive_interactions = data.get("positive_interactions", 0)
	rel.negative_interactions = data.get("negative_interactions", 0)
	rel.shared_memories = data.get("shared_memories", [])
	rel.gifts_given = data.get("gifts_given", [])
	rel.gifts_received = data.get("gifts_received", [])
	rel.quests_completed_together = data.get("quests_completed_together", 0)
	rel.fights_won_together = data.get("fights_won_together", 0)
	rel.trades_completed = data.get("trades_completed", 0)
	return rel