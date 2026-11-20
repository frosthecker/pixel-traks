class_name NPCEnhanced extends CharacterBody2D

## Enhanced NPC Base Class
## Integrates: Relationships, Memory, Social Interactions, Pathfinding, Schedules, AI Dialogue

# Core components
const NPCResourceType = preload("res://resources/npc_resource.gd")
const NPCBiodataType = preload("res://resources/npc_biodata.gd")
const NPCRelationshipType = preload("res://resources/npc_relationship.gd")
const NPCMemoryType = preload("res://resources/npc_memory.gd")
const NPCNavigationType = preload("res://scripts/npc_navigation.gd")
const NPCSocialType = preload("res://scripts/npc_social.gd")

## Movement & Animation
var direction: Vector2 = Vector2.ZERO
var last_direction: Vector2 = Vector2.DOWN
@export var base_speed: float = 25.0
var can_move: bool = true

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_tree: AnimationTree = $PlayerAnimation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@onready var bt_player: Node = $BTPlayer

## NPC Data
@export_category("NPC Identity")
@export var npc_id: String = ""              # Unique persistent ID
@export var npc_name: String = ""             # Display name
@export var texture: Texture2D
@export_file("*.dch") var dialogue_character: String = ""
@export_file("*.dtl") var dialogue_timeline: String = ""
@export_file("*.dtl") var intro_timeline: String = ""
@export var random_timelines: Array[String] = []
@export var dialogue_distance: float = 48.0
@export var key_prompt_delay: float = 5.0
@export var biodata: NPCBiodataType

@export_category("AI Dialogue")
@export var use_groq_ai: bool = true
@export var groq_character_id: String = ""
@export var enable_interactive_choices: bool = true

@export_category("Behavior")
@export_enum("idle", "wander", "follow_player", "follow_npc", "chase", "talk", "work", "flee", "sleep", "socialize", "trade", "travel")
var behavior_state: String = "wander"

@export_category("Farmer/Worker")
@export var worker_seed: Enum.Seed = Enum.Seed.WHEAT
@export var work_efficiency: float = 1.0

## Components (initialized in _ready)
var npc_data: NPCResourceType
var npc_memory: NPCMemoryType
var npc_navigation: NPCNavigationType
var npc_social: NPCSocialType
var relationships: Dictionary = {}  # target_id -> NPCRelationship

## Runtime State
var player_in_range: bool = false
var player: Node2D
var dialogue_running: bool = false
var is_requesting_ai: bool = false
var conversation_history: Array = []
var startup_dialogue_running: bool = false
var startup_dialogue_stage: int = 0
var dialogic: Node
var previous_behavior_state: String = "wander"
var worker_work_phase: int = 0
var current_schedule_activity: String = ""
var worker_target_position: Vector2 = Vector2.INF
var worker_target_tool: Enum.Tool = Enum.Tool.AXE
var current_path: Array[Vector2] = []
var path_target: Vector2 = Vector2.INF
var is_following_path: bool = false
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO

@onready var emoticon_player: AnimationPlayer = get_node_or_null("emoticonAnimation/AnimationPlayer")
@onready var key_ui: AnimatedSprite2D = $Key_UI/key_UI
@onready var key_timer: Timer = $Key_UI/Timer

## Signals
signal npc_interacted(interactor: Node2D)
signal behavior_changed(old_state: String, new_state: String)
signal relationship_changed(target_id: String, tier: int, affinity: float)
signal memory_updated(memory_type: String)
signal path_completed
signal path_failed(target: Vector2)
signal social_interaction_started(target: Node, interaction_type: String)
signal social_interaction_ended(target: Node, interaction_type: String, outcome: String)
signal schedule_changed(activity: String)

