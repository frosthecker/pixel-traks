extends Control

@onready var texture_rect: TextureRect = $TextureRect
@onready var outline_material: ShaderMaterial = texture_rect.material as ShaderMaterial
var tool_enum: Enum.Tool
var highlight_tween: Tween
var is_highlighted := false

const NORMAL_SCALE := Vector2.ONE
const HIGHLIGHT_SCALE := Vector2(1.18, 1.18)
const HIGHLIGHT_COLOR := Color(1.0, 0.9, 0.55, 1.0)

func _ready() -> void:
	texture_rect.pivot_offset = Vector2(8, 8)
	outline_material.set_shader_parameter("enabled", false)

func setup(new_tool_enum: Enum.Tool, main_texture: Texture2D):
	tool_enum = new_tool_enum
	texture_rect.texture = main_texture
	
func highlight(selected: bool):
	if selected == is_highlighted:
		return
	is_highlighted = selected
	outline_material.set_shader_parameter("enabled", selected)

	if highlight_tween:
		highlight_tween.kill()

	highlight_tween = create_tween()
	if selected:
		texture_rect.scale = NORMAL_SCALE
		texture_rect.modulate = Color.WHITE
		for i in range(2):
			highlight_tween.tween_property(texture_rect, "scale", HIGHLIGHT_SCALE, 0.16) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			highlight_tween.tween_property(texture_rect, "scale", Vector2(1.08, 1.08), 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			
	else:
		highlight_tween.set_parallel(true)
		highlight_tween.tween_property(texture_rect, "scale", NORMAL_SCALE, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		highlight_tween.tween_property(texture_rect, "modulate", Color.WHITE, 0.12)
	
