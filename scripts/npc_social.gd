class_name NPCSocial extends Node

## Social component for NPCs.
##
## NPCs periodically look for other NPCs nearby and start a conversation.
## Dialogue lines are generated offline by LocalLLM (NobodyWho + Qwen3 0.6B),
## with small hand-written fallbacks so the world still feels alive while the
## model is loading or unavailable.

signal social_interaction_started(participant_a: Node, participant_b: Node, interaction_type: String)
signal social_interaction_ended(participant_a: Node, participant_b: Node, interaction_type: String, outcome: String)
signal relationship_changed(target_id: String, old_tier: int, new_tier: int, affinity_change: float)
signal group_formed(group_id: String, members: Array)
signal group_disbanded(group_id: String)
signal rumor_spread(rumor: Dictionary, from_npc: Node, to_npc: Node)
signal dialogue_spoken(speaker: Node, text: String, interaction_type: String)
signal show_bubble(text: String)

## Unique voice data per NPC - tone keywords + vocabulary (NO full sentences to copy)
const NPC_VOICES: Dictionary = {
	"John": {"tone": "practical, weathered, brief", "words": "crops, rain, harvest, soil, back, hoe"},
	"Elara": {"tone": "earnest, organic, nurturing", "words": "compost, marigold, beetle, tomato, seed, soil"},
	"Tomas": {"tone": "slow, deliberate, veteran", "words": "harvest, winter, young, back, season, patience"},
	"Sarah": {"tone": "gentle, quiet, observant", "words": "hive, bee, honey, royal jelly, calm, pollen"},
	"Kaia": {"tone": "blunt, gruff, warm", "words": "forge, ingot, hammer, steel, iron, blade"},
	"Marcus": {"tone": "precise, pattern-focused, meticulous", "words": "loom, tension, thread, silk, pattern, weave"},
	"Elena": {"tone": "patient, grounded, fiery", "words": "kiln, clay, glaze, cone, copper, fire"},
	"Finn": {"tone": "practical, builder, exact", "words": "joint, oak, rib, boat, chisel, joint"},
	"Lydia": {"tone": "sharp, no-nonsense, trader", "words": "flour, shipment, spice, price, margin, caravan"},
	"Omar": {"tone": "mysterious, distant, exotic", "words": "caravan, saffron, silk, route, south, danger"},
	"Mira": {"tone": "cryptic, cheerful, precise", "words": "brew, root, simmer, tincture, tonic, moonwater"},
	"Brother Thomas": {"tone": "slow, thoughtful, faithful", "words": "patience, season, charity, listening, duty, turn"},
	"Zara": {"tone": "vague, prophetic, ominous", "words": "star, align, omen, well, copper, sign"},
	"Orin": {"tone": "salty, weathered, humorous", "words": "tide, net, storm, knee, silverfin, current"},
	"Marina": {"tone": "practical, direct, observant", "words": "current, point, silverfin, run, net, catch"},
	"Henrik": {"tone": "quiet, observant, tracker", "words": "trail, deer, wolf, north, pack, dawn"},
	"Elsa": {"tone": "whimsical, knowledgeable, forest", "words": "chanterelle, oak, ghost fungus, hollow, mushroom"},
	"Captain Vex": {"tone": "blunt, impatient, strict", "words": "treeline, patrol, ration, order, perimeter, stripe"},
	"Sergeant Briga": {"tone": "dry, duty-focused, sardonic", "words": "patrol, captain, mood, quiet, shift, bell"},
	"Corporal Tonn": {"tone": "eager, nervous, professional", "words": "shift, bell, track, mine, report, eager"},
	"Elder Thom": {"tone": "ancient, cyclical, wise", "words": "winter, island, young, back, season, mild"},
	"Professor Arwyn": {"tone": "precise, academic, historical", "words": "record, chart, coast, translate, century, slow"},
	"Scribe Elin": {"tone": "anxious, distracted, bookish", "words": "ink, ledger, quill, misfile, grain, tax, careful"},
	"Pip": {"tone": "excitable, simple, curious", "words": "oak, climb, dock, race, crab, tide pool"},
	"Tiko": {"tone": "curious, secretive, quiet", "words": "crab, tide pool, secret, cave, mara, whisper"},
	"Mara": {"tone": "dreamy, poetic, oceanic", "words": "ship, light, ocean, desert, sail, horizon"},
	"Rook": {"tone": "sarcastic, teasing, smug", "words": "crate, boot, coin, hide, half, blow"},
	"Viktor": {"tone": "competitive, intense, challenging", "words": "bet, first, best, keep up, old, timer"},
	"Serafina": {"tone": "sharp, competitive, biting", "words": "glaze, fair, clay, wall, thin, beat"},
	"Captain Reef": {"tone": "grizzled, tall-tale, seaworthy", "words": "whale, ship, island, ghost, chart, sank"},
	"Chef Bonnie": {"tone": "warm, loud, food-obsessed", "words": "stew, hearth, spice, hungry, fish, shack, fresh"},
	"Grundy": {"tone": "cynical, warning, deep", "words": "gas, level, deep, wall, breathe, dark, vein"},
	"Plex": {"tone": "technical, exact, precise", "words": "pressure, valve, gear, ratio, fraction, steam"},
}

