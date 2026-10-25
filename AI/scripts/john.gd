extends CharacterBody2D

const NPCResourceType = preload("res://resources/npc_resource.gd")
const NPCBiodataType = preload("res://resources/npc_biodata.gd")

var direction: Vector2 = Vector2.ZERO
var last_direction: Vector2 = Vector2.DOWN
var speed = 25
var can_move: bool = true

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_tree: AnimationTree = $PlayerAnimation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@onready var bt_player: Node = $BTPlayer
@onready var key_ui: AnimatedSprite2D = $Key_UI/key_UI
@onready var key_timer: Timer = $Key_UI/Timer

## These inspector values are copied into NPCResource in _ready().
@export_category("NPC Data")
@export var texture: Texture2D
@export_file("*.dch") var dialogue_character: String = ""
@export_file("*.dtl") var dialogue_timeline: String = ""
@export_file("*.dtl") var intro_timeline: String = ""
@export var random_timelines: Array[String] = []
@export var dialogue_distance: float = 32.0
@export var key_prompt_delay: float = 5.0
@export var biodata: NPCBiodataType
@export_category("Groq AI")
@export var use_groq_ai: bool = true
@export var groq_character_id: String = "John"
@export var enable_interactive_choices: bool = true
@export_category("Farmer")
@export var farmer_seed: Enum.Seed = Enum.Seed.WHEAT
@export_enum("idle", "wander", "follow_player", "follow_npc", "chase", "talk", "work", "flee", "sleep")
var behavior_state: String = "wander"

var npc_data: NPCResourceType
var player_in_range := false
var player: Node2D
var dialogue_running := false
var is_requesting_ai := false
var conversation_history: Array = []
var startup_dialogue_running := false
var startup_dialogue_stage := 0
var dialogic: Node
var previous_behavior_state: String = "wander"
var farmer_work_phase: int = 0
var current_schedule_activity: String = ""
var farmer_target_position: Vector2 = Vector2.INF
var farmer_target_tool: Enum.Tool = Enum.Tool.AXE

@onready var emoticon_player: AnimationPlayer = get_node_or_null("emoticonAnimation/AnimationPlayer")

func _ready() -> void:
	animation_tree.active = true

	# Build the reusable data object from the values supplied on john.tscn.
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
		speed = npc_data.biodata.movement_speed
	dialogue_distance = npc_data.dialogue_distance
	key_prompt_delay = npc_data.key_prompt_delay
	dialogue_timeline = npc_data.dialogue_timeline
	intro_timeline = npc_data.intro_timeline
	random_timelines = npc_data.random_timelines
	key_timer.one_shot = true
	key_timer.wait_time = key_prompt_delay
	key_ui.hide()
	player = get_tree().get_first_node_in_group("Player")
	dialogic = get_node_or_null("/root/Dialogic")
	if dialogic:
		if not dialogic.is_connected("timeline_ended", Callable(self, "_on_dialogue_ended")):
			dialogic.connect("timeline_ended", Callable(self, "_on_dialogue_ended"))
		if not dialogic.is_connected("signal_event", Callable(self, "_on_dialogic_signal")):
			dialogic.connect("signal_event", Callable(self, "_on_dialogic_signal"))
	if not WorldTime.time_changed.is_connected(_on_world_time_changed):
		WorldTime.time_changed.connect(_on_world_time_changed)
	_update_schedule_state()
	# The intro is a first-run event. Once a save exists, loading the game should
	# never restart John's opening conversation.
	if dialogic and not intro_timeline.is_empty() and not SaveGame.has_save():
		call_deferred("_play_startup_dialogue")
	
func _physics_process(delta: float) -> void:
	if not can_move and not dialogue_running and not animation_tree.get("parameters/ToolOneShot/active"):
		can_move = true
	if can_move:
		animate()
		get_basic_input()

func _on_world_time_changed(_minutes: int) -> void:
	_update_schedule_state()

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
	behavior_state = _schedule_activity_to_state(activity)
	print(name, " schedule state: ", behavior_state, " at ", clock.format_time())

