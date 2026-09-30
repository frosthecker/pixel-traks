extends Node2D




func _on_player_tool_use(tool: Enum.Tool, pos: Vector2) -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
	var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
	var grid_coord: Vector2i = light_dirt_layer.local_to_map(light_dirt_layer.to_local(pos))
	match tool:
		Enum.Tool.HOE:
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
				dark_dirt_layer.set_cell(dark_coord, 0, Vector2i(12, 7), 0)
				if connected_cells.size() > 1:
					dark_dirt_layer.set_cells_terrain_connect(connected_cells, 0, 3)
