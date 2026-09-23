extends CharacterBody2D

var direction: Vector2
var speed = 40
var current_tool: Enum.Tool = Enum.Tool.HOE
var current_seed: Enum.Seed
var can_move: bool = true
@onready var animation_tree: AnimationTree = $Animation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@onready var tool_state_machine = animation_tree.get("parameters/ToolStateMachine/playback")
signal tool_use(tool: Enum.Tool, pos: Vector2)

func _ready() -> void:
	animation_tree.active = true

func _physics_process(delta: float) -> void:
	if not can_move and not animation_tree.get("parameters/ToolOneShot/active"):
		can_move = true
	if can_move:
		move()
		animate()
		get_basic_input()

func get_basic_input():
	if Input.is_action_just_pressed("tool_backward") or Input.is_action_just_pressed("tool_forward"):
		var dir = Input.get_axis("tool_backward", "tool_forward")
		current_tool = posmod(current_tool + int(dir), Enum.Tool.size()) as Enum.Tool
		print(current_tool)
		
	if Input.is_action_just_pressed("seed_forward"):
		current_seed = posmod(current_seed + 1, Enum.Seed.size()) as Enum.Seed
		print(current_seed)
	
	if Input.is_action_just_pressed("action"):
		can_move = false
		tool_state_machine.travel(Data.TOOL_STATE_ANIMATIONS[current_tool])
		animation_tree.set("parameters/ToolOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		tool_use.emit(current_tool, position)

func move():
	direction = Input.get_vector("left", "right", "down", "up")
	velocity = direction * speed
	move_and_slide()

func animate():
	if direction:
		var direction_animation = Vector2(round(direction.x), round(direction.y))
		move_state_machine.travel("walk")
		animation_tree.set("parameters/MoveStateMachine/idle/blend_position", direction_animation)
		animation_tree.set("parameters/MoveStateMachine/walk/blend_position", direction_animation)
		var tool_direction = Vector2(round(direction.x), round(direction.y)) if direction else Vector2.DOWN
		for animation in Data.TOOL_STATE_ANIMATIONS.values():
			var animation_name: String = "parameters/ToolStateMachine/" + animation + "/blend_position"
			animation_tree.set(animation_name, tool_direction)
	else:
		move_state_machine.travel("idle")

func tool_use_emit():
	print('tool')