func _schedule_activity_to_state(activity: String) -> String:
	match activity:
		"sleep":
			return "sleep"
		"work", "farm", "eat":
			return "work"
		"follow_player":
			return "follow_player"
		"chase":
			return "chase"
		"talk":
			return "talk"
		"wander":
			return "wander"
		_:
			return "idle"
	
func get_basic_input() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	if player == null:
		return
	if global_position.distance_to(player.global_position) > dialogue_distance:
		return
	if dialogue_running or is_requesting_ai:
		return

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

	var clock: Node = get_node_or_null("/root/WorldTime")
	var time_str: String = clock.format_time() if clock != null else "daytime"
	var current_activity := current_schedule_activity if not current_schedule_activity.is_empty() else behavior_state
	var personality := biodata.personality if biodata else "Friendly and cautious farmer."
	var mood := str(biodata.current_mood) if biodata else "neutral"

	var context := {
		"time": time_str,
		"activity": current_activity,
		"mood": mood
	}

	var ai_turn: Dictionary = await groq_service.generate_npc_dialogue_turn(
		groq_character_id,
		personality,
		context,
		player_prompt,
		conversation_history
	)
	var ai_text: String = str(ai_turn.get("dialogue", ""))

	is_requesting_ai = false
	if emoticon_player:
		emoticon_player.stop()

	if ai_text.is_empty():
		print("[John] Groq returned empty dialogue or error, falling back to local timeline.")
		if dialogic:
			if not random_timelines.is_empty():
				dialogic.call("start", random_timelines.pick_random())
			else:
				dialogic.call("start", dialogue_timeline)
		else:
			dialogue_running = false
			can_move = true
			_resume_ai()
		return

	var prompt_recorded := player_prompt if not player_prompt.is_empty() else "Player interacted with you."
	conversation_history.append({"role": "user", "content": prompt_recorded})
	conversation_history.append({"role": "assistant", "content": ai_text})
	if conversation_history.size() > 6:
		conversation_history = conversation_history.slice(conversation_history.size() - 6)

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
		# Do not leave John frozen if the dialogue UI/autoload is unavailable.
		_end_interaction()


