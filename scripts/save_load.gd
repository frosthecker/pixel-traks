extends Node2D

const WORLD_SLOTS := 3
const MODE_SLOT := 4
const NEW_WORLD_SLOT := 5
const STATUS_SLOT := 6
const MAX_NAME_LENGTH := 12
const MODE_SAVE := 0
const MODE_LOAD := 1
const MODE_RENAME := 2
const MODE_LABELS := ["Mode: Save", "Mode: Load", "Mode: Rename"]

var _mode := MODE_SAVE
var _pending := 0
var _busy := false
var _name_edit: LineEdit


func _ready() -> void:
	for number in range(1, STATUS_SLOT + 1):
		_slot(number).pressed.connect(_on_slot_pressed.bind(number))
	visibility_changed.connect(_refresh)
	_refresh()


func _slot(number: int) -> TextureButton:
	return get_node("ScrollContainer/VBoxContainer/slot%d" % number) as TextureButton


func _label(number: int) -> Label:
	return _slot(number).get_node("Label") as Label


func _refresh() -> void:
	_pending = 0
	for number in range(1, WORLD_SLOTS + 1):
		var info: Dictionary = SaveGame.get_slot_info(number)
		var text := SaveGame.get_world_name(number)
		if info.exists:
			text += " - Day %d" % info.day
		else:
			text += " - Empty"
		if number == SaveGame.current_slot:
			text = "> " + text
		_label(number).text = text
		_slot(number).disabled = _busy
	_label(MODE_SLOT).text = MODE_LABELS[_mode]
	_label(NEW_WORLD_SLOT).text = "New World"
	if SaveGame.has_save():
		_label(STATUS_SLOT).text = "Playing: %s" % SaveGame.get_world_name(SaveGame.current_slot)
	else:
		_label(STATUS_SLOT).text = "Playing: unsaved"
	_slot(MODE_SLOT).disabled = _busy
	_slot(NEW_WORLD_SLOT).disabled = _busy
	_slot(STATUS_SLOT).disabled = true


func _on_slot_pressed(number: int) -> void:
	if _busy:
		return
	_close_name_edit()
	var level := get_tree().current_scene
	if level == null or not level.has_method("load_world"):
		return

	if number <= WORLD_SLOTS:
		match _mode:
			MODE_SAVE:
				_save_into(number)
			MODE_LOAD:
				if not SaveGame.has_save(number):
					_flash(number, "Empty")
					return
				_busy = true
				_refresh()
				await level.load_world(number)
				_busy = false
				_refresh()
			MODE_RENAME:
				_open_name_edit(number)
	elif number == MODE_SLOT:
		_mode = (_mode + 1) % MODE_LABELS.size()
		_refresh()
	elif number == NEW_WORLD_SLOT:
		if _pending != number:
			_ask_confirm(number, "Press again to confirm")
			return
		_busy = true
		_refresh()
		await level.start_new_world()
		_busy = false
		_refresh()


func _save_into(number: int) -> void:
	var info: Dictionary = SaveGame.get_slot_info(number)
	var replaces_other: bool = info.exists and number != SaveGame.current_slot
	if replaces_other and _pending != number:
		_ask_confirm(number, "Overwrite? Press again")
		return
	var saved := SaveGame.save_game(null, number)
	_refresh()
	_flash(number, "Saved" if saved else "Failed")


func _open_name_edit(number: int) -> void:
	var edit := LineEdit.new()
	edit.max_length = MAX_NAME_LENGTH
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.text = SaveGame.get_world_name(number)
	edit.text_submitted.connect(_on_name_submitted.bind(number))
	edit.focus_exited.connect(_close_name_edit)
	edit.gui_input.connect(_on_name_edit_input)
	_slot(number).add_child(edit)
	edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit.grab_focus()
	edit.select_all()
	_name_edit = edit


func _on_name_submitted(text: String, number: int) -> void:
	SaveGame.set_world_name(number, text)
	_close_name_edit()


func _on_name_edit_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_name_edit()


func _close_name_edit() -> void:
	if _name_edit == null:
		return
	var edit := _name_edit
	_name_edit = null
	edit.queue_free()
	_refresh()


func _ask_confirm(number: int, text: String) -> void:
	_refresh()
	_pending = number
	_label(number).text = text
	get_tree().create_timer(2.5).timeout.connect(_cancel_pending.bind(number))


func _cancel_pending(number: int) -> void:
	if _pending == number:
		_refresh()


func _flash(number: int, text: String) -> void:
	_label(number).text = text
	get_tree().create_timer(1.2).timeout.connect(_refresh)
