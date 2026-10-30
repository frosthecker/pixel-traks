extends CharacterBody2D

var direction: Vector2 = Vector2.ZERO
var last_direction: Vector2 = Vector2.DOWN
var speed = 25
var can_move: bool = true

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_tree: AnimationTree = $PlayerAnimation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@export var texture: Texture2D
@export_category("Behavior")
@export_enum("idle", "wander", "follow_player", "follow_npc", "chase", "talk", "work", "flee", "sleep")
var behavior_state: String = "wander"

func _ready() -> void:
	animation_tree.active = true
	sprite_2d.texture = texture
func _physics_process(delta: float) -> void:
	if not can_move and not animation_tree.get("parameters/ToolOneShot/active"):
		can_move = true
	if can_move:
		animate()
		get_basic_input()

func get_basic_input():
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
	
