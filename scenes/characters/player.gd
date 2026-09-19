extends CharacterBody2D

var direction: Vector2
var speed = 50

func _physics_process(delta: float) -> void:
	move()

func move():
	direction = Input.get_vector("left", "right", "down", "up")
	velocity = direction * speed
	move_and_slide()

func tool_use_emit():
	print('tool')