func _on_dialogic_signal(argument: Variant) -> void:
	var sig_str := str(argument)
	var groq_service := get_node_or_null("/root/GroqService")
	if not use_groq_ai or groq_service == null or not groq_service.has_valid_api_key():
		return

	var prompt := ""
	match sig_str:
		"groq_ask_farm":
			prompt = "The player asks: 'How is the farm doing today?' Answer warmly in character."
		"groq_ask_tips":
			prompt = "The player asks: 'Any tips for life on this island?' Share practical farming or survival advice."
		"groq_ask_now":
			prompt = "The player asks: 'What are you doing right now?' Explain your current task or schedule."
		_:
			if sig_str.begins_with("groq_custom:"):
				prompt = sig_str.substr(len("groq_custom:")).strip_edges()
			else:
				return

	is_requesting_ai = true
	if emoticon_player and emoticon_player.has_animation("chatting"):
		emoticon_player.play("chatting")

	var clock: Node = get_node_or_null("/root/WorldTime")
	var time_str: String = clock.format_time() if clock != null else "daytime"
	var current_activity := current_schedule_activity if not current_schedule_activity.is_empty() else behavior_state
	var personality := biodata.personality if biodata else "Friendly and cautious farmer."
	var mood := str(biodata.current_mood) if biodata else "neutral"

	var context := {
		"time": time_str,
		"activity": current_activity,
		"mood": mood
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
		if conversation_history.size() > 6:
			conversation_history = conversation_history.slice(conversation_history.size() - 6)

		var timeline = groq_service.create_dialogic_timeline(groq_character_id, answer, [])
		dialogic.call("start", timeline)
	else:
		# The previous timeline already ended while the request was in flight, so
		# its timeline_ended signal cannot restore the NPC state for us.
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
	bt_player.set_process(false)
	bt_player.set_physics_process(false)

func _resume_ai() -> void:
	bt_player.set_process(true)
	bt_player.set_physics_process(true)

func farmer_work_step() -> bool:
	var level := get_tree().current_scene
	if level == null or not level.has_method("npc_tool_use"):
		return true

	if farmer_target_position == Vector2.INF:
		_prepare_farmer_work(level)
		if farmer_target_position == Vector2.INF:
			return true

	if global_position.distance_to(farmer_target_position) > 12.0:
		var travel_direction := global_position.direction_to(farmer_target_position)
		last_direction = travel_direction.round()
		move(travel_direction, speed)
		return false

	move(Vector2.ZERO, 0.0)
	last_direction = global_position.direction_to(farmer_target_position).round()
	if last_direction.is_zero_approx():
		last_direction = Vector2.RIGHT
	level.npc_tool_use(farmer_target_tool, farmer_target_position, false, farmer_seed)
	_play_tool_animation(farmer_target_tool)
	farmer_target_position = Vector2.INF
	farmer_work_phase += 1
	return true

func _prepare_farmer_work(level: Node) -> void:
	if farmer_work_phase % 2 == 0:
		farmer_target_position = _find_planting_spot(level)
		farmer_target_tool = Enum.Tool.SEED
		if farmer_target_position == Vector2.INF:
			farmer_target_position = _find_nearest_tree_position()
			farmer_target_tool = Enum.Tool.AXE
	else:
		farmer_target_position = _find_nearest_tree_position()
		farmer_target_tool = Enum.Tool.AXE
		if farmer_target_position == Vector2.INF:
			farmer_target_position = _find_planting_spot(level)
			farmer_target_tool = Enum.Tool.SEED

func _find_planting_spot(level: Node) -> Vector2:
	var dirt_layer: TileMapLayer = level.get_node_or_null("Layers/LightDirtLayer")
	if dirt_layer == null:
		return Vector2.INF
	var used_cells: Array = level.get("used_cells")
	var farm_cells := dirt_layer.get_used_cells()
	if farm_cells.is_empty():
		return Vector2.INF
	var farm_center := Vector2.ZERO
	for cell in farm_cells:
		farm_center += Vector2(cell)
	farm_center /= float(farm_cells.size())

	var best_position := Vector2.INF
	var best_distance := INF
	for cell in farm_cells:
		if cell in used_cells:
			continue
		var position := dirt_layer.to_global(dirt_layer.map_to_local(cell))
		var distance := Vector2(cell).distance_squared_to(farm_center)
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

func tool_use_emit() -> void:
	# John applies the gameplay effect in perform_farmer_work(). The copied
	# animation tracks still call this method, so keep it as a safe no-op.
	pass

func move(move_direction: Vector2 = Vector2.ZERO, move_speed: float = 0.0) -> void:
	if move_direction.is_zero_approx() or is_zero_approx(move_speed):
		direction = Vector2.ZERO
		velocity = Vector2.ZERO
	else:
		direction = move_direction.normalized()
		last_direction = direction
		velocity = direction * move_speed
	move_and_slide()

func animate():
	if direction:
		var direction_animation = Vector2(round(direction.x), round(direction.y))
		move_state_machine.travel("walk")
		animation_tree.set("parameters/MoveStateMachine/idle/blend_position", direction_animation)
		animation_tree.set("parameters/MoveStateMachine/walk/blend_position", direction_animation)
	else:
		move_state_machine.travel("idle")

func check_for_self(node):
	if node == self:
		return true
	else:
		return false
	


func _on_timer_timeout() -> void:
	if player_in_range and not dialogue_running:
		key_ui.show()
		key_ui.play("R")


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body != player and not body.is_in_group("Player"):
		return
	player_in_range = true
	if not dialogue_running:
		key_timer.start()


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body != player and not body.is_in_group("Player"):
		return
	player_in_range = false
	key_timer.stop()
	key_ui.hide()
