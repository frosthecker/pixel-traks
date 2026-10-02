extends Control

@onready var hide_timer: Timer = $HideTimer
@onready var tool_container: HBoxContainer = $ToolContainer
const TOOL_TEXTURES = {
	Enum.Tool.AXE: preload("res://assets/Sunnyside_World_Assets/UI/axe.png"),
	Enum.Tool.HOE: preload("res://assets/Sunnyside_World_Assets/UI/shovel.png"),
	Enum.Tool.WATER: preload("res://assets/Sunnyside_World_Assets/UI/water.png"),
	Enum.Tool.SWORD: preload("res://assets/Sunnyside_World_Assets/UI/sword.png"),
	Enum.Tool.FISH: preload("res://assets/Sunnyside_World_Assets/UI/rod alt.png"),
	Enum.Tool.SEED: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/seeds_generic.png"),
	Enum.Tool.HAMMER: preload("res://assets/Sunnyside_World_Assets/UI/hammer.png"),
}
var tool_texture_scene = preload("res://scenes/UI/tool_ui_texture.tscn")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tool_container.hide()
	texture_setup(Enum.Tool.values(),TOOL_TEXTURES, tool_container)

func texture_setup(enum_list: Array, textures: Dictionary, container: HBoxContainer):
	for enum_id in enum_list:
		var tool_texture = tool_texture_scene.instantiate()
		container.add_child(tool_texture)
		tool_texture.setup(enum_id, textures[enum_id])
		
func reveal():
	hide_timer.start()
	tool_container.show()
	var target = get_parent().current_tool
	for texture in tool_container.get_children():
		texture.highlight(target == texture.tool_enum)

func _on_hide_timer_timeout() -> void:
	tool_container.hide()
