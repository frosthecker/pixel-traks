extends StaticBody2D

var coord: Vector2i

func setup(grid_coord: Vector2i, parent: Node2D):
	position = grid_coord * Data.TILE_SIZE + Vector2i(8,6)
	parent.add_child(self)
	coord = grid_coord
