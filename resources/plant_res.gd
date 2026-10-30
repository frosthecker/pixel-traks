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

func setup(seed_enum: Enum.Seed):
	texture = load(Data.PLANT_DATA[seed_enum]['texture'])
	icon_texture = load(Data.PLANT_DATA[seed_enum]['icon_texture'])
	grow_speed = Data.PLANT_DATA[seed_enum]['grow_speed']
	h_frames = Data.PLANT_DATA[seed_enum]['h_frames']
	death_max = Data.PLANT_DATA[seed_enum]['death_max']
	name = 	Data.PLANT_DATA[seed_enum]['name']
func grow(sprite: Sprite2D):
	age = min(age + grow_speed, h_frames)
	sprite.frame = int(age)
	death_count = 0
	
func decay(plant: StaticBody2D):
	death_count +=1
	if death_count >= death_max:
		emit_changed()
		plant.queue_free()
		

func get_complete():
	return age >= h_frames