func _ready() -> void:
	animation_tree.active = true
	
	# Generate unique NPC ID if not set
	if npc_id.is_empty():
		npc_id = "npc_%s_%d" % [npc_name.to_lower().replace(" ", "_"), get_instance_id()]
	
	# Build NPCResource from inspector values
	npc_data = NPCResourceType.new()
	npc_data.texture = texture
	npc_data.dialogue_character = dialogue_character
	npc_data.dialogue_timeline = dialogue_timeline
	npc_data.intro_timeline = intro_timeline
	npc_data.random_timelines = random_timelines
	npc_data.dialogue_distance = dialogue_distance
	npc_data.key_prompt_delay = key_prompt_delay
	npc_data.biodata = biodata
	
	sprite_2d.texture = npc_data.texture
	if npc_data.biodata:
		base_speed = npc_data.biodata.movement_speed
	dialogue_distance = npc_data.dialogue_distance
	key_prompt_delay = npc_data.key_prompt_delay
	dialogue_timeline = npc_data.dialogue_timeline
	intro_timeline = npc_data.intro_timeline
	random_timelines = npc_data.random_timelines
	
	# Setup Groq character ID
	if groq_character_id.is_empty():
		groq_character_id = npc_name if not npc_name.is_empty() else name
	
	# Initialize components
	_initialize_components()
	
	# UI setup
	key_timer.one_shot = true
	key_timer.wait_time = key_prompt_delay
	key_ui.hide()
	
	# Find player
	_find_player()
	
	# Dialogic connection
	dialogic = get_node_or_null("/root/Dialogic")
	if dialogic:
		if not dialogic.is_connected("timeline_ended", Callable(self, "_on_dialogue_ended")):
			dialogic.connect("timeline_ended", Callable(self, "_on_dialogue_ended"))
		if not dialogic.is_connected("signal_event", Callable(self, "_on_dialogic_signal")):
			dialogic.connect("signal_event", Callable(self, "_on_dialogic_signal"))
	
	# World time connection
	var clock := get_node_or_null("/root/WorldTime")
	if clock and clock.has_signal("time_changed") and not clock.time_changed.is_connected(_on_world_time_changed):
		clock.time_changed.connect(_on_world_time_changed)
	
	# Load saved data if available
	_load_persistent_data()
	
	# Startup dialogue
	_update_schedule_state()
	var save_game := get_node_or_null("/root/SaveGame")
	if dialogic and not intro_timeline.is_empty() and (save_game == null or not save_game.has_save()):
		call_deferred("_play_startup_dialogue")

func _initialize_components() -> void:
	# Memory component (Resource, not a Node)
	if not npc_memory:
		npc_memory = NPCMemoryType.new()
		npc_memory.npc_id = npc_id
	
	# Navigation component
	npc_navigation = get_node_or_null("NPCNavigation")
	if npc_navigation == null:
		npc_navigation = NPCNavigationType.new()
		npc_navigation.name = "NPCNavigation"
		add_child(npc_navigation)
		npc_navigation.owner = self
		# Connect signals
		npc_navigation.path_completed.connect(_on_path_completed)
		npc_navigation.path_blocked.connect(_on_path_blocked)
		npc_navigation.path_recalculated.connect(_on_path_recalculated)
	
	# Social component
	npc_social = get_node_or_null("NPCSocial")
	if npc_social == null:
		npc_social = NPCSocialType.new()
		npc_social.name = "NPCSocial"
		add_child(npc_social)
		npc_social.owner = self
		# Connect signals
		npc_social.social_interaction_started.connect(_on_social_interaction_started)
		npc_social.social_interaction_ended.connect(_on_social_interaction_ended)
		npc_social.relationship_changed.connect(_on_relationship_changed)
		npc_social.group_formed.connect(_on_group_formed)
		npc_social.rumor_spread.connect(_on_rumor_spread)
	
	last_position = global_position

func _physics_process(delta: float) -> void:
	# Handle movement lock from dialogue/interactions
	if not can_move and not dialogue_running and not animation_tree.get("parameters/ToolOneShot/active"):
		can_move = true
	
	if can_move:
		animate()
		get_basic_input()
		_update_pathfinding(delta)
	
	# Update social system
	if npc_social:
		# NPCSocial handles its own _physics_process
		pass

