class_name GameSettings
extends RefCounted

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

static var values: Dictionary = {}


static func ensure_loaded() -> void:
	if not values.is_empty():
		return
	values = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			values[section][key] = config.get_value(section, key, DEFAULTS[section][key])


static func get_value(section: String, key: String) -> Variant:
	ensure_loaded()
	return values[section][key]
