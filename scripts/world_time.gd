extends Node

signal time_changed(minutes: int)

@export var day_length_seconds: float = 180.0
@export_range(0, 1439) var start_minutes: int = 360

var current_minutes: int
var day_count: int = 1
var _last_emitted_minute: int = -1
var _minute_progress: float

func _ready() -> void:
	current_minutes = start_minutes
	_minute_progress = float(start_minutes)
	_last_emitted_minute = current_minutes

func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var minutes_per_second: float = 1440.0 / day_length_seconds
	var previous_minutes := current_minutes
	_minute_progress = fmod(_minute_progress + minutes_per_second * delta, 1440.0)
	current_minutes = int(_minute_progress)
	if current_minutes < previous_minutes:
		day_count += 1
	if current_minutes != _last_emitted_minute:
		_last_emitted_minute = current_minutes
		time_changed.emit(current_minutes)

func get_current_minutes() -> int:
	return current_minutes

func set_time(minutes: int) -> void:
	current_minutes = posmod(minutes, 1440)
	_minute_progress = float(current_minutes)
	_last_emitted_minute = current_minutes
	time_changed.emit(current_minutes)

func format_time() -> String:
	return "%02d:%02d" % [current_minutes / 60, current_minutes % 60]