@export var interaction_range: float = 300.0
@export var conversation_chance: float = 0.12
@export var trade_chance: float = 0.08
@export var max_conversation_duration: float = 45.0
@export var social_check_interval: float = 14.0
@export var conversation_cooldown: float = 60.0
@export var max_lines_per_conversation: int = 3
@export var use_local_ai: bool = true

var social_groups: Dictionary = {}
var pending_interactions: Array = []
var interaction_history: Array = []

var npc_memory: NPCMemory
var npc_relationships: Dictionary = {}
var current_interaction: Dictionary = {}
var interaction_timer: float = 0.0
var social_check_timer: float = 0.0
var cooldown_timer: float = 0.0

var local_llm: Node
var _npc: Node
var _rng: RandomNumberGenerator

## Fallback lines already used recently, shared by every NPC on the island.
static var _recent_fallbacks: Array[String] = []
const MAX_RECENT_FALLBACKS: int = 24

func _ready() -> void:
	_npc = get_parent()
	if _npc == null:
		push_error("NPCSocial must be a child of an NPC body")
		return

	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	var mem = _npc.get("npc_memory")
	if mem is NPCMemory:
		npc_memory = mem

	local_llm = get_node_or_null("/root/LocalLLM")

	# Spread the first social check so every NPC does not talk on the same frame.
	social_check_timer = _rng.randf_range(0.0, social_check_interval)
	_initialize_relationships()

func _physics_process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)

	social_check_timer += delta
	if social_check_timer >= social_check_interval:
		social_check_timer = 0.0
		_check_social_opportunities()

func _initialize_relationships() -> void:
	if npc_memory == null:
		return
	for entity_id in npc_memory.known_entities:
		if not npc_relationships.has(entity_id):
			var rel := NPCRelationship.new()
			rel.target_id = str(entity_id)
			rel.target_type = "npc"
			var known: Dictionary = npc_memory.known_entities[entity_id]
			var times_met: int = int(known.get("times_met", 1))
			rel.familiarity = minf(100.0, float(times_met) * 5.0)
			npc_relationships[entity_id] = rel

func _check_social_opportunities() -> void:
	if not current_interaction.is_empty():
		return
	if cooldown_timer > 0.0:
		return
	if _get_prop(_npc, "dialogue_running", false):
		return
	if str(_get_prop(_npc, "behavior_state", "")) == "sleep":
		return

	# Do not pile new conversations onto a busy local model.
	if local_llm != null and local_llm.has_method("is_backlogged") and local_llm.is_backlogged():
		return

	var nearby: Array = _get_nearby_npcs()
	for other in nearby:
		if not is_instance_valid(other):
			continue
		if other == _npc:
			continue
		var other_social: Node = other.get_node_or_null("NPCSocial")
		if other_social == null:
			continue
		if not other_social.current_interaction.is_empty():
			continue
		if other_social.cooldown_timer > 0.0:
			continue
		if _get_prop(other, "dialogue_running", false):
			continue
		if str(_get_prop(other, "behavior_state", "")) == "sleep":
			continue

		var other_id: String = str(other.call("get_unique_npc_id"))
		var rel: NPCRelationship = get_relationship(other_id)
		if _should_initiate_interaction(other, rel):
			var interaction_type: String = _choose_interaction_type(other, rel)
			_initiate_interaction(other, interaction_type)
			return

func _get_nearby_npcs() -> Array:
	var result: Array = []
	var tree := get_tree()
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("NPC"):
		if not is_instance_valid(node) or node == _npc:
			continue
		if not node.has_method("get_unique_npc_id"):
			continue
		if _npc.global_position.distance_to(node.global_position) <= interaction_range:
			result.append(node)
	return result

func _get_prop(node: Node, prop: String, default: Variant) -> Variant:
	if node != null and prop in node:
		return node.get(prop)
	return default

func _should_initiate_interaction(other_npc: Node, relationship: NPCRelationship) -> bool:
	if _get_prop(_npc, "dialogue_running", false):
		return false
	if _get_prop(other_npc, "dialogue_running", false):
		return false

	var chance: float = conversation_chance
	chance *= relationship.get_tier_modifiers().get("social_chance", 1.0)

	var biodata = _npc.get("biodata")
	if biodata != null:
		var personality: String = str(biodata.personality).to_lower()
		if personality.contains("social") or personality.contains("friendly"):
			chance *= 1.35
		elif personality.contains("shy") or personality.contains("loner"):
			chance *= 0.6

	return _rng.randf() < clampf(chance, 0.0, 1.0)

