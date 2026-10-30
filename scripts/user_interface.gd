extends CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _input(event):
	if event.is_action_pressed("back") and $map.is_open:
		$map.close()
		get_viewport().set_input_as_handled()
