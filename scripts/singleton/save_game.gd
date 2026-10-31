extends Node

## Central persistence service. Level scenes provide their own serializable state
## through get_save_data() and apply_save_data().

const SLOT_COUNT := 3
const SAVE_PATH_TEMPLATE := "user://world_slot_%d.save"
const RESUME_PATH := "user://resume.save"
const META_PATH := "user://save_meta.cfg"
const RESUME_INTERVAL_SECONDS := 10.0

var _resume_elapsed := 0.0
var current_slot := 1
var new_world_requested := false

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(META_PATH) == OK:
		current_slot = clampi(int(config.get_value("general", "last_slot", 1)), 1, SLOT_COUNT)

func _process(delta: float) -> void:
	_resume_elapsed += delta
	if _resume_elapsed >= RESUME_INTERVAL_SECONDS:
		_resume_elapsed = 0.0
		save_resume()

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
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_resume()

func slot_path(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(slot_path(slot if slot > 0 else current_slot))

func has_resume() -> bool:
	return FileAccess.file_exists(RESUME_PATH)

func delete_save(slot: int = 0) -> void:
	var target_slot := slot if slot > 0 else current_slot
	if FileAccess.file_exists(slot_path(target_slot)):
		DirAccess.remove_absolute(slot_path(target_slot))
	var config := ConfigFile.new()
	if config.load(META_PATH) == OK:
		config.erase_section_key("slot_%d" % target_slot, "day")
		config.erase_section_key("slot_%d" % target_slot, "saved_at")
		config.save(META_PATH)

func get_world_name(slot: int) -> String:
	var config := ConfigFile.new()
	config.load(META_PATH)
	var saved_name := str(config.get_value("slot_%d" % slot, "name", "")).strip_edges()
	return saved_name if saved_name != "" else "World %d" % slot

func set_world_name(slot: int, new_name: String) -> void:
	var config := ConfigFile.new()
	config.load(META_PATH)
	var clean := new_name.strip_edges()
	if clean == "World %d" % slot:
		clean = ""
	config.set_value("slot_%d" % slot, "name", clean)
	config.save(META_PATH)

func get_slot_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {"exists": false}
	var config := ConfigFile.new()
	config.load(META_PATH)
	var section := "slot_%d" % slot
	return {
		"exists": true,
		"day": int(config.get_value(section, "day", 1)),
		"saved_at": int(config.get_value(section, "saved_at", 0)),
	}

func save_game(level_override: Node = null, slot: int = 0) -> bool:
	var target_slot := slot if slot > 0 else current_slot
	if target_slot < 1 or target_slot > SLOT_COUNT:
		return false
	var level := level_override if level_override != null else _get_level()
	if level == null:
		return false
	if not bool(level.get("world_boot_complete")):
		return false

	var payload := _build_payload(level, target_slot)
	if not _write_compressed(slot_path(target_slot), payload):
		return false

	current_slot = target_slot
	var level_data: Dictionary = payload["level"]
	var time_data: Dictionary = level_data.get("world_time", {})
	_write_meta(target_slot, int(time_data.get("day_count", 1)))
	print("Game saved to ", slot_path(target_slot))
	return true

func save_resume(level_override: Node = null) -> bool:
	var level := level_override if level_override != null else _get_level()
	if level == null:
		return false
	if not bool(level.get("world_boot_complete")):
		return false
	return _write_compressed(RESUME_PATH, _build_payload(level, current_slot))

func load_game(level_override: Node = null, slot: int = 0) -> bool:
	var target_slot := slot if slot > 0 else current_slot
	if not has_save(target_slot):
		return false
	var save_data := _read_compressed(slot_path(target_slot))
	if save_data.is_empty():
		return false
	current_slot = target_slot
	if _apply_payload(save_data, level_override):
		print("Game loaded from ", slot_path(target_slot))
		return true
	return false

func load_resume(level_override: Node = null) -> bool:
	if not has_resume():
		return false
	var save_data := _read_compressed(RESUME_PATH)
	if save_data.is_empty():
		return false
	current_slot = clampi(int(save_data.get("slot", 0)), 0, SLOT_COUNT)
	if _apply_payload(save_data, level_override):
		print("Game resumed from ", RESUME_PATH)
		return true
	return false

func _build_payload(level: Node, slot: int) -> Dictionary:
	return {
		"version": 1,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"slot": slot,
		"level": level.get_save_data(),
		"inventory": PlayerInventory.get_save_data()
	}

func _write_compressed(path: String, payload: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open_compressed(temp_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not open save file: %s" % temp_path)
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK

func _read_compressed(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not open save file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Save file contains invalid JSON.")
		return {}
	return parsed

func _apply_payload(save_data: Dictionary, level_override: Node) -> bool:
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
		return true
	return false

func _write_meta(slot: int, day: int) -> void:
	var config := ConfigFile.new()
	config.load(META_PATH)
	config.set_value("general", "last_slot", slot)
	config.set_value("slot_%d" % slot, "day", day)
	config.set_value("slot_%d" % slot, "saved_at", int(Time.get_unix_time_from_system()))
	config.save(META_PATH)

func _get_level() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_save_data") and scene.has_method("apply_save_data"):
		return scene
	return null
