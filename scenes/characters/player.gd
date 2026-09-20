extends CharacterBody2D

var direction: Vector2
var speed = 50
@onready var animation_tree: AnimationTree = $Animation/AnimationTree
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")


func _physics_process(delta: float) -> void:
	move()
	animate()

func move():
	direction = Input.get_vector("left", "right", "down", "up")
	velocity = direction * speed
	move_and_slide()

func animate():
	if direction:
		move_state_machine.travel("walk")
		var direction_animation = Vector2(round(direction.x), round(direction.y))
		animation_tree.set("parameters/MoveStateMachine/idle/blend_position", direction_animation)
		animation_tree.set("parameters/MoveStateMachine/walk/blend_position", direction_animation)
	else:
		move_state_machine.travel("idle")

func tool_use_emit():
	print('tool')