func _update_pathfinding(delta: float) -> void:
	if not is_following_path or current_path.is_empty():
		return
	
	var target := current_path[0] if current_path.size() > 0 else path_target
	var to_target := target - global_position
	var distance := to_target.length()
	
	# Check waypoint reached
	if distance <= 12.0:
		current_path.remove_at(0)
		if current_path.is_empty():
			_on_path_completed()
			return
		target = current_path[0]
		to_target = target - global_position
		distance = to_target.length()
	
	# Move towards target
	var move_direction := to_target.normalized()
	var move_speed := base_speed * (npc_navigation.movement_speed_multiplier if npc_navigation else 1.0)
	
	# Apply local avoidance if navigation component exists
	if npc_navigation and npc_navigation.avoidance_enabled:
		move_direction = npc_navigation._apply_avoidance(move_direction)
	
	move(move_direction, move_speed)
	
	# Stuck detection
	var dist_moved := global_position.distance_to(last_position)
	if dist_moved < 4.0:
		stuck_timer += delta
		if stuck_timer >= 2.0:
			_request_path_recalculation()
	else:
		stuck_timer = 0.0
	last_position = global_position

func _request_path_recalculation() -> void:
	stuck_timer = 0.0
	if path_target != Vector2.INF:
		_request_path(path_target, true)

func _on_world_time_changed(_minutes: int) -> void:
	_update_schedule_state()
	# Apply daily memory decay
	if npc_memory:
		npc_memory.apply_daily_decay()

func _update_schedule_state() -> void:
	if biodata == null or biodata.daily_schedule.is_empty() or dialogue_running:
		return
	
	var clock := get_node_or_null("/root/WorldTime")
	if clock == null:
		return
	
	var now: int = clock.get_current_minutes()
	var selected: Dictionary = {}
	for entry in biodata.daily_schedule:
		var start: int = int(entry.get("start_minute", 0))
		var end: int = int(entry.get("end_minute", 1440))
		if (start <= end and now >= start and now < end) or (start > end and (now >= start or now < end)):
			selected = entry
			break
	
	if selected.is_empty():
		return
	
	var activity: String = str(selected.get("activity", "idle"))
	if activity == current_schedule_activity:
		return
	
	current_schedule_activity = activity
	var new_state := _schedule_activity_to_state(activity)
	_set_behavior_state(new_state)
	
	# Handle location-based activities
	if selected.has("target_location"):
		var target_loc: Variant = selected["target_location"]
		if target_loc is Vector2:
			_request_path(target_loc)
	
	schedule_changed.emit(activity)
	print("%s schedule: %s at %s" % [npc_name, behavior_state, clock.format_time()])

func _schedule_activity_to_state(activity: String) -> String:
	match activity:
		"sleep": return "sleep"
		"work", "farm", "mine", "fish", "craft": return "work"
		"follow_player": return "follow_player"
		"chase": return "chase"
		"talk", "socialize": return "socialize"
		"trade": return "trade"
		"travel", "go_to": return "travel"
		"wander": return "wander"
		"eat": return "idle"
		_: return "idle"

func _set_behavior_state(new_state: String) -> void:
	if behavior_state != new_state:
		var old := behavior_state
		behavior_state = new_state
		behavior_changed.emit(old, new_state)

## Player Interaction

func get_basic_input() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	interact()

func interact(interactor: Node2D = null) -> void:
	if interactor != null:
		player = interactor
	
	_find_player()
	if player == null:
		return
	
	if global_position.distance_to(player.global_position) > dialogue_distance and not player_in_range:
		return
	if dialogue_running or is_requesting_ai:
		return
	
	# Record meeting in memory
	npc_memory.record_meeting("player", "player", "Player")
	
	# Update relationship
	var rel := _get_or_create_relationship("player", "player")
	rel.modify_familiarity(1.0)
	
	dialogue_running = true
	can_move = false
	previous_behavior_state = behavior_state
	behavior_state = "talk"
	last_direction = global_position.direction_to(player.global_position).round()
	if last_direction.is_zero_approx():
		last_direction = Vector2.DOWN
	animate()
	key_ui.hide()
	key_timer.stop()
	
	_pause_ai()
	
	npc_interacted.emit(player)
	
	var groq_service := get_node_or_null("/root/GroqService")
	if use_groq_ai and groq_service != null and groq_service.has_valid_api_key():
		_start_groq_dialogue(groq_service)
	elif dialogic:
		if not random_timelines.is_empty():
			dialogic.call("start", random_timelines.pick_random())
		else:
			dialogic.call("start", dialogue_timeline)
	else:
		dialogue_running = false
		can_move = true
		_resume_ai()

