extends PanelContainer

var res: PlantResource
@onready var name_label: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var icon_texture: TextureRect = $HBoxContainer/IconTexture
@onready var growth_bar: TextureProgressBar = $HBoxContainer/VBoxContainer/GrowthBar
@onready var death_bar: TextureProgressBar = $HBoxContainer/VBoxContainer/DeathBar

func setup(new_res: PlantResource):
	res = new_res
	name_label.text = res.name
	icon_texture.texture = res.icon_texture
	growth_bar.max_value = res.h_frames
	death_bar.max_value = res.death_max
	update()
	res.connect('changed', queue_free)
func update():
	growth_bar.value = res.age
	death_bar.value = res.death_count
