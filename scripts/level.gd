extends Node2D


var plant_scene = preload("res://scenes/objects/plant.tscn")
var used_cells: Array[Vector2i]
@onready var player: CharacterBody2D = $Objects/Player
@export var daytime_color: Gradient
@onready var day_timer: Timer = $Timers/DayTimer
@onready var day_time_color: CanvasModulate = $Overlay/DayTimeColor
@onready var day_transition_layer_material = $Overlay/CanvasLayer/DayTransitionLayer.material
@onready var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer

func _on_player_tool_use(tool: Enum.Tool, pos: Vector2, dir) -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
	var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
	# var grid_coord: Vector2i = light_dirt_layer.local_to_map(light_dirt_layer.to_local(pos))
	var grid_coord: Vector2i = Vector2i(int(pos.x / Data.TILE_SIZE), int(pos.y / Data.TILE_SIZE))
	grid_coord.x += -1 if pos.x < 0 else 0
	grid_coord.y += -1 if pos.y < 0 else 0
	var has_soil = grid_coord in $Layers/GrassLayer.get_used_cells()
	var tile_adjuster: Vector2i = Vector2i(1,0)
	match tool:
		Enum.Tool.HOE:
			var cell = $Layers/GrassLayer.get_cell_tile_data(grid_coord)
			if cell and cell.get_custom_data('farmable'):
				
				var connected_cells: Array[Vector2i] = [grid_coord]
				for y in range(-1, 2):
					for x in range(-1, 2):
						if x == 0 and y == 0:
							continue
						var neighbor := grid_coord + Vector2i(x, y)
						if light_dirt_layer.get_cell_source_id(neighbor) != -1:
							connected_cells.append(neighbor)

				# An isolated cell must start as a complete dirt tile. Once it has
				# a dirt neighbor, terrain-connect can safely create the borders.
				light_dirt_layer.set_cell(grid_coord, 0, Vector2i(6, 35), 0)
				if connected_cells.size() > 1:
					light_dirt_layer.set_cells_terrain_connect(connected_cells, 0, 1)
		Enum.Tool.WATER:
		
			
			var cell = light_dirt_layer.get_cell_tile_data(grid_coord)
			if cell:
				var dark_coord: Vector2i = dark_dirt_layer.local_to_map(dark_dirt_layer.to_local(pos))
				var connected_cells: Array[Vector2i] = [dark_coord]
				for y in range(-1, 2):
					for x in range(-1, 2):
						if x == 0 and y == 0:
							continue
						var neighbor := dark_coord + Vector2i(x, y)
						if dark_dirt_layer.get_cell_source_id(neighbor) != -1:
							connected_cells.append(neighbor)

				# Terrain-connect cannot create an isolated terrain reliably.
				# Place the complete dark-dirt tile first, then connect neighbors.
				if dir:
					dark_dirt_layer.set_cell(dark_coord + tile_adjuster*(-1), 0, Vector2i(12, 7), 0)
					print(dir)
				else:
					dark_dirt_layer.set_cell(dark_coord + tile_adjuster, 0, Vector2i(12, 7), 0)
					print(dir)
				if connected_cells.size() > 1:
					dark_dirt_layer.set_cells_terrain_connect(connected_cells, 0, 3)
		Enum.Tool.FISH:
			if has_soil:
				print('fishing')
		Enum.Tool.SEED:
			if has_soil and grid_coord not in used_cells:
				var plant = plant_scene.instantiate()
				plant.setup(grid_coord, $Objects)
				used_cells.append(grid_coord)
		Enum.Tool.AXE, Enum.Tool.SWORD:
			for object in get_tree().get_nodes_in_group('Objects'):
				if object.position.distance_to(pos) < 20:
					object.hit(tool)
			
func _process(delta: float) -> void:
		var daytime_point = 1 - (day_timer.time_left / day_timer.wait_time)
		var color = daytime_color.sample(daytime_point)
		day_time_color.color = color
		if Input.is_action_just_pressed("day_change"):
			day_restart()

func day_restart():
	var tween = create_tween()
	tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 1.0, 1.0)	
	tween.tween_interval(0.5)
	tween.tween_callback(level_reset)
	tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, 1.0)	

func level_reset():
	for plant in get_tree().get_nodes_in_group('Plants'):
		plant.grow(plant.coord in dark_dirt_layer.get_used_cells())
	dark_dirt_layer.clear()
	print('level reset')
	day_timer.start()
