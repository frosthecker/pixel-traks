extends Node

signal time_changed(minutes: int)

const HOURS_PER_DAY := 24
const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := HOURS_PER_DAY * MINUTES_PER_HOUR

# One in-game day takes one real day: each displayed minute lasts 60 seconds.
@export var day_length_seconds: float = float(MINUTES_PER_DAY * MINUTES_PER_HOUR)
@export_range(0, 1439) var start_minutes: int = 360

var current_minutes: int
var current_hour: int
var current_minute: int
var day_count: int = 1
var _last_emitted_minute: int = -1
var _minute_progress: float

func _ready() -> void:
	set_time(start_minutes)

func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var minutes_per_second: float = float(MINUTES_PER_DAY) / day_length_seconds
	var total_progress := _minute_progress + minutes_per_second * delta
	var completed_days := int(floor(total_progress / float(MINUTES_PER_DAY)))
	if completed_days > 0:
		day_count += completed_days
	_minute_progress = fmod(total_progress, float(MINUTES_PER_DAY))
	current_minutes = int(_minute_progress)
	_sync_clock_components()
	if current_minutes != _last_emitted_minute:
		_last_emitted_minute = current_minutes
		time_changed.emit(current_minutes)

func get_current_minutes() -> int:
	return current_minutes

func set_time(minutes: int) -> void:
	current_minutes = posmod(minutes, MINUTES_PER_DAY)
	_minute_progress = float(current_minutes)
	_sync_clock_components()
	_last_emitted_minute = current_minutes
	time_changed.emit(current_minutes)

func format_time() -> String:
	return "%02d:%02d" % [current_hour, current_minute]


func _sync_clock_components() -> void:
	current_hour = current_minutes / MINUTES_PER_HOUR
	current_minute = current_minutes % MINUTES_PER_HOUR
