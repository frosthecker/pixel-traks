extends StaticBody2D

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var stump: Sprite2D = $stump
@onready var sprite_2d: Sprite2D = $FlashSprite2D
@onready var leaf_particles: CPUParticles2D = $leaf_particles
@export var log_scene: PackedScene
@onready var tree_chop: AudioStreamPlayer = $tree_chop

func _ready() -> void:
	# A healthy tree should not render its stump.  The health setter is not run
	# for the initial value, so this must be initialized explicitly.
	if health > 0:
		stump.hide()
	if sprite_2d.material != null:
		sprite_2d.material = sprite_2d.material.duplicate()
		sprite_2d.material.set_shader_parameter("shake_intensity", 0.0)

var health := 3:
	set(value):
		health = value
		if health <= 0:
			stump.show()
			sprite_2d.hide()
			leaf_particles.emitting = false
			var shape = RectangleShape2D.new()
			shape.size = Vector2i(16, 14)
			collision_shape.shape = shape
			collision_shape.position.y = 9

func hit(tool: Enum.Tool):
	# 1. Do nothing if the tree is already a stump or the wrong tool is used
	if health <= 0 or tool != Enum.Tool.AXE:
		return

	# 2. Play audio and particles immediately on hit
	if tree_chop:
		tree_chop.play()
	# flash_sprite_2d.flash()
	leaf_particles.restart()

	# 3. Handle visual shake
	if sprite_2d.material != null:
		sprite_2d.material.set_shader_parameter("shake_intensity", 1.0)

	# 4. Reduce health immediately
	health -= 1

	# 5. Only spawn logs if this hit broke the tree
	if health <= 0 and log_scene:
		var log_count = randi_range(1, 1) # Adjust if you want more logs (e.g., 2, 3)
		for _i in range(log_count):
			var log_item = log_scene.instantiate()
			var drop_parent := get_parent()
			if drop_parent == null:
				log_item.queue_free()
				continue
			drop_parent.add_child(log_item)
			# Set global coordinates only after parenting.  Otherwise Godot treats
			# the world position as local coordinates and can spawn the item away
			# from the felled tree when its parent is transformed.
			log_item.global_position = global_position

			var random_offset = Vector2(randf_range(-30, 30), randf_range(-12, 12))
			var drop_tween = log_item.create_tween()
			drop_tween.set_parallel(true)
			drop_tween.tween_property(log_item, "position", log_item.position + random_offset, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 6. Reset shake intensity after the timer completes
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(sprite_2d) and sprite_2d.material != null:
		sprite_2d.material.set_shader_parameter("shake_intensity", 0.0)
