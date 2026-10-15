extends Node

var item_data: Dictionary

# Called when the node enters the scene tree for the first time.
func _ready():
	item_data = LoadData("res://scenes/UI/Data/ItemData.json")

func LoadData(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		print("File does not exist: ", file_path)
		return {}
	
	# Godot 4: Open file directly using FileAccess
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	# Godot 4: Parse the JSON string directly into a Dictionary
	var json_data = JSON.parse_string(json_text)
	
	if json_data is Dictionary:
		return json_data
	else:
		print("Failed to parse JSON or data is not a Dictionary")
		return {}