func _start_groq_dialogue(groq_service: Node, player_prompt: String = "") -> void:
	is_requesting_ai = true
	if emoticon_player and emoticon_player.has_animation("chatting"):
		emoticon_player.play("chatting")
	
	var clock := get_node_or_null("/root/WorldTime")
	var time_str: String = clock.format_time() if clock else "daytime"
	var current_activity := current_schedule_activity if not current_schedule_activity.is_empty() else behavior_state
	var personality := biodata.personality if biodata else "Friendly island resident."
	var mood := str(biodata.current_mood) if biodata else "neutral"
	
	# Add relationship context
	var player_rel := _get_or_create_relationship("player", "player")
	var relationship_context := ""
	if player_rel.current_tier >= 2:
		relationship_context = " You are good friends with the player."
	elif player_rel.current_tier >= 1:
		relationship_context = " You know the player casually."
	elif player_rel.current_tier <= -1:
		relationship_context = " You dislike the player."
	
	var context := {
		"time": time_str,
		"activity": current_activity,
		"mood": mood,
		"relationship": player_rel.get_relationship_description(),
	}
	
	var ai_turn: Dictionary = await groq_service.generate_npc_dialogue_turn(
		groq_character_id,
		personality + relationship_context,
		context,
		player_prompt,
		conversation_history
	)
	var ai_text: String = str(ai_turn.get("dialogue", ""))
	
	is_requesting_ai = false
	if emoticon_player:
		emoticon_player.stop()
	
	if ai_text.is_empty():
		print("[%s] Groq returned empty dialogue, falling back." % npc_name)
		if dialogic:
			if not random_timelines.is_empty():
				dialogic.call("start", random_timelines.pick_random())
			else:
				dialogic.call("start", dialogue_timeline)
		else:
			_end_interaction()
		return
	
	# Record in conversation history
	var prompt_recorded := player_prompt if not player_prompt.is_empty() else "Player interacted with you."
	conversation_history.append({"role": "user", "content": prompt_recorded})
	conversation_history.append({"role": "assistant", "content": ai_text})
	if conversation_history.size() > 8:
		conversation_history = conversation_history.slice(conversation_history.size() - 8)
	
	# Add memory of this conversation
	npc_memory.add_event_memory("conversation", "Talked with player: %s" % ai_text.left(50), ["player"], "", 0.1)
	
	if dialogic:
		var choices: Array = []
		if enable_interactive_choices:
			for choice in ai_turn.get("choices", []):
				choices.append({
					"label": str(choice.get("label", "")),
					"signal": "groq_custom:%s" % str(choice.get("prompt", ""))
				})
		var timeline = groq_service.create_dialogic_timeline(groq_character_id, ai_text, choices)
		dialogic.call("start", timeline)
	else:
		_end_interaction()

