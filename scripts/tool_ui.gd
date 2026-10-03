extends Control

@onready var seed_container: HBoxContainer = $SeedContainer
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
const SEED_TEXTURES = {
	Enum.Seed.BEETROOT: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/beetroot_00.png"),
	Enum.Seed.CABBAGE: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/cabbage_00.png"),
	Enum.Seed.CARROT: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/carrot_00.png"),
	Enum.Seed.CAULIFLOWER: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/cauliflower_00.png"),
	#Enum.Seed.KALE: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/kale_00.png"),
	#Enum.Seed.PARSNIP: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/parsnip_00.png"),
	Enum.Seed.POTATO: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/potato_00.png"),
	Enum.Seed.PUMPKIN: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/pumpkin_00.png"),
	Enum.Seed.RADISH: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/radish_00.png"),
	Enum.Seed.SUNFLOWER: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/sunflower_00.png"),
	Enum.Seed.WHEAT: preload("res://assets/Sunnyside_World_Assets/Elements/Crops/wheat_00.png")
}
var tool_texture_scene = preload("res://scenes/UI/tool_ui_texture.tscn")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for container in [tool_container, seed_container]:
		container.hide()
	texture_setup(Enum.Tool.values(),TOOL_TEXTURES, tool_container)
	texture_setup(Enum.Seed.values(),SEED_TEXTURES, seed_container)
func texture_setup(enum_list: Array, textures: Dictionary, container: HBoxContainer):
	for enum_id in enum_list:
		var tool_texture = tool_texture_scene.instantiate()
		container.add_child(tool_texture)
		tool_texture.setup(enum_id, textures[enum_id])
		
func reveal(tool: bool):
	hide_timer.start()
	var current_container = tool_container if tool else seed_container
	
	var target = get_parent().current_tool if tool else get_parent().current_seed
	for container in [tool_container, seed_container]:
		container.hide()
	current_container.show()
	for texture in current_container.get_children():
		texture.highlight(target == texture.tool_enum)

func _on_hide_timer_timeout() -> void:
	tool_container.hide()
