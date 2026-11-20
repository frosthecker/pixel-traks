extends Node2D

## Placeable sprinkler. The level owns the actual watering logic so automation
## also works for NPC-grown crops; this node only stores placement metadata and
## draws a tiny animated marker.

var coord: Vector2i
var machine_type: int = Enum.Machine.SPRINKLER
var radius: int = 2
var _spin := 0.0

func _ready() -> void:
	add_to_group("FarmMachines")
	z_index = 1

func setup(grid_coord: Vector2i, parent: Node2D, new_radius: int = 2) -> void:
	coord = grid_coord
	radius = new_radius
	position = grid_coord * Data.TILE_SIZE + Vector2i(8, 7)
	parent.add_child(self)

func _process(delta: float) -> void:
	_spin = fmod(_spin + delta * 2.2, TAU)
	queue_redraw()

func _draw() -> void:
	# Small metal post and base.
	draw_rect(Rect2(-2, -3, 4, 10), Color(0.36, 0.38, 0.44))
	draw_rect(Rect2(-6, 6, 12, 2), Color(0.23, 0.24, 0.29))
	# Rotating water arms.
	for i in range(4):
		var angle := _spin + float(i) * PI / 2.0
		var tip := Vector2.from_angle(angle) * 6.0 + Vector2(0, -4)
		draw_line(Vector2(0, -4), tip, Color(0.42, 0.74, 1.0), 1.5)
	# Nozzle highlight.
	draw_circle(Vector2(0, -4), 2.5, Color(0.68, 0.88, 1.0))