func _choose_interaction_type(other_npc: Node, relationship: NPCRelationship) -> String:
	var tier: int = relationship.current_tier
	var my_name: String = _npc_display_name(_npc)
	var their_name: String = _npc_display_name(other_npc)
	var my_biodata = _npc.get("biodata")
	var my_personality: String = str(my_biodata.personality).to_lower() if my_biodata else ""
	var my_role: String = ""
	if my_biodata != null:
		# Use skill_affinities to determine role
		var skills: Dictionary = my_biodata.skill_affinities
		var max_skill: String = ""
		var max_val: float = 0.0
		for k in skills:
			if skills[k] > max_val:
				max_val = skills[k]
				max_skill = k
		my_role = max_skill

	# Build dynamic weight pool based on context
	var weights: Dictionary = {"chat": 0.60}
	
	# Relationship-based
	if tier <= -1:
		weights = {"chat": 0.30, "insult": 0.25, "compete": 0.20, "fight": 0.15, "share_rumor": 0.10}
	elif tier >= 3:
		weights = {"chat": 0.40, "gift": 0.15, "cooperate": 0.15, "share_rumor": 0.15, "flirt": 0.10, "compete": 0.05}
	
	# Personality/role modifiers
	if "merchant" in my_personality or "trader" in my_role:
		weights["trade"] = float(weights.get("trade", 0.0)) + 0.15
	if "gossip" in my_personality:
		weights["share_rumor"] = float(weights.get("share_rumor", 0.0)) + 0.15
	if "competitive" in my_personality or "rival" in my_role:
		weights["compete"] = float(weights.get("compete", 0.0)) + 0.15
	if "generous" in my_personality or my_personality.contains("kind"):
		weights["gift"] = float(weights.get("gift", 0.0)) + 0.10
	
	# Situation-specific triggers
	var activity: String = str(_get_prop(_npc, "current_schedule_activity", "")).to_lower()
	if "work" in activity:
		weights["cooperate"] = float(weights.get("cooperate", 0.0)) + 0.10
		weights["complain"] = float(weights.get("complain", 0.0)) + 0.10  # New: complain about work
	if "socialize" in activity:
		weights["share_rumor"] = float(weights.get("share_rumor", 0.0)) + 0.15
		weights["flirt"] = float(weights.get("flirt", 0.0)) + 0.05
	
	# Add dynamic interaction types
	if not weights.has("complain"):
		weights["complain"] = 0.05
	if not weights.has("warn"):
		weights["warn"] = 0.03
	if not weights.has("tease"):
		weights["tease"] = 0.05
	if not weights.has("ask_advice"):
		weights["ask_advice"] = 0.04
	
	var total: float = 0.0
	for value in weights.values():
		total += float(value)
	var roll: float = _rng.randf() * total
	var cumulative: float = 0.0
	for key in weights:
		cumulative += float(weights[key])
		if roll <= cumulative:
			return str(key)
	return "chat"

func _initiate_interaction(other_npc: Node, interaction_type: String) -> void:
	var other_social: Node = other_npc.get_node_or_null("NPCSocial")
	if other_social == null:
		return
	if not other_social.call("_accept_interaction", _npc, interaction_type):
		return

	# Reset shared LLM chat history to prevent cross-NPC bleeding
	if local_llm != null and local_llm.has_method("reset_chat_history"):
		local_llm.reset_chat_history()

	var start_time: float = Time.get_ticks_msec() / 1000.0
	current_interaction = {
		"target": other_npc,
		"type": interaction_type,
		"start_time": start_time,
		"stage": "active",
		"lines": 0,
		"max_lines": max_lines_per_conversation,
		"history": [],
	}
	other_social.current_interaction["stage"] = "active"

	_pause_ai_for_interaction()
	other_social.call("_pause_ai_for_interaction")
	face_target(other_npc)
	other_social.call("face_target", _npc)

	social_interaction_started.emit(_npc, other_npc, interaction_type)

	if interaction_type == "chat":
		_run_chat(other_npc, other_social)
	else:
		_execute_interaction(interaction_type)

func _accept_interaction(initiator: Node, interaction_type: String) -> bool:
	if not current_interaction.is_empty():
		return false
	if cooldown_timer > 0.0:
		return false
	if _get_prop(_npc, "dialogue_running", false):
		return false
	if str(_get_prop(_npc, "behavior_state", "")) == "sleep":
		return false

	var rel: NPCRelationship = get_relationship(str(initiator.call("get_unique_npc_id")))
	if rel.current_tier <= -1 and interaction_type == "chat" and _rng.randf() > 0.35:
		return false

	# Reserve immediately so two NPCs cannot both start a chat with each other.
	current_interaction = {
		"target": initiator,
		"type": interaction_type,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"stage": "accepted",
		"lines": 0,
		"max_lines": max_lines_per_conversation,
		"history": [],
	}
	return true

func _pause_ai_for_interaction() -> void:
	if _npc.has_method("_pause_ai"):
		_npc.call("_pause_ai")
	_npc.set("can_move", false)
	_npc.set("dialogue_running", true)

func _resume_ai_after_interaction() -> void:
	if _npc.has_method("_resume_ai"):
		_npc.call("_resume_ai")
	_npc.set("can_move", true)
	_npc.set("dialogue_running", false)

func _run_chat(other_npc: Node, other_social: Node) -> void:
	var max_lines: int = max_lines_per_conversation
	var last_line: String = ""
	var last_speaker_name: String = ""
	
	for i in range(max_lines):
		if current_interaction.is_empty():
			return
		if not is_instance_valid(other_npc) or not is_instance_valid(_npc):
			return
		if _npc.global_position.distance_to(other_npc.global_position) > interaction_range * 1.8:
			_end_interaction("target_left")
			return

		var speaker: Node = _npc if i % 2 == 0 else other_npc
		var listener: Node = other_npc if i % 2 == 0 else _npc
		var line: String = await _generate_line_for(speaker, listener, last_line, last_speaker_name)
		if current_interaction.is_empty():
			return
		if line.is_empty():
			line = _fallback_line(speaker, listener, i)

		_say_line(speaker, line)
		var history: Array = current_interaction["history"]
		history.append({
			"speaker_id": speaker.get_instance_id(),
			"name": _npc_display_name(speaker),
			"text": line,
		})
		current_interaction["lines"] = i + 1
		
		# Store for next speaker's context
		last_line = line
		last_speaker_name = _npc_display_name(speaker)

		if i < max_lines - 1:
			await _wait(1.0)

	_end_interaction("chat_complete")

