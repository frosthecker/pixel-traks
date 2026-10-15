extends StaticBody2D

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var stump: Sprite2D = $stump
@onready var sprite_2d: Sprite2D = $FlashSprite2D
@onready var leaf_particles: GPUParticles2D = $leaf_particles
@export var log_scene: PackedScene

func _ready() -> void:
	sprite_2d.material.set_shader_parameter("shake_intensity", 0.0)


var health := 3:
	set(value):
		health = value
		if health <= 0:
			stump.show()
			sprite_2d.hide()
			leaf_particles.emitting = false
			# leaf_particles.queue_free()
			var shape = RectangleShape2D.new()
			shape.size = Vector2i(16,14)
			collision_shape.shape = shape
			collision_shape.position.y = 9
			
			
func hit(tool: Enum.Tool):
	if tool == Enum.Tool.AXE:
		#flash_sprite_2d.flash()
		leaf_particles.restart()
		sprite_2d.material.set_shader_parameter("shake_intensity", 1)
		await get_tree().create_timer(1.0).timeout
		sprite_2d.material.set_shader_parameter("shake_intensity", 0.0)
		
		if log_scene:
				var log_count = randi_range(1, 1)
				for i in range(log_count):
					var log_item = log_scene.instantiate()
					log_item.global_position = global_position
					
					# Add to the main level/parent node so it stays after tree handling
					get_parent().add_child(log_item)
					
					# Pop out animation using a Tween
					var random_offset = Vector2(randf_range(-30, 30), randf_range(-12, 12))
					var drop_tween = log_item.create_tween()
					drop_tween.set_parallel(true)
					drop_tween.tween_property(log_item, "position", log_item.position + random_offset, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		
		health-=1