func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		return
	
	var prompt := ""
	match sig_str:
		"groq_ask_farm":
			prompt = "The player asks about your farm/work. Answer in character."
		"groq_ask_tips":
			prompt = "The player asks for advice. Give practical tips."
		"groq_ask_now":
			prompt = "The player asks what you're doing. Explain your current activity."
		"groq_ask_rumor":
			prompt = "The player asks if you've heard any rumors. Share one if you know any."
		"groq_ask_relationship":
			prompt = "The player asks about your opinion of them. Answer honestly based on your relationship."
		_:
			if sig_str.begins_with("groq_custom:"):
				prompt = sig_str.substr(len("groq_custom:")).strip_edges()
			else:
				return
	
	is_requesting_ai = true
	if emoticon_player and emoticon_player.has_animation("chatting"):
		emoticon_player.play("chatting")
	
	var clock := get_node_or_null("/root/WorldTime")
	var time_str: String = clock.format_time() if clock else "daytime"
	var current_activity := current_schedule_activity if not current_schedule_activity.is_empty() else behavior_state
	var personality := biodata.personality if biodata else "Friendly island resident."
	var mood := str(biodata.current_mood) if biodata else "neutral"
	
	var context := {
		"time": time_str,
		"activity": current_activity,
		"mood": mood,
	}
	
	var answer: String = await groq_service.generate_npc_dialogue(
		groq_character_id,
		personality,
		context,
		prompt,
		conversation_history
	)
	
	is_requesting_ai = false
	if emoticon_player:
		emoticon_player.stop()
	
	if not answer.is_empty() and dialogic:
		conversation_history.append({"role": "user", "content": prompt})
		conversation_history.append({"role": "assistant", "content": answer})
		if conversation_history.size() > 8:
			conversation_history = conversation_history.slice(conversation_history.size() - 8)
		
		# Learn from this interaction
		npc_memory.learn_fact("player_asked_%s" % prompt.left(20), answer, 0.8, "player")
		
		var timeline = groq_service.create_dialogic_timeline(groq_character_id, answer, [])
		dialogic.call("start", timeline)
	else:
		_end_interaction()

func _play_startup_dialogue() -> void:
	if startup_dialogue_running or dialogic == null or intro_timeline.is_empty():
		return
	startup_dialogue_running = true
	startup_dialogue_stage = 1
	dialogue_running = true
	can_move = false
	previous_behavior_state = behavior_state
	behavior_state = "talk"
	_pause_ai()
	dialogic.call("start", intro_timeline)

func _play_startup_random_dialogue() -> void:
	if not startup_dialogue_running or dialogic == null:
		return
	if random_timelines.is_empty():
		_finish_startup_dialogue()
		return
	startup_dialogue_stage = 2
	dialogic.call("start", random_timelines.pick_random())

func _finish_startup_dialogue() -> void:
	startup_dialogue_running = false
	startup_dialogue_stage = 0
	dialogue_running = false
	can_move = true
	behavior_state = previous_behavior_state
	_resume_ai()

func _on_dialogue_ended() -> void:
	if startup_dialogue_running:
		if startup_dialogue_stage == 1:
			call_deferred("_play_startup_random_dialogue")
		else:
			_finish_startup_dialogue()
		return
	if is_requesting_ai:
		return
	if dialogue_running:
		_end_interaction()
		if player_in_range:
			key_timer.start()

func _end_interaction() -> void:
	dialogue_running = false
	can_move = true
	behavior_state = previous_behavior_state
	_resume_ai()

func _pause_ai() -> void:
	velocity = Vector2.ZERO
	if bt_player:
		bt_player.set_process(false)
		bt_player.set_physics_process(false)
	# Also pause navigation
	is_following_path = false

func _resume_ai() -> void:
	if bt_player:
		bt_player.set_process(true)
		bt_player.set_physics_process(true)

## Pathfinding API

func _request_path(target: Vector2, force_recalculate: bool = false) -> bool:
	if npc_navigation == null:
		return false
	
	if not force_recalculate and target == path_target and is_following_path:
		return true
	
	path_target = target
	var success := npc_navigation.request_path(target, force_recalculate)
	
	if success:
		current_path = npc_navigation.get_current_path()
		is_following_path = true
		_set_behavior_state("travel")
	
	return success

func stop_pathfinding() -> void:
	is_following_path = false
	current_path = []
	path_target = Vector2.INF
	if npc_navigation:
		npc_navigation.stop()

func move_to(target: Vector2, arrival_dist: float = 12.0) -> bool:
	return _request_path(target)

func _on_path_completed() -> void:
	is_following_path = false
	current_path = []
	path_target = Vector2.INF
	path_completed.emit()
	
	# Resume previous behavior if we were traveling
	if behavior_state == "travel":
		behavior_state = previous_behavior_state

func _on_path_blocked(blocked_position: Vector2) -> void:
	print("[%s] Path blocked at %s" % [npc_name, blocked_position])
	path_failed.emit(blocked_position)
	# Try to find alternative after delay
	call_deferred("_request_path_recalculation")

