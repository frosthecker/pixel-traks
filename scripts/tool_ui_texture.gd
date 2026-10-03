extends Control

@onready var texture_rect: TextureRect = $TextureRect
var tool_enum: Enum.Tool

func setup(new_tool_enum: Enum.Tool, main_texture: Texture2D):
	tool_enum = new_tool_enum
	texture_rect.texture = main_texture
	
func highlight(selected: bool):
	print(selected)
	var tween = create_tween()
	var target_size = Vector2(20,20) if selected else Vector2(16,16)
	tween.tween_property(texture_rect, "custom_minimum_size", target_size, 0.1)
	
	
