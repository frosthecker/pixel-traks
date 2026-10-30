extends CharacterBody2D

var direction: Vector2
var speed := 20
var push_speed := 300.0  # Speed at which enemy is knocked back (pixels/sec)
var knockback_velocity: Vector2 = Vector2.ZERO
@onready var player = get_tree().get_first_node_in_group('Player')
@onready var sprite_2d: AnimatedSprite2D = $Sprite2D
var health := 7:
	set(value):
		health = value
		if health <= 0:
			death()


func _physics_process(_delta: float) -> void:
	direction = (player.position - position).normalized()
	
	# Flip sprite depending on moving left or right
	if direction.x != 0:
		sprite_2d.flip_h = direction.x < 0

	# Standard movement velocity (zero out if hurt or dead)
	var move_velocity := Vector2.ZERO
	if not (sprite_2d.animation in ["hurt", "death"] and sprite_2d.is_playing()):
		if direction:
			sprite_2d.play('walk')
		else:
			sprite_2d.play('idle')
		move_velocity = direction * speed

	# Combine normal walk velocity with knockback force
	velocity = move_velocity + knockback_velocity
	move_and_slide()

func push() -> void:
	var target_knockback = (position - player.position).normalized() * push_speed
	var tween = get_tree().create_tween()
	# Instantly apply knockback force, then smoothly decay back to Vector2.ZERO over 0.2 seconds
	knockback_velocity = target_knockback
	tween.tween_property(self, "knockback_velocity", Vector2.ZERO, 0.2)

func death():
	speed = 0
	sprite_2d.play("death")
	# Connect to animation_finished and check if the finished animation is "death"
	if not sprite_2d.animation_finished.is_connected(_on_animation_finished):
		sprite_2d.animation_finished.connect(_on_animation_finished)
	
	
func hit(tool: Enum.Tool) -> void:
	if tool == Enum.Tool.SWORD:
		sprite_2d.play("hurt")
		push()
		health -= 1

func _on_animation_finished() -> void:
	if sprite_2d.animation == "death":
		queue_free()
