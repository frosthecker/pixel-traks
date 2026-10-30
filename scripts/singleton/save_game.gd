extends Node

## Central persistence service. Level scenes provide their own serializable state
## through get_save_data() and apply_save_data().

const SLOT_COUNT := 3
const SAVE_PATH_TEMPLATE := "user://world_slot_%d.save"
const META_PATH := "user://save_meta.cfg"

var current_slot := 1
var new_world_requested := false

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(META_PATH) == OK:
		current_slot = clampi(int(config.get_value("general", "last_slot", 1)), 1, SLOT_COUNT)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		save_game()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_L:
		load_game()
		get_viewport().set_input_as_handled()

func slot_path(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(slot_path(slot if slot > 0 else current_slot))

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

	var level_data: Dictionary = level.get_save_data()
	var save_data: Dictionary = {
		"version": 1,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"slot": target_slot,
		"level": level_data,
		"inventory": PlayerInventory.get_save_data()
	}
	var file := FileAccess.open_compressed(slot_path(target_slot), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not open save file: %s" % slot_path(target_slot))
		return false
	file.store_string(JSON.stringify(save_data))
	file.close()

	current_slot = target_slot
	var time_data: Dictionary = level_data.get("world_time", {})
	_write_meta(target_slot, int(time_data.get("day_count", 1)))
	print("Game saved to ", slot_path(target_slot))
	return true

func load_game(level_override: Node = null, slot: int = 0) -> bool:
	var target_slot := slot if slot > 0 else current_slot
	if not has_save(target_slot):
		return false

	var file := FileAccess.open_compressed(slot_path(target_slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not open save file: %s" % slot_path(target_slot))
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

	current_slot = target_slot
	var inventory_data: Variant = save_data.get("inventory", {})
	if inventory_data is Dictionary:
		PlayerInventory.load_save_data(inventory_data)

	var level := level_override if level_override != null else _get_level()
	var level_data: Variant = save_data.get("level", {})
	if level != null and level_data is Dictionary:
		level.apply_save_data(level_data)
		print("Game loaded from ", slot_path(target_slot))
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