func _on_path_recalculated(new_path: Array[Vector2]) -> void:
	current_path = new_path
	print("[%s] Path recalculated, %d waypoints" % [npc_name, new_path.size()])

## Relationship System

func _get_or_create_relationship(target_id: String, target_type: String = "npc") -> NPCRelationshipType:
	if not relationships.has(target_id):
		var rel = NPCRelationshipType.new()
		rel.target_id = target_id
		rel.target_type = target_type
		relationships[target_id] = rel
	return relationships[target_id]

func get_relationship(target_id: String) -> NPCRelationshipType:
	return _get_or_create_relationship(target_id)

func modify_relationship(target_id: String, affinity_change: float, reason: String = "", target_type: String = "npc") -> void:
	var rel := _get_or_create_relationship(target_id, target_type)
	var old_tier := rel.current_tier
	rel.modify_affinity(affinity_change, reason)
	
	# Update memory familiarity
	npc_memory.known_entities[target_id]["familiarity"] = rel.familiarity
	
	relationship_changed.emit(target_id, rel.current_tier, rel.affinity)
	
	# Add memory
	if not reason.is_empty():
		npc_memory.add_event_memory("relationship_change", "%s with %s (%+.1f)" % [reason, target_id, affinity_change], [target_id], "", affinity_change / 100.0)

func get_relationship_tier(target_id: String) -> int:
	return _get_or_create_relationship(target_id).current_tier

func get_affinity(target_id: String) -> float:
	return _get_or_create_relationship(target_id).affinity

func get_relationship_modifiers(target_id: String) -> Dictionary:
	return _get_or_create_relationship(target_id).get_tier_modifiers()

## Social Interaction Delegation

func _on_social_interaction_started(participant_a: Node, participant_b: Node, interaction_type: String) -> void:
	var other := participant_a if participant_b == self else participant_b
	social_interaction_started.emit(other, interaction_type)
	_pause_ai()

func _on_social_interaction_ended(participant_a: Node, participant_b: Node, interaction_type: String, outcome: String) -> void:
	var other := participant_a if participant_b == self else participant_b
	social_interaction_ended.emit(other, interaction_type, outcome)
	_resume_ai()

func _on_relationship_changed(target_id: String, old_tier: int, new_tier: int, affinity_change: float) -> void:
	relationship_changed.emit(target_id, new_tier, _get_or_create_relationship(target_id).affinity)
	
	# React to significant relationship changes
	if new_tier >= 2 and old_tier < 2:
		# Became friends
		npc_memory.add_event_memory("friendship_formed", "Became friends with %s" % target_id, [target_id], "", 0.5)
	elif new_tier <= -1 and old_tier > -1:
		# Became enemies
		npc_memory.add_grudge(target_id, "Relationship deteriorated", 5.0)
		npc_memory.add_event_memory("enemy_made", "Became enemies with %s" % target_id, [target_id], "", -0.5)

func _on_group_formed(group_id: String, members: Array[Node]) -> void:
	print("[%s] Joined group %s" % [npc_name, group_id])

func _on_rumor_spread(rumor: Dictionary, from_npc: Node, to_npc: Node) -> void:
	if to_npc == self:
		npc_memory.hear_rumor(rumor.content, from_npc.get_unique_npc_id() if from_npc.has_method("get_unique_npc_id") else "unknown")
		npc_memory.add_event_memory("rumor_heard", "Heard rumor from %s: %s" % [from_npc.npc_name if from_npc.has_method("npc_name") else "someone", rumor.content], [], "", 0.1)

## Worker/Farmer Behavior (for schedule-driven work)

func worker_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true
	
	if worker_target_position == Vector2.INF:
		_prepare_worker_work(level)
		if worker_target_position == Vector2.INF:
			return true
	
	if global_position.distance_to(worker_target_position) > 12.0:
		var travel_direction := global_position.direction_to(worker_target_position)
		last_direction = travel_direction.round()
		move(travel_direction, base_speed * work_efficiency)
		return false
	
	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(worker_target_position).round()
	if last_direction.is_zero_approx():
		last_direction = Vector2.RIGHT
	level.npc_tool_use(worker_target_tool, worker_target_position, false, worker_seed)
	_play_tool_animation(worker_target_tool)
	worker_target_position = Vector2.INF
	worker_work_phase += 1
	return true

