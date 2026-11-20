class_name PlantResource extends Resource

@export var texture: Texture2D
@export var icon_texture: Texture2D
@export var grow_speed: float
@export var h_frames: int = 3
@export var death_max: int = 3
@export var name: String


var age: float
var death_count: int
var dead: bool:
	set(value):
		dead = value
		emit_changed()

## Bookkeeping used by the farming expansion. It lives on the resource so the
## level can save and restore crops without touching the plant scene.
var seed: int = -1
var quality: int = Enum.Quality.NORMAL
var care_days: int = 0
var watered_days: int = 0
var _quality_rolled := false

func setup(seed_enum: Enum.Seed):
	seed = int(seed_enum)
	texture = load(Data.PLANT_DATA[seed_enum]['texture'])
	icon_texture = load(Data.PLANT_DATA[seed_enum]['icon_texture'])
	grow_speed = Data.PLANT_DATA[seed_enum]['grow_speed']
	h_frames = Data.PLANT_DATA[seed_enum]['h_frames']
	death_max = Data.PLANT_DATA[seed_enum]['death_max']
	name = 	Data.PLANT_DATA[seed_enum]['name']

## Called once per day before growth/decay so quality can tell how diligent the
## player was. Watered days should always be a subset of care days.
func tick_care(watered: bool) -> void:
	care_days += 1
	if watered:
		watered_days += 1

func grow(sprite: Sprite2D, season: int):
	age = min(age + grow_speed * Data.season_growth_multiplier(season), h_frames)
	sprite.frame = int(age)
	death_count = 0
	if get_complete():
		_roll_quality()

func decay(plant: StaticBody2D):
	death_count +=1
	if death_count >= death_max:
		emit_changed()
		plant.queue_free()

func get_complete():
	return age >= h_frames

func is_in_season(season: int) -> bool:
	return Data.seed_in_season(seed, season)

func get_care_ratio() -> float:
	return float(watered_days) / maxf(1.0, float(care_days))

## Quality is determined when the crop finishes growing, based on consistency
## of watering and the player's farming level. It is stored so the plant info
## panel and the harvest use the same result.
func _roll_quality() -> void:
	if _quality_rolled:
		return
	_quality_rolled = true
	var score := get_care_ratio() * 60.0
	score += float(FarmState.farming_level) * 4.0
	score += randf_range(0.0, 20.0)
	if score >= 90.0:
		quality = Enum.Quality.IRIDIUM
	elif score >= 72.0:
		quality = Enum.Quality.GOLD
	elif score >= 48.0:
		quality = Enum.Quality.SILVER
	else:
		quality = Enum.Quality.NORMAL

func get_quality_name() -> String:
	return Data.quality_name(quality)

func get_quality_stars() -> String:
	return Data.quality_stars(quality)

func get_display_name() -> String:
	if get_complete() and quality > Enum.Quality.NORMAL:
		return "%s %s" % [name, get_quality_stars()]
	return name

func get_harvest_amount() -> int:
	## Iridium crops are bountiful enough to yield an extra unit.
	if quality >= Enum.Quality.IRIDIUM:
		return 2
	return 1

func get_sell_multiplier() -> float:
	return Data.quality_multiplier(quality)
