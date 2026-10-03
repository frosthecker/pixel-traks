extends StaticBody2D

var coord: Vector2i

@export var res: PlantResource
@onready var sprite_2d: Sprite2D = $Sprite2D

func setup(grid_coord: Vector2i, parent: Node2D):
	position = grid_coord * Data.TILE_SIZE + Vector2i(8,6)
	parent.add_child(self)
	coord = grid_coord
	sprite_2d.texture = res.texture
