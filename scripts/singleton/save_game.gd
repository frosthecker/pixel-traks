extends Node

## Central persistence service. Level scenes provide their own serializable state
## through get_save_data() and apply_save_data().

const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_INTERVAL_SECONDS := 60.0

var _autosave_elapsed := 0.0
var new_world_requested := false

func _process(delta: float) -> void:
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed = 0.0
		save_game()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		save_game()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_L:
		load_game()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func save_game(level_override: Node = null) -> bool:
	var level := level_override if level_override != null else _get_level()
	if level == null:
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file: %s" % SAVE_PATH)
		return false

	var save_data: Dictionary = {
		"version": 1,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"level": level.get_save_data(),
		"inventory": PlayerInventory.get_save_data()
	}
	file.store_string(JSON.stringify(save_data))
	file.close()
	print("Game saved to ", SAVE_PATH)
	return true

func load_game(level_override: Node = null) -> bool:
	if not has_save():
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file: %s" % SAVE_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Save file contains invalid JSON.")
		return false

	var save_data: Dictionary = parsed
	if int(save_data.get("version", 0)) != 1:
		push_error("Save file uses an unsupported version.")
		return false

	var inventory_data: Variant = save_data.get("inventory", {})
	if inventory_data is Dictionary:
		PlayerInventory.load_save_data(inventory_data)

	var level := level_override if level_override != null else _get_level()
	var level_data: Variant = save_data.get("level", {})
	if level != null and level_data is Dictionary:
		level.apply_save_data(level_data)
		print("Game loaded from ", SAVE_PATH)
		return true
	return false

func _get_level() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_save_data") and scene.has_method("apply_save_data"):
		return scene
	return null