func _prepare_worker_work(level: Node) -> void:
	# Crops are season-locked. Keep NPC workers useful all year by picking an
	# in-season seed when their configured crop is out of season.
	var world_time := get_node_or_null("/root/WorldTime")
	var data_singleton := get_node_or_null("/root/Data")
	if world_time and data_singleton and not data_singleton.seed_in_season(int(worker_seed), world_time.current_season):
		worker_seed = data_singleton.first_seed_in_season(world_time.current_season) as Enum.Seed
	# Alternate between farming and woodcutting
	if worker_work_phase % 2 == 0:
		worker_target_position = _find_planting_spot(level)
		worker_target_tool = Enum.Tool.SEED
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_nearest_tree_position()
			worker_target_tool = Enum.Tool.AXE
	else:
		worker_target_position = _find_nearest_tree_position()
		worker_target_tool = Enum.Tool.AXE
		if worker_target_position == Vector2.INF:
			worker_target_position = _find_planting_spot(level)
			worker_target_tool = Enum.Tool.SEED

func _find_planting_spot(level: Node) -> Vector2:
	var dirt_layer: TileMapLayer = level.get_node_or_null("Layers/LightDirtLayer")
	if dirt_layer == null:
		return Vector2.INF
	var used_cells: Array = level.get("used_cells")
	var farm_cells := dirt_layer.get_used_cells()
	if farm_cells.is_empty():
		return Vector2.INF
	
	# Find nearest unplanted spot
	var best_position := Vector2.INF
	var best_distance := INF
	for cell in farm_cells:
		if cell in used_cells:
			continue
		var position := dirt_layer.to_global(dirt_layer.map_to_local(cell))
		var distance := global_position.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best_position = position
	return best_position

func _find_nearest_tree_position() -> Vector2:
	var best_position := Vector2.INF
	var best_distance := INF
	for object in get_tree().get_nodes_in_group("Objects"):
		if not is_instance_valid(object) or not object.has_method("hit"):
			continue
		var health = object.get("health")
		if health != null and int(health) <= 0:
			continue
		var distance := global_position.distance_squared_to(object.global_position)
		if distance < best_distance:
			best_distance = distance
			best_position = object.global_position
	return best_position

