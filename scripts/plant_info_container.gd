extends Control

@onready var v_box_container: VBoxContainer = $MarginContainer/ScrollContainer/VBoxContainer


func add(child: PanelContainer):
	v_box_container.add_child(child)
	
func update_all():
	for plant_info in v_box_container.get_children():
		plant_info.update()
		
