extends Sprite2D

@onready var sprite: Sprite2D = $"."


func set_outline_visible(is_visible: bool) -> void:
	var mat = sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("enabled", is_visible)
