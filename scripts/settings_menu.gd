extends Node2D

## Settings are kept outside save games so they apply to every character/save slot.
const SETTINGS_PATH := "user://settings.cfg"

const DEFAULTS := {

	"video": {
		"fullscreen": false,
		"vsync": true,
		"screen_shake": true,
	},
	"accessibility": {
		"reduced_motion": false,
		"high_contrast": false,
		"text_scale": 100,
	},
	"audio": {
		"master_volume": 100,
	},
}

@onready var option_list: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var save_button: TextureButton = $save/save
@onready var reset_button: TextureButton = $save/reset
@onready var save_label: Label = $save/save/Label
@onready var category_buttons: Dictionary = {
	"video": $HBoxContainer/video,
	"accessibility": $HBoxContainer/accessibility,
	"controls": $HBoxContainer/controls,
	"audio": $HBoxContainer/audio,
}

var settings: Dictionary = DEFAULTS.duplicate(true)
var current_category := "video"
var active_options: Array[Dictionary] = []


func _ready() -> void:
	_load_settings()
	_apply_settings()

	for category in category_buttons:
		(category_buttons[category] as TextureButton).pressed.connect(_show_category.bind(category))

	var rows := option_list.get_children()
	for index in rows.size():
		var row := rows[index] as TextureButton
		row.pressed.connect(_activate_option.bind(index))
		_add_row_label(row)

	save_button.pressed.connect(_save_settings)
	reset_button.pressed.connect(_reset_settings)
	_show_category(current_category)


func _show_category(category: String) -> void:
	current_category = category
	active_options = _options_for(category)
	var rows := option_list.get_children()
	for index in rows.size():
		var row := rows[index] as TextureButton
		var has_option := index < active_options.size()
		row.visible = has_option
		row.disabled = not has_option or not active_options[index].get("interactive", true)
		if has_option:
			_set_row_text(row, active_options[index].get("text", ""))


func _options_for(category: String) -> Array[Dictionary]:
	match category:
		"video":
			return [
				_toggle_option("Fullscreen", "video", "fullscreen"),
				_toggle_option("VSync", "video", "vsync"),
				_toggle_option("Screen shake", "video", "screen_shake"),
			]
		"accessibility":
			return [
				_toggle_option("Reduced motion", "accessibility", "reduced_motion"),
				_toggle_option("High contrast", "accessibility", "high_contrast"),
				{
					"text": "Text scale: %d%%" % int(settings.accessibility.text_scale),
					"section": "accessibility", "key": "text_scale", "interactive": true,
				}
			]
		"controls":
			return [
				_read_only_option("Move: W A S D"),
				_read_only_option("Action: Space"),
				_read_only_option("Inventory: E"),
				_read_only_option("Interact: R"),
				_read_only_option("Harvest: P"),
				_read_only_option("Tools / seeds: Q / C"),
				_read_only_option("Close menu: Esc"),
			]
		"audio":
			return [{
				"text": "Master volume: %d%%" % int(settings.audio.master_volume),
				"section": "audio", "key": "master_volume", "interactive": true,
			}]
	return []


func _toggle_option(title: String, section: String, key: String) -> Dictionary:
	return {
		"text": "%s: %s" % [title, "On" if settings[section][key] else "Off"],
		"section": section, "key": key, "interactive": true,
	}


func _read_only_option(text: String) -> Dictionary:
	return {"text": text, "interactive": false}


func _activate_option(index: int) -> void:
	if index >= active_options.size():
		return
	var option := active_options[index]
	if not option.get("interactive", false):
		return

	var section: String = option.section
	var key: String = option.key
	if key == "text_scale":
		var scales := [100, 125, 150]
		var current := scales.find(int(settings[section][key]))
		settings[section][key] = scales[(current + 1) % scales.size()]
	elif key == "master_volume":
		settings[section][key] = posmod(int(settings[section][key]) + 10, 110)
	else:
		settings[section][key] = not settings[section][key]

	_apply_settings()
	_show_category(current_category)


func _apply_settings() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if settings.video.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.video.vsync else DisplayServer.VSYNC_DISABLED
	)

	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		var volume_percent: float = float(settings.audio.master_volume)
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(volume_percent / 100.0, 0.001)))

	# These values are persistent now, ready for game/UI systems to consume as
	# they are added. Text scale is applied directly to this menu immediately.
	var scale_factor := float(settings.accessibility.text_scale) / 100.0
	option_list.scale = Vector2.ONE * scale_factor
	option_list.position = Vector2.ZERO
	if settings.accessibility.high_contrast:
		modulate = Color(1.15, 1.15, 1.15, 1.0)
	else:
		modulate = Color.WHITE


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			settings[section][key] = config.get_value(section, key, DEFAULTS[section][key])


func _save_settings() -> void:
	var config := ConfigFile.new()
	for section in settings:
		for key in settings[section]:
			config.set_value(section, key, settings[section][key])
	if config.save(SETTINGS_PATH) == OK:
		save_label.text = "saved"
		get_tree().create_timer(1.2).timeout.connect(func() -> void: save_label.text = "save")


func _reset_settings() -> void:
	settings = DEFAULTS.duplicate(true)
	_apply_settings()
	_show_category(current_category)
	save_label.text = "reset"
	get_tree().create_timer(1.2).timeout.connect(func() -> void: save_label.text = "save")


func _add_row_label(row: TextureButton) -> void:
	var label := Label.new()
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 12.0
	label.offset_right = -12.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)


func _set_row_text(row: TextureButton, text: String) -> void:
	(row.get_node("Label") as Label).text = text
