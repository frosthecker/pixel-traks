extends CharacterBody2D

var direction: Vector2
var last_direction: Vector2 = Vector2.DOWN
var speed = 50
var current_tool: Enum.Tool = Enum.Tool.AXE
var current_seed: Enum.Seed
var can_move: bool = true
@onready var sprite2d: Sprite2D = $Sprite2D
@onready var tool_ui: Control = $ToolUI
@onready var animation_tree: AnimationTree = $Animation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@onready var tool_state_machine = animation_tree.get("parameters/ToolStateMachine/playback")
signal tool_use(tool: Enum.Tool, pos: Vector2, dir: bool)
@onready var sprite: Sprite2D = $Sprite2D
var current_style = 0

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
	if Input.is_action_just_pressed("style"):
		current_style = posmod(current_style + 1, Enum.Style.size()) as Enum.Style
		sprite.texture = Data.PLAYER_SKINS[current_style] 
	if Input.is_action_just_pressed("tool_backward"):
		current_tool = posmod(current_tool + 1, Enum.Tool.size()) as Enum.Tool
		print(current_tool)
		tool_ui.reveal(true)
		
	if Input.is_action_just_pressed("seed_forward"):
		current_seed = posmod(current_seed + 1, Enum.Seed.size()) as Enum.Seed
		tool_ui.reveal(false)
		print(current_seed)
	
	if Input.is_action_just_pressed("action"):
		can_move = false
		tool_state_machine.travel(Data.TOOL_STATE_ANIMATIONS[current_tool])
		animation_tree.set("parameters/ToolOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
	if Input.is_action_pressed("pick"):
		for pickup_item in $PickupZone.items_in_range.values():
			if pickup_item.has_method("hit"):
				print("tree picked")
				break
			elif pickup_item.has_method("pick_up_item"):
				pickup_item.pick_up_item(self)
				$PickupZone.items_in_range.erase(pickup_item)
				print('log picked')
				break

func move():
	direction = Input.get_vector("left", "right", "down", "up")
	if direction:
		last_direction = Vector2(round(direction.x), round(direction.y))
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
	# Tool placement is emitted when the action starts. This method remains for
	# existing animation tracks but must not emit a second time.
	var use_position : Vector2 =  global_position if current_tool == Enum.Tool.WATER else global_position + last_direction * Data.TILE_SIZE
	tool_use.emit(current_tool, use_position, sprite2d.flip_h)