func _generate_line_for(speaker: Node, listener: Node, last_line: String = "", last_speaker_name: String = "") -> String:
	if local_llm == null or not use_local_ai:
		return ""
	if local_llm.has_method("is_ready") and not local_llm.is_ready():
		return ""

	var listener_name: String = _npc_display_name(listener)

	var user_prompt: String
	if last_line.is_empty():
		# Opening line: no topic injection, just a direct invitation to speak.
		user_prompt = "%s walks up to you. What do you say?" % listener_name
	else:
		# Reply: show the previous line verbatim and ask for a direct answer.
		var trigger_speaker: String = last_speaker_name if not last_speaker_name.is_empty() else "They"
		user_prompt = "%s: \"%s\"\nYou answer %s:" % [trigger_speaker, last_line, trigger_speaker]

	# No cross-turn history: each line is generated from the persona plus the
	# single line it is answering. Keeps the prompt tiny and prevents earlier
	# conversations from bleeding into the current one.
	var system_prompt: String = _build_system_prompt(speaker, listener)
	var text: String = await local_llm.generate_line(system_prompt, [], user_prompt)
	if text.is_empty():
		return ""
	return text.strip_edges()

func _build_system_prompt(speaker: Node, listener: Node) -> String:
	var speaker_name: String = _npc_display_name(speaker)
	var listener_name: String = _npc_display_name(listener)
	var voice_data: Dictionary = NPC_VOICES.get(speaker_name, {})
	var personality: String = "plain-spoken islander"
	var biodata = speaker.get("biodata")
	if biodata != null and not str(biodata.personality).is_empty():
		personality = str(biodata.personality)

	var tone: String = str(voice_data.get("tone", personality))
	var words: String = str(voice_data.get("words", "work, weather, the day"))

	return (
		"You are %s, talking out loud to %s. Voice: %s. Talk about: %s.\n" +
		"One sentence, under 12 words, first person. Sound casual. No narration, no quotes, no proverbs."
	) % [speaker_name, listener_name, tone, words]

func _npc_display_name(npc: Node) -> String:
	if npc == null:
		return "Someone"
	var value = npc.get("npc_name")
	if value != null and not str(value).is_empty():
		return str(value)
	return str(npc.name)

func _fallback_line(speaker: Node, listener: Node, index: int) -> String:
	var speaker_name: String = _npc_display_name(speaker)
	var listener_name: String = _npc_display_name(listener)
	var biodata = speaker.get("biodata")
	var personality: String = str(biodata.personality).to_lower() if biodata != null else ""
	var role: String = str(NPC_VOICES.get(speaker_name, {}).get("tone", "")).to_lower()
	var activity: String = str(_get_prop(speaker, "current_schedule_activity", "")).to_lower()
	var name_lower := speaker_name.to_lower()

	# Role-specific greetings
	var greetings: Array[String] = [
		"Morning, %s! Fine weather for it." % listener_name,
		"Ah, %s. Good to see you." % listener_name,
		"Hello there, %s." % listener_name,
		"%s! Didn't expect to see you here." % listener_name,
		"Well met, %s." % listener_name,
	]
	# Role-specific additions
	if "farm" in role or "farmer" in name_lower:
		greetings.append("Morning %s. Soil's looking good today." % listener_name)
		greetings.append("%s! Just finished checking the crops." % listener_name)
	elif "smith" in role or "forge" in role or "kaia" in name_lower:
		greetings.append("%s. Forge is running hot today." % listener_name)
		greetings.append("Ah, %s. Just hammered out a new blade." % listener_name)
	elif "herbalist" in role or "alchemist" in role or "mira" in name_lower:
		greetings.append("%s. Brewed a new tonic this morning." % listener_name)
		greetings.append("Morning %s. Herbs are potent today." % listener_name)
	elif "fish" in role or "orin" in name_lower or "marina" in name_lower:
		greetings.append("%s. Tide's turning early." % listener_name)
		greetings.append("Good haul yesterday, %s?" % listener_name)
	elif "merchant" in role or "trader" in role or "lydia" in name_lower or "omar" in name_lower:
		greetings.append("%s. Market's busy today." % listener_name)
		greetings.append("Trade winds favor us, %s." % listener_name)
	elif "guard" in role or "captain" in name_lower or "sergeant" in name_lower:
		greetings.append("%s. All quiet on the perimeter." % listener_name)
		greetings.append("Morning, %s. Patrol was uneventful." % listener_name)
	elif "scholar" in role or "scribe" in role or "elin" in name_lower or "arwyn" in name_lower:
		greetings.append("%s. Found an interesting entry in the logs." % listener_name)
		greetings.append("Ah, %s. Been cataloguing the new arrivals." % listener_name)
	elif "child" in name_lower or "pip" in name_lower or "tiko" in name_lower:
		greetings.append("%s! Look what I found!" % listener_name)
		greetings.append("Hi %s! Wanna play?" % listener_name)
	elif "elder" in name_lower or "thom" in name_lower or "thomas" in name_lower:
		greetings.append("%s. The years treat you well, I hope." % listener_name)
		greetings.append("Morning %s. Old bones know this weather." % listener_name)

	# Contextual replies
	var replies: Array[String] = [
		"It really is. The island feels lively today.",
		"Good to see you too, %s." % speaker_name,
		"Can't complain. Busy day for me.",
		"Have you been down to the market lately?",
		"Same as always. Work, eat, sleep.",
		"The season's turning. Feel it in the air.",
		"Days blur together lately.",
		"Keeping busy keeps the mind sharp.",
	]
	# Role-specific replies
	if "farm" in role:
		replies.append("Crops are coming along. Rain would help.")
		replies.append("Harvest's not far off. Hope for dry weather.")
	elif "smith" in role or "forge" in role:
		replies.append("Iron's been stubborn this week.")
		replies.append("Made a few good pieces. Sold one to the guard.")
	elif "herbalist" in role or "alchemist" in role:
		replies.append("New batch of salves ready. Lavender and comfrey.")
		replies.append("Experimenting with moonwater distillation.")
	elif "fish" in role:
		replies.append("Net's full of silverfin today.")
		replies.append("Current's strange near the rocks.")
	elif "merchant" in role or "trader" in role:
		replies.append("Prices up on grain. Ships delayed.")
		replies.append("Got a shipment of exotic spices coming.")
	elif "guard" in role:
		replies.append("Quiet week. Long may it last.")
		replies.append("Saw tracks near the old mine. Probably nothing.")
	elif "scholar" in role or "scribe" in role:
		replies.append("Found a fragment of the old charter. Fascinating.")
		replies.append("Translating the coastal charts. Slow work.")
	elif "child" in name_lower:
		replies.append("I climbed the big oak yesterday!")
		replies.append("The tide pools have crabs today.")
	elif "elder" in name_lower:
		replies.append("Seen forty winters on this island. This one's mild.")
		replies.append("The young ones have energy. Good for them.")

	var gossip: Array[String] = [
		"Did you hear the merchant ship is due tomorrow?",
		"I saw strange lights near the forest last night.",
		"They say the old mine has reopened.",
		"The mayor's planning a festival for harvest.",
		"Someone found a message in a bottle on the beach.",
		"Old Captain Reef swears he saw a whale in the bay.",
		"The lighthouse keeper's cat had kittens.",
		"Traveler from the mainland brought news of war.",
	]

	if personality.contains("gossip") and index > 0 and _rng.randf() < 0.5:
		return _pick_fallback(gossip)
	if index == 0:
		return _pick_fallback(greetings)
	return _pick_fallback(replies)

