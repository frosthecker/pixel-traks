extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if randi() % 2==0:
		$TextureRect.texture = load('res://assets/Sunnyside_World_Assets/UI/shovel.png')
	else:
		$TextureRect.texture = load('res://assets/Sunnyside_World_Assets/UI/sword.png')
