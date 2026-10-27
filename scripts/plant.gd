extends StaticBody2D

var coord: Vector2i
var player_inside := false
var item_name

@export var res: PlantResource
@onready var sprite_2d: Sprite2D = $outline_sprite
signal death(coord: Vector2i)
func _ready() -> void:
	sprite_2d.set_outline_visible(false)
	# Plant data uses a title-cased display name, whereas ItemData.json uses
	# lowercase IDs (for example, "Beetroot" -> "beetroot").
	item_name = res.name.to_lower()

func setup(grid_coord: Vector2i, parent: Node2D, new_res: PlantResource, plant_death_func):
	position = grid_coord * Data.TILE_SIZE + Vector2i(8,6)
	coord = grid_coord
	res = new_res
	death.connect(plant_death_func)
	# Adding the node runs _ready(), which derives item_name from res.
	# Assign the configured resource first so harvests never use the empty
	# default resource stored on the scene.
	parent.add_child(self)
	sprite_2d.texture = res.texture
	# Crop textures are four-frame horizontal spritesheets. The resource's
	# h_frames value is the last valid frame index, so add one for hframes.
	sprite_2d.hframes = res.h_frames + 1
	sprite_2d.vframes = 1
	sprite_2d.frame = 0
func grow(watered: bool):
	if watered:
		res.grow(sprite_2d)
	else:
		res.decay(self)

func _unhandled_input(event: InputEvent) -> void:
	if player_inside and res.get_complete() and event.is_action_pressed("pick"):
		PlayerInventory.add_item(item_name, 1)
		queue_free()
		death.emit(coord)
		res.dead = true
	
func _on_collision_area_body_entered(_body: Node2D) -> void:
	player_inside = true
	if res.get_complete():
		sprite_2d.set_outline_visible(true)

func _on_collision_area_body_exited(_body: Node2D) -> void:
	player_inside = false
	sprite_2d.set_outline_visible(false)
