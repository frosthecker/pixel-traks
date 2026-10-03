class_name PlantResource extends Resource

@export var texture: Texture2D
@export var grow_speed: float
@export var h_frames: int = 3
@export var death_max: int = 3
var age: float
var death_count: int

func setup(seed_enum: Enum.Seed):
	texture = load(Data.PLANT_DATA[seed_enum]['texture'])
	grow_speed = Data.PLANT_DATA[seed_enum]['grow_speed']
	h_frames = Data.PLANT_DATA[seed_enum]['h_frames']
	death_max = Data.PLANT_DATA[seed_enum]['death_max']
	
func grow(sprite: Sprite2D):
	age = min(age + grow_speed, h_frames)
	sprite.frame = int(age)
	death_count = 0
func decay(plant: StaticBody2D):
	death_count +=1
	if death_count >= death_max:
		plant.queue_free()
