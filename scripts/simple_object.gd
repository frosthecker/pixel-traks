@tool
extends StaticBody2D

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var style = [0,2].pick_random()
	sprite_2d.frame_coords = Vector2i(randi_range(0,7), style)
	collision_shape.disabled = style < 2