## Pick a fallback line that no other NPC has said recently, so offline
## conversations do not repeat the same canned sentence.
func _pick_fallback(candidates: Array) -> String:
	if candidates.is_empty():
		return ""
	var pool: Array = []
	for line in candidates:
		if not _recent_fallbacks.has(line):
			pool.append(line)
	if pool.is_empty():
		pool = candidates.duplicate()
	var chosen: String = str(pool[_rng.randi_range(0, pool.size() - 1)])
	_recent_fallbacks.append(chosen)
	if _recent_fallbacks.size() > MAX_RECENT_FALLBACKS:
		_recent_fallbacks.remove_at(0)
	return chosen

func _say_line(speaker: Node, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var speaker_name: String = _npc_display_name(speaker)
	print("[CONVERSATION] %s: \"%s\"" % [speaker_name, text])

	var speaker_social: Node = speaker.get_node_or_null("NPCSocial")
	if speaker_social != null:
		speaker_social.dialogue_spoken.emit(speaker, text, "chat")
		speaker_social.show_bubble.emit(text)

	if speaker.has_method("_show_speech_bubble"):
		speaker.call("_show_speech_bubble", text)
	if speaker.has_method("play_chat_animation"):
		speaker.call("play_chat_animation")

func _wait(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(seconds).timeout

func _execute_interaction(interaction_type: String) -> void:
	match interaction_type:
		"trade": _start_trade()
		"gift": _start_gift()
		"cooperate": _start_cooperate()
		"compete": _start_compete()
		"fight": _start_fight()
		"flirt": _start_flirt()
		"insult": _start_insult()
		"apologize": _start_apologize()
		"share_rumor": _start_share_rumor()
		"complain": _start_complain()
		"warn": _start_warn()
		"tease": _start_tease()
		"ask_advice": _start_ask_advice()
		_: _end_interaction("unknown")

func _start_trade() -> void:
	var other: Node = current_interaction["target"]
	var trade_openers := [
		"Want to trade? I have a few things to spare.",
		"Got some surplus. Interested in a swap, %s?" % _npc_display_name(other),
		"Looking to move some goods. You buying or selling?",
		"Trade? My stock's fresh today.",
	]
	var trade_replies := [
		"Aye, let's see what you've got.",
		"Depends on the price. Show me.",
		"Always room for a fair deal.",
		"Let's have a look then.",
	]
	_say_line(_npc, _pick_fallback(trade_openers))
	_say_line(other, _pick_fallback(trade_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 3.0, "traded")
	_end_interaction("trade_complete")

func _start_gift() -> void:
	var other: Node = current_interaction["target"]
	var gift_openers := [
		"Here, take this. I thought of you.",
		"Made this for you. Hope you like it.",
		"Saw this and thought of you, %s." % _npc_display_name(other),
		"A small thing. For you.",
	]
	var gift_replies := [
		"That's kind of you. Thank you!",
		"Oh! You didn't have to. But thank you.",
		"How thoughtful. I appreciate it.",
		"Well now. That's a surprise. Thanks!",
	]
	_say_line(_npc, _pick_fallback(gift_openers))
	_say_line(other, _pick_fallback(gift_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 8.0, "gave a gift")
	_end_interaction("gift_given")

func _start_cooperate() -> void:
	var other: Node = current_interaction["target"]
	var coop_openers := [
		"Need a hand with that? We'll finish faster together.",
		"Two pairs of hands beat one. Want help?",
		"Looks like a big job. Mind if I pitch in?",
		"Working alone's slow. Let me help.",
	]
	var coop_replies := [
		"Much appreciated. Let's get to it.",
		"Don't mind at all. Thanks.",
		"Could use the company anyway.",
		"Alright then. Let's make quick work of it.",
	]
	_say_line(_npc, _pick_fallback(coop_openers))
	_say_line(other, _pick_fallback(coop_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 5.0, "worked together")
	_end_interaction("cooperation_complete")

func _start_compete() -> void:
	var other: Node = current_interaction["target"]
	var comp_openers := [
		"Bet I can finish my chores before you finish yours.",
		"Race you to the market and back?",
		"Think you can chop more wood than me?",
		"First one done buys the drinks.",
	]
	var comp_replies := [
		"You're on. Loser buys the cider.",
		"Ha! You'll regret that challenge.",
		"Deal. But don't cry when you lose.",
		"Confident. I like that. Let's go.",
	]
	_say_line(_npc, _pick_fallback(comp_openers))
	_say_line(other, _pick_fallback(comp_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 2.0, "friendly competition")
	_end_interaction("competition_complete")

func _start_fight() -> void:
	var other: Node = current_interaction["target"]
	var fight_openers := [
		"I've had just about enough of you.",
		"Watch your tongue, %s." % _npc_display_name(other),
		"That's the last straw.",
		"You want to say that again?",
	]
	var fight_replies := [
		"Then say it to my face!",
		"Oh, I'm shaking. Really.",
		"Big words. Back them up.",
		"Calm down. No need for this.",
	]
	_say_line(_npc, _pick_fallback(fight_openers))
	_say_line(other, _pick_fallback(fight_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), -15.0, "got into a fight")
	if npc_memory != null:
		npc_memory.add_grudge(str(other.call("get_unique_npc_id")), "Got into a fight", 3.0)
	_end_interaction("fight_over")

func _start_flirt() -> void:
	var other: Node = current_interaction["target"]
	var flirt_openers := [
		"You look nice today. Been doing something different?",
		"That color suits you, %s." % _npc_display_name(other),
		"Someone's looking sharp today.",
		"New outfit? It works.",
	]
	var flirt_replies := [
		"Oh, stop it. But thank you.",
		"Flattery gets you everywhere.",
		"You're smooth. I'll give you that.",
		"Careful, people might talk.",
	]
	_say_line(_npc, _pick_fallback(flirt_openers))
	_say_line(other, _pick_fallback(flirt_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 6.0, "flirted")
	_end_interaction("flirt_complete")

func _start_insult() -> void:
	var other: Node = current_interaction["target"]
	var insult_openers := [
		"You smell like compost.",
		"Your brain's as dull as your blade.",
		"Even the chickens avoid you.",
		"Did a goat teach you manners?",
	]
	var insult_replies := [
		"And you sound like a broken wheelbarrow.",
		"Coming from you, that's a compliment.",
		"At least I don't talk to my crops.",
		"Watch it. Your ego's showing.",
	]
	_say_line(_npc, _pick_fallback(insult_openers))
	_say_line(other, _pick_fallback(insult_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), -8.0, "insulted")
	_end_interaction("insult_complete")

func _start_apologize() -> void:
	var other: Node = current_interaction["target"]
	var apology_openers := [
		"Sorry about earlier. I didn't mean it.",
		"I was out of line. My apologies.",
		"Let's start over. I regret what I said.",
		"Forgive me? I spoke without thinking.",
	]
	var apology_replies := [
		"It's forgotten. Let's start over.",
		"Water under the bridge. Happens to the best of us.",
		"Accepted. Don't make a habit of it.",
		"Alright. But watch yourself next time.",
	]
	_say_line(_npc, _pick_fallback(apology_openers))
	_say_line(other, _pick_fallback(apology_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 10.0, "apologized")
	if npc_memory != null:
		npc_memory.resolve_grudge(str(other.call("get_unique_npc_id")))
	_end_interaction("apology_complete")

func _start_share_rumor() -> void:
	var other: Node = current_interaction["target"]
	var rumors: Array[String] = [
		"The merchant ship arrives tomorrow.",
		"Strange lights were seen in the forest last night.",
		"The old mine has reopened.",
		"The mayor is planning a festival.",
		"Someone found buried treasure near the lighthouse.",
		"Captain Reef swears he saw a sea serpent.",
		"The lighthouse keeper found a message in a bottle.",
		"A traveling bard is performing at the tavern tonight.",
		"The well in the square has turned sweet.",
		"Old Thom says the stars are aligning oddly.",
	]
	var rumor: String = _pick_fallback(rumors)
	_say_line(_npc, "Hey, did you hear? %s" % rumor)
	_say_line(other, "Really? I hadn't heard that.")
	var other_social: Node = other.get_node_or_null("NPCSocial")
	if other_social != null and other_social.has_method("hear_rumor"):
		other_social.hear_rumor(rumor, str(_npc.call("get_unique_npc_id")))
	rumor_spread.emit({"content": rumor}, _npc, other)
	modify_relationship(str(other.call("get_unique_npc_id")), 3.0, "shared a rumor")
	_end_interaction("rumor_shared")

func _start_complain() -> void:
	var other: Node = current_interaction["target"]
	var complain_openers := [
		"Flour shipment's late again. Third time this month.",
		"My back's killing me from this grind.",
		"Rain's ruining the harvest. Again.",
		"Prices jumped but wages didn't.",
		"Tools keep breaking. Can't get good steel.",
	]
	var complain_replies := [
		"Tell me about it. Same here.",
		"At least the ale's still cheap.",
		"Could be worse. Could be taxes.",
		"Season'll turn. Always does.",
		"Want a drink after shift?",
	]
	_say_line(_npc, _pick_fallback(complain_openers))
	_say_line(other, _pick_fallback(complain_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 2.0, "commiserated")
	_end_interaction("complain_complete")

func _start_warn() -> void:
	var other: Node = current_interaction["target"]
	var warn_openers := [
		"Watch the north path. Something's moving there.",
		"Don't take the shortcut through the ravine.",
		"Old mine's unstable. Heard cracking yesterday.",
		"Stranger asking about the lighthouse. Bad news.",
		"Tide's turning early. Get your nets in.",
	]
	var warn_replies := [
		"Thanks for the heads up.",
		"Good looking out. I'll avoid it.",
		"Heard similar. Appreciate it.",
		"Noted. Stay safe yourself.",
	]
	_say_line(_npc, _pick_fallback(warn_openers))
	_say_line(other, _pick_fallback(warn_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 4.0, "warned")
	_end_interaction("warn_complete")

func _start_tease() -> void:
	var other: Node = current_interaction["target"]
	var tease_openers := [
		"Bet you can't beat my time today.",
		"Someone's moving slow this morning.",
		"Nice boots. Borrow them from a giant?",
		"Still sleeping on the job, %s?" % _npc_display_name(other),
		"Your shadow's working harder than you.",
	]
	var tease_replies := [
		"Ha. Your time's the one to beat.",
		"At least I show up.",
		"Fit me fine. Your eyesight going?",
		"Only when you're watching.",
		"My shadow's smarter than your mouth.",
	]
	_say_line(_npc, _pick_fallback(tease_openers))
	_say_line(other, _pick_fallback(tease_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 1.0, "teased")
	_end_interaction("tease_complete")

func _start_ask_advice() -> void:
	var other: Node = current_interaction["target"]
	var advice_openers := [
		"Best bait for silverfin this season?",
		"How deep you planting the tubers?",
		"Seen any good clay near the river?",
		"Best way to temper a blade this thin?",
		"Your herb mix for the cough work?",
	]
	var advice_replies := [
		"Worm and shine. Dawn or dusk.",
		"Two knuckles deep. Mulch heavy.",
		"North bank. Gray-blue streak.",
		"Quench in brine, not water.",
		"Thyme, honey, lemon. Steep long.",
	]
	_say_line(_npc, _pick_fallback(advice_openers))
	_say_line(other, _pick_fallback(advice_replies))
	modify_relationship(str(other.call("get_unique_npc_id")), 3.0, "asked advice")
	_end_interaction("advice_complete")

func _end_interaction(outcome: String) -> void:
	if current_interaction.is_empty():
		return

	var target = current_interaction.get("target")
	var interaction_type: String = str(current_interaction.get("type", "chat"))
	var start_time: float = float(current_interaction.get("start_time", 0.0))
	var duration: float = Time.get_ticks_msec() / 1000.0 - start_time

	if is_instance_valid(target):
		var target_id: String = str(target.call("get_unique_npc_id"))
		interaction_history.append({
			"target_id": target_id,
			"type": interaction_type,
			"outcome": outcome,
			"duration": duration,
		})
		if interaction_history.size() > 100:
			interaction_history.remove_at(0)

		if npc_memory != null:
			npc_memory.add_event_memory(
				"conversation",
				"Talked with %s (%s)" % [_npc_display_name(target), outcome],
				[target_id],
				"",
				0.1
			)

	current_interaction = {}
	interaction_timer = 0.0
	cooldown_timer = conversation_cooldown
	_resume_ai_after_interaction()

	if is_instance_valid(target):
		var target_social: Node = target.get_node_or_null("NPCSocial")
		if target_social != null:
			target_social.current_interaction = {}
			target_social.cooldown_timer = target_social.conversation_cooldown
			target_social.call("_resume_ai_after_interaction")
		social_interaction_ended.emit(_npc, target, interaction_type, outcome)

## Relationships

func get_relationship(entity_id: String) -> NPCRelationship:
	if not npc_relationships.has(entity_id):
		var rel := NPCRelationship.new()
		rel.target_id = entity_id
		rel.target_type = "npc"
		npc_relationships[entity_id] = rel
	return npc_relationships[entity_id]

func modify_relationship(entity_id: String, affinity_change: float, reason: String = "", target_type: String = "npc") -> void:
	var rel: NPCRelationship = get_relationship(entity_id)
	var old_tier: int = rel.current_tier
	rel.modify_affinity(affinity_change, reason)
	rel.modify_familiarity(2.0)

	if npc_memory != null:
		if not npc_memory.known_entities.has(entity_id):
			npc_memory.record_meeting(entity_id, target_type, entity_id)
		npc_memory.known_entities[entity_id]["familiarity"] = rel.familiarity
		if not reason.is_empty():
			npc_memory.add_event_memory(
				"relationship_change",
				"%s with %s (%+.1f)" % [reason, entity_id, affinity_change],
				[entity_id],
				"",
				affinity_change / 100.0
			)

	relationship_changed.emit(entity_id, old_tier, rel.current_tier, affinity_change)

func get_relationship_tier(entity_id: String) -> int:
	return get_relationship(entity_id).current_tier

func get_affinity(entity_id: String) -> float:
	return get_relationship(entity_id).affinity

func get_relationship_modifiers(entity_id: String) -> Dictionary:
	return get_relationship(entity_id).get_tier_modifiers()

## Groups

func form_social_group(group_id: String, group_type: String, members: Array, leader: Node = null) -> void:
	if social_groups.has(group_id):
		return
	var group_leader: Node = leader if leader != null else (members[0] if not members.is_empty() else null)
	social_groups[group_id] = {
		"members": members,
		"type": group_type,
		"leader": group_leader,
		"formed_time": 0,
		"formed_day": 0,
	}
	group_formed.emit(group_id, members)

func leave_social_group(group_id: String) -> void:
	if not social_groups.has(group_id):
		return
	var group: Dictionary = social_groups[group_id]
	var members: Array = group["members"]
	members.erase(_npc)
	if members.size() <= 1:
		disband_social_group(group_id)

func disband_social_group(group_id: String) -> void:
	if not social_groups.has(group_id):
		return
	social_groups.erase(group_id)
	group_disbanded.emit(group_id)

func _on_group_joined(_group_id: String, _group_type: String) -> void:
	pass

func _on_group_member_left(_group_id: String, _member: Node) -> void:
	pass

func _on_group_disbanded(_group_id: String) -> void:
	pass

## Memory / rumour bridge

func hear_rumor(content: String, source: String, believed: bool = true) -> void:
	if npc_memory != null:
		npc_memory.hear_rumor(content, source, believed)

## Inventory / body helpers

func get_unique_npc_id() -> String:
	if _npc != null and _npc.has_method("get_unique_npc_id"):
		return str(_npc.call("get_unique_npc_id"))
	return "npc_%d" % (get_instance_id())

func _get_inventory_items() -> Array:
	if _npc != null and _npc.has_method("get_inventory_items"):
		return _npc.call("get_inventory_items")
	return []

func _get_item_value(item: String) -> int:
	if _npc != null and _npc.has_method("get_item_value"):
		return int(_npc.call("get_item_value", item))
	return 10

func _add_inventory_item(item: String) -> void:
	if _npc != null and _npc.has_method("add_inventory_item"):
		_npc.call("add_inventory_item", item)

func _remove_inventory_item(item: String) -> void:
	if _npc != null and _npc.has_method("remove_inventory_item"):
		_npc.call("remove_inventory_item", item)

func face_target(target: Node) -> void:
	if _npc != null and _npc.has_method("face_target"):
		_npc.call("face_target", target)

func take_damage(amount: int) -> void:
	if _npc != null and _npc.has_method("take_damage"):
		_npc.call("take_damage", amount)

## Persistence

func get_social_save_data() -> Dictionary:
	var rel_data: Dictionary = {}
	for id in npc_relationships:
		rel_data[id] = npc_relationships[id].to_dict()

	var group_data: Dictionary = {}
	for gid in social_groups:
		var group: Dictionary = social_groups[gid]
		var member_ids: Array = []
		for member in group["members"]:
			if is_instance_valid(member):
				member_ids.append(str(member.call("get_unique_npc_id")))
		group_data[gid] = {
			"member_ids": member_ids,
			"type": group["type"],
			"formed_time": group["formed_time"],
			"formed_day": group["formed_day"],
		}

	return {
		"relationships": rel_data,
		"groups": group_data,
		"interaction_history": interaction_history,
	}

func load_save_data(data: Dictionary) -> void:
	var rels: Dictionary = data.get("relationships", {})
	for id in rels:
		npc_relationships[id] = NPCRelationship.from_dict(rels[id])
	set("_pending_groups", data.get("groups", {}))
	interaction_history = data.get("interaction_history", [])

func load_social_save_data(data: Dictionary) -> void:
	load_save_data(data)

func resolve_pending_groups(all_npcs: Array) -> void:
	var pending: Dictionary = get("_pending_groups")
	if not (pending is Dictionary):
		return
	for gid in pending:
		var gdata: Dictionary = pending[gid]
		var members: Array = []
		var member_ids: Array = gdata.get("member_ids", [])
		for mid in member_ids:
			for npc in all_npcs:
				if is_instance_valid(npc) and str(npc.call("get_unique_npc_id")) == str(mid):
					members.append(npc)
					break
		if not members.is_empty():
			form_social_group(gid, str(gdata.get("type", "cooperation")), members)
	set("_pending_groups", {})
