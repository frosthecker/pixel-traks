extends CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _input(event):
	if event.is_action_pressed("inventory"):
		$inventory.visible = true
		$inventory.popup_open()
	elif event.is_action_pressed("back"):
		$inventory.popup_close()
