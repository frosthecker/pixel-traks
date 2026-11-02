extends VideoStreamPlayer

# This allows you to select your main menu file directly in the Inspector
@export_file("*.tscn") var next_scene: String

func _ready() -> void:
	# Connect the signal that detects when the video finishes
	finished.connect(_on_video_finished)

func _on_video_finished() -> void:
	# If a scene path is assigned in the Inspector, load it
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
	else:
		push_error("Next scene is not assigned in the Inspector!")
