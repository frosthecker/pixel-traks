@tool
extends StaticBody2D

@onready var sprite_2d: Sprite2D = $Sprite2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	sprite_2d.frame = randi_range(0,19)