func _play_tool_animation(tool: Enum.Tool) -> void:
	can_move = false
	var animation_name: String = Data.TOOL_STATE_ANIMATIONS.get(tool, "")
	if animation_name.is_empty():
		return
	var tool_state_machine = animation_tree.get("parameters/ToolStateMachine/playback")
	for tool_animation in Data.TOOL_STATE_ANIMATIONS.values():
		animation_tree.set("parameters/ToolStateMachine/" + tool_animation + "/blend_position", last_direction)
	tool_state_machine.travel(animation_name)
	animation_tree.set("parameters/ToolOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Player Detection

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body != player and not body.is_in_group("Player"):
		return
	player = body
	player_in_range = true
	if not dialogue_running:
		key_timer.start()
	
	# Record meeting
	if body.has_method("get_unique_npc_id"):
		npc_memory.record_meeting(body.get_unique_npc_id(), "npc", body.npc_name if body.has_method("npc_name") else "NPC")
	elif body.is_in_group("Player"):
		npc_memory.record_meeting("player", "player", "Player")

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body != player and not body.is_in_group("Player"):
		return
	player_in_range = false
	key_timer.stop()
	key_ui.hide()

func _on_timer_timeout() -> void:
	if player_in_range and not dialogue_running:
		key_ui.show()
		key_ui.play("R")

## Persistence

func _load_persistent_data() -> void:
	# This would be called by the save system after loading
	# Override in specific NPC if needed
	pass

func get_save_data() -> Dictionary:
	var rel_data := {}
	for id in relationships:
		rel_data[id] = relationships[id].to_dict()
	
	return {
		"npc_id": npc_id,
		"position": [global_position.x, global_position.y],
		"last_direction": [last_direction.x, last_direction.y],
		"behavior_state": behavior_state,
		"relationships": rel_data,
		"memory": npc_memory.to_dict() if npc_memory else {},
		"social": npc_social.get_social_save_data() if npc_social else {},
		"conversation_history": conversation_history,
		"current_schedule_activity": current_schedule_activity,
		"worker_work_phase": worker_work_phase,
	}

func load_save_data(data: Dictionary) -> void:
	global_position = Vector2(data.get("position", [0, 0]))
	last_direction = Vector2(data.get("last_direction", [0, 1]))
	behavior_state = data.get("behavior_state", "wander")
	
	# Restore relationships
	for id in data.get("relationships", {}):
		var rel = NPCRelationshipType.from_dict(data["relationships"][id])
		relationships[id] = rel
	
	# Restore memory
	if npc_memory and data.has("memory"):
		var mem_data: Dictionary = data["memory"]
		# NPCMemory.from_dict is static, so we copy values
		npc_memory.npc_id = mem_data.get("npc_id", npc_id)
		npc_memory.known_entities = mem_data.get("known_entities", {})
		npc_memory.location_memories = mem_data.get("location_memories", {})
		npc_memory.event_memories = mem_data.get("event_memories", [])
		npc_memory.knowledge = mem_data.get("knowledge", {})
		npc_memory.rumors_known = mem_data.get("rumors_known", [])
		npc_memory.personal_goals = mem_data.get("personal_goals", [])
		npc_memory.grudges = mem_data.get("grudges", {})
		npc_memory.favors_owed = mem_data.get("favors_owed", {})
		npc_memory.promises_made = mem_data.get("promises_made", [])
		npc_memory.daily_reflection = mem_data.get("daily_reflection", "")
	
	# Restore social data (groups resolved later)
	if npc_social and data.has("social"):
		npc_social.load_save_data(data["social"])
	
	conversation_history = data.get("conversation_history", [])
	current_schedule_activity = data.get("current_schedule_activity", "")
	worker_work_phase = data.get("worker_work_phase", 0)
	
	# Re-apply schedule
	_update_schedule_state()

## Utility

func _find_player() -> void:
	var scene = get_tree().current_scene if get_tree() else null
	if scene != null:
		player = scene.get_node_or_null("Objects/Player")
	if player == null:
		for p in get_tree().get_nodes_in_group("Player"):
			if p != get_tree().root.get_node_or_null("Player"):
				player = p
				break

func move(move_direction: Vector2 = Vector2.ZERO, move_speed: float = 0.0) -> void:
	if move_direction.is_zero_approx() or is_zero_approx(move_speed):
		direction = Vector2.ZERO
		velocity = Vector2.ZERO
	else:
		direction = move_direction.normalized()
		last_direction = direction
		velocity = direction * move_speed
	move_and_slide()

func animate() -> void:
	if direction:
		var direction_animation = Vector2(round(direction.x), round(direction.y))
		move_state_machine.travel("walk")
		animation_tree.set("parameters/MoveStateMachine/idle/blend_position", direction_animation)
		animation_tree.set("parameters/MoveStateMachine/walk/blend_position", direction_animation)
	else:
		move_state_machine.travel("idle")

func tool_use_emit() -> void:
	pass

func check_for_self(node) -> bool:
	return node == self

func get_unique_npc_id() -> String:
	return npc_id

func get_inventory_items() -> Array[String]:
	# Override in specific NPC
	return []

func get_item_value(item: String) -> int:
	# Override in specific NPC
	return 10

func add_inventory_item(item: String) -> void:
	pass

func remove_inventory_item(item: String) -> void:
	pass

func take_damage(amount: int) -> void:
	if has_method("hit"):
		call("hit", Enum.Tool.SWORD)

func face_target(target: Node) -> void:
	var dir = global_position.direction_to(target.global_position)
	last_direction = dir.round()
	animate()

func has_singleton(name: String) -> bool:
	return get_tree().has_node("/root/" + name) if get_tree() else false