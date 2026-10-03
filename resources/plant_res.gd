class_name PlantResource extends Resource

@export var texture: Texture2D
@export var grow_speed := 1
var age: float
var death_count: int
func grow(sprite: Sprite2D):
	age = min(age + grow_speed, sprite.hframes - 1)
	sprite.frame = int(age)
	death_count = 0
func decay(plant: StaticBody2D):
	death_count +=1
	if death_count >= 3:
		plant.queue_free()
