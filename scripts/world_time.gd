extends Node

signal time_changed(minutes: int)
signal season_changed(season: int, day_of_season: int)

const HOURS_PER_DAY := 24
const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := HOURS_PER_DAY * MINUTES_PER_HOUR
const DAYS_PER_SEASON := 12

# One in-game day takes one real day: each displayed minute lasts 60 seconds.
@export var day_length_seconds: float = float(MINUTES_PER_DAY * MINUTES_PER_HOUR)
@export_range(0, 1439) var start_minutes: int = 360
@export_range(1, 120) var days_per_season: int = DAYS_PER_SEASON

var current_minutes: int
var current_hour: int
var current_minute: int
var day_count: int = 1
var current_season: int = Enum.Season.SPRING
var day_of_season: int = 1
var _season_initialized := false
var _last_emitted_minute: int = -1
var _minute_progress: float

func _ready() -> void:
	set_time(start_minutes)
	_refresh_season(false)

func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var minutes_per_second: float = float(MINUTES_PER_DAY) / day_length_seconds
	var total_progress := _minute_progress + minutes_per_second * delta
	var completed_days := int(floor(total_progress / float(MINUTES_PER_DAY)))
	if completed_days > 0:
		advance_days(completed_days)
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

## Advances the calendar by one or more days, which is what moves seasons
## forward. Levels call this when the player sleeps/ends the day.
func advance_days(count: int = 1) -> void:
	if count <= 0:
		return
	day_count += count
	_refresh_season()

func set_day_count(new_day: int, announce_season := false) -> void:
	day_count = maxi(1, new_day)
	_refresh_season(announce_season)

func get_season_name() -> String:
	return Data.season_name(current_season)

func format_date() -> String:
	return "%s %d" % [get_season_name(), day_of_season]

func format_time() -> String:
	return "%02d:%02d" % [current_hour, current_minute]


func _refresh_season(announce := true) -> void:
	var safe_days := maxi(1, days_per_season)
	var season_count := maxi(1, Enum.Season.size())
	var new_season := int(floor(float(day_count - 1) / float(safe_days))) % season_count
	var changed := new_season != current_season
	current_season = new_season
	day_of_season = ((day_count - 1) % safe_days) + 1
	if announce and changed and _season_initialized:
		season_changed.emit(current_season, day_of_season)
	_season_initialized = true

func _sync_clock_components() -> void:
	current_hour = current_minutes / MINUTES_PER_HOUR
	current_minute = current_minutes % MINUTES_PER_HOUR
