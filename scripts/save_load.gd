extends Node2D

@onready var save_button: TextureButton = $ScrollContainer/VBoxContainer/slot1
@onready var load_button: TextureButton = $ScrollContainer/VBoxContainer/slot2
@onready var save_label: Label = $ScrollContainer/VBoxContainer/slot1/Label
@onready var load_label: Label = $ScrollContainer/VBoxContainer/slot2/Label


func _ready() -> void:
	save_button.pressed.connect(_save_game)
	load_button.pressed.connect(_load_game)
	for slot_number in range(3, 7):
		var slot := get_node("ScrollContainer/VBoxContainer/slot%d" % slot_number) as TextureButton
		slot.disabled = true
		(slot.get_node("Label") as Label).text = "Unavailable"
	_update_slot_labels()


func _save_game() -> void:
	SaveGame.save_game()
	_update_slot_labels()


func _load_game() -> void:
	SaveGame.load_game()
	_update_slot_labels()


func _update_slot_labels() -> void:
	save_label.text = "Save Game"
	load_label.text = "Load Game" if SaveGame.has_save() else "No Save Found"
	load_button.disabled = not SaveGame.has_save()
