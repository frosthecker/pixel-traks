extends VBoxContainer

@onready var pages: Control = $pages

func _ready() -> void:
	$ScrollContainer/HBoxContainer/crops.pressed.connect(func(): _show_section("plant_info_container"))
	$ScrollContainer/HBoxContainer/traders.pressed.connect(func(): _show_section("traders"))
	$ScrollContainer/HBoxContainer/friends.pressed.connect(func(): _show_section("friends"))
	$ScrollContainer/HBoxContainer/tasks.pressed.connect(func(): _show_section("tasks"))
	_show_section("plant_info_container")

func _show_section(section_name: String) -> void:
	for page in pages.get_children():
		if page is CanvasItem:
			page.visible = page.name == section_name
