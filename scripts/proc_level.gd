extends Node2D

signal world_boot_completed

var plant_scene = preload("res://scenes/objects/plant.tscn")
var log_scene = preload("res://scenes/objects/log.tscn")
var plant_info_scene = preload("res://scenes/UI/panel_container.tscn")
var used_cells: Array[Vector2i]
@onready var player: CharacterBody2D = $Objects/Player
@export var daytime_color: Gradient
@onready var day_timer: Timer = $Timers/DayTimer
@onready var day_time_color: CanvasModulate = $Overlay/DayTimeColor
@onready var day_transition_layer: ColorRect = $Overlay/CanvasLayer/DayTransitionLayer
@onready var day_transition_layer_material: ShaderMaterial = day_transition_layer.material as ShaderMaterial
@onready var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
@onready var plant_info_container: Control = $Overlay/UserInterface/map/pages/worldmap/WorldSections/pages/plant_info_container
var day_transition_tween: Tween

@export var noise_height_text: NoiseTexture2D
@export var noise_tree_text: NoiseTexture2D

@export_group("Forest Generation")
@export var forest_noise_threshold: float = 0.12 ## Noise threshold above which terrain is considered a forest biome
@export var forest_block_size: int = 4 ## Tile grid block size for placing trees
@export var min_tree_distance: int = 3 ## Minimum tile distance between trees to prevent collision overlap
@export var solitary_tree_chance: float = 0.004 ## Chance of occasional lone trees in open plains
@export_range(100, 2000, 25) var max_tree_count: int = 750 ## Keeps scene-tile physics affordable on low-end devices
var tree_frequency: float = 0.12 ## Backward-compatibility alias for forest_noise_threshold

var noise: Noise
var tree_noise: Noise
var width: int = 256
var height: int = 256
var noise_val_arr = []
var world_seed: int

@onready var water: TileMapLayer = $Layers/water
@onready var ground_1: TileMapLayer = $Layers/ground_1
@onready var ground_2: TileMapLayer = $Layers/ground_2
@onready var environment: TileMapLayer = $Objects/environment if has_node("Objects/environment") else $Layers/environment
@onready var cliff: TileMapLayer = $Layers/cliff

var source_id = 0
var water_source_id = 2
var tree_source_id = 2
var water_atlas = Vector2(4,1) #4,1 for normal tile
var tree_atlas = Vector2(0,0)
var sand_atlas = Vector2(6,30)
var land_atlas =  Vector2(6,35)

var sand_tiles_arr = []
var terrain_sand_int = 4

var grass_tiles_arr = []
var terrain_grass_int = 0
var _restored_world_data := false
var world_boot_complete := false
var _daylight_update_elapsed := 0.0
const DAYLIGHT_UPDATE_INTERVAL := 0.1


func _ready() -> void:
	if noise_height_text == null:
		push_error("proc_level requires a NoiseTexture2D assigned to noise_height_text")
		return
	noise = noise_height_text.noise
	if noise_tree_text != null:
		tree_noise = noise_tree_text.noise
	if tree_noise == null:
		tree_noise = FastNoiseLite.new()
		tree_noise.frequency = 0.02
		tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Generation intentionally yields so the loading animation stays responsive.
	# Do not expose the partially populated TileMaps during those yield points.
	_set_world_visible(false)
	# A save contains the generated tile layers, so restoring it must happen
	# instead of generating a fresh map first.  Passing this scene explicitly is
	# important while the loading screen is still the SceneTree's current scene.
	if SaveGame.has_save():
		SaveGame.load_game(self)
		# Saves created before procedural layers were persisted cannot be restored
		# exactly. Generate once to migrate them, then rewrite the save after this
		# scene becomes the current scene.
		if not _restored_world_data:
			await generate_world()
			call_deferred("_save_migrated_world")
	else:
		await generate_world()
	_set_world_visible(true)
	_play_startup_transition()
	world_boot_complete = true
	world_boot_completed.emit()

func _set_world_visible(is_visible: bool) -> void:
	$Layers.visible = is_visible
	$Objects.visible = is_visible

func _save_migrated_world() -> void:
	SaveGame.save_game(self)

func _play_startup_transition() -> void:
	if day_transition_layer_material == null:
		return
	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 1.0)
	var transition := create_tween()
	transition.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, 1.0)
	transition.tween_callback(_finish_day_transition)

func _on_player_tool_use(tool: Enum.Tool, pos: Vector2, dir) -> void:
	_apply_tool_use(tool, pos, dir, player.current_seed, true)

func npc_tool_use(tool: Enum.Tool, pos: Vector2, dir: bool, seed: Enum.Seed) -> void:
	_apply_tool_use(tool, pos, dir, seed, false)

func _apply_tool_use(tool: Enum.Tool, pos: Vector2, dir: bool, seed: Enum.Seed, show_plant_info: bool) -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
	var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
	# Use the tile layer's own coordinate conversion so NPC and player tool
	# positions resolve to the same cell, including when the layer is offset.
	var grid_coord: Vector2i = light_dirt_layer.local_to_map(light_dirt_layer.to_local(pos))
	var has_soil: bool = light_dirt_layer.get_cell_source_id(grid_coord) != -1
	var tile_adjuster: Vector2i = Vector2i(0,0)
	match tool:
		Enum.Tool.HOE:
			# proc_level uses ground_2 for grass; GrassLayer only exists in the
			# hand-authored level scene.
			var grass_layer: TileMapLayer = $Layers/ground_2
			var cell = grass_layer.get_cell_tile_data(grid_coord)
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
				var cell = $Layers/LightDirtLayer.get_cell_tile_data(grid_coord)
				if cell and cell.get_custom_data('seedable'):
					var plant_res = PlantResource.new()
					plant_res.setup(seed)
					var plant = plant_scene.instantiate()
					plant.setup(grid_coord + tile_adjuster, $Objects, plant_res, plant_death)
					used_cells.append(grid_coord)
					print(used_cells)
				
					if show_plant_info:
						var plant_info = plant_info_scene.instantiate()
						plant_info_container.add(plant_info)
						plant_info.setup(plant_res)
				
		Enum.Tool.AXE, Enum.Tool.SWORD:
			for object in get_tree().get_nodes_in_group('Objects'):
				if object.global_position.distance_to(pos) < 24:
					object.hit(tool)
			
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("day_change"):
		day_restart()

	# The procedural level scene may not have a day-color gradient assigned yet.
	if daytime_color == null or day_timer == null or day_time_color == null:
		return
	_daylight_update_elapsed += delta
	if _daylight_update_elapsed < DAYLIGHT_UPDATE_INTERVAL:
		return
	_daylight_update_elapsed = 0.0
	var daytime_point = 1 - (day_timer.time_left / day_timer.wait_time)
	day_time_color.color = daytime_color.sample(daytime_point)

func day_restart() -> void:
	if day_transition_tween and day_transition_tween.is_running():
		return
	if day_transition_layer_material == null:
		push_error("DayTransitionLayer does not have a ShaderMaterial.")
		return

	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 0.0)
	day_transition_tween = create_tween()
	day_transition_tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 1.0, 1.0)
	day_transition_tween.tween_interval(0.5)
	day_transition_tween.tween_callback(level_reset)
	day_transition_tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, 1.0)
	day_transition_tween.tween_callback(_finish_day_transition)

func _finish_day_transition() -> void:
	day_transition_layer.visible = false

func level_reset():
	for plant in get_tree().get_nodes_in_group('Plants'):
		plant.grow(plant.coord in dark_dirt_layer.get_used_cells())
	dark_dirt_layer.clear()
	plant_info_container.update_all()
	print('level reset')
	day_timer.start()

func plant_death(coord: Vector2i):
	used_cells.erase(coord)
	print(used_cells)

func get_save_data() -> Dictionary:
	var trees: Dictionary = {}
	for tree in get_tree().get_nodes_in_group("Objects"):
		if tree.get_script() != null and tree.get_script().resource_path == "res://scripts/tree.gd":
			trees[str(tree.get_path())] = int(tree.health)

	var npcs: Dictionary = {}
	for npc in get_tree().get_nodes_in_group("NPC"):
		npcs[str(npc.get_path())] = {
			"position": _vector_to_data(npc.global_position),
			"last_direction": _vector_to_data(npc.last_direction),
			"behavior_state": npc.behavior_state
		}

	var plants: Array = []
	for plant in get_tree().get_nodes_in_group("Plants"):
		plants.append({
			"coord": _vector_to_data(plant.coord),
			"seed": _seed_for_plant(plant.res),
			"age": plant.res.age,
			"death_count": plant.res.death_count
		})

	var dropped_items: Array = []
	for item in get_tree().get_nodes_in_group("DroppedItems"):
		dropped_items.append({
			"item_name": item.item_name,
			"position": _vector_to_data(item.global_position)
		})

	return {
		"world": {
			"water": _serialize_tile_layer(water),
			"ground_1": _serialize_tile_layer(ground_1),
			"ground_2": _serialize_tile_layer(ground_2),
			"environment": _serialize_tile_layer(environment)
		},
		"player": {
			"position": _vector_to_data(player.global_position),
			"last_direction": _vector_to_data(player.last_direction),
			"current_tool": int(player.current_tool),
			"current_seed": int(player.current_seed),
			"current_style": int(player.current_style)
		},
		"world_time": {
			"minutes": WorldTime.get_current_minutes(),
			"day_count": WorldTime.day_count,
			"day_timer_remaining": day_timer.time_left
		},
		"light_dirt": _serialize_tile_layer($Layers/LightDirtLayer),
		"dark_dirt": _serialize_tile_layer($Layers/DarkDirtLayer),
		"plants": plants,
		"dropped_items": dropped_items,
		"trees": trees,
		"npcs": npcs
	}

func apply_save_data(save_data: Dictionary) -> void:
	var world_data: Variant = save_data.get("world", {})
	if world_data is Dictionary and world_data.has("water") and world_data.has("ground_1") and world_data.has("ground_2") and world_data.has("environment"):
		_restore_tile_layer(water, world_data.get("water", []))
		_restore_tile_layer(ground_1, world_data.get("ground_1", []))
		_restore_tile_layer(ground_2, world_data.get("ground_2", []))
		_restore_tile_layer(environment, world_data.get("environment", []))
		_remove_water_trees()
		_limit_tree_count()
		_restored_world_data = true
	else:
		push_warning("Save game has no generated world data; generating once to migrate this legacy save.")

	var player_data: Variant = save_data.get("player", {})
	if player_data is Dictionary:
		player.global_position = _data_to_vector(player_data.get("position", []))
		player.last_direction = _data_to_vector(player_data.get("last_direction", [0, 1]))
		player.current_tool = int(player_data.get("current_tool", player.current_tool)) as Enum.Tool
		player.current_seed = int(player_data.get("current_seed", player.current_seed)) as Enum.Seed
		player.current_style = int(player_data.get("current_style", player.current_style)) as Enum.Style
		if Data.PLAYER_SKINS.has(player.current_style):
			player.sprite.texture = Data.PLAYER_SKINS[player.current_style]

	var time_data: Variant = save_data.get("world_time", {})
	if time_data is Dictionary:
		WorldTime.day_count = max(1, int(time_data.get("day_count", 1)))
		WorldTime.set_time(int(time_data.get("minutes", WorldTime.start_minutes)))
		var remaining := float(time_data.get("day_timer_remaining", day_timer.wait_time))
		day_timer.start(clampf(remaining, 0.01, day_timer.wait_time))

	_restore_tile_layer($Layers/LightDirtLayer, save_data.get("light_dirt", []))
	_restore_tile_layer($Layers/DarkDirtLayer, save_data.get("dark_dirt", []))
	_restore_trees(save_data.get("trees", {}))
	_restore_npcs(save_data.get("npcs", {}))
	_restore_plants(save_data.get("plants", []))
	_restore_dropped_items(save_data.get("dropped_items", []))

func _serialize_tile_layer(layer: TileMapLayer) -> Array:
	var cells: Array = []
	for coord in layer.get_used_cells():
		var atlas := layer.get_cell_atlas_coords(coord)
		cells.append({
			"coord": _vector_to_data(coord),
			"source": layer.get_cell_source_id(coord),
			"atlas": _vector_to_data(atlas),
			"alternative": layer.get_cell_alternative_tile(coord)
		})
	return cells

func _restore_tile_layer(layer: TileMapLayer, cell_data: Variant) -> void:
	layer.clear()
	if not (cell_data is Array):
		return
	for cell in cell_data:
		if cell is Dictionary:
			layer.set_cell(
				Vector2i(_data_to_vector(cell.get("coord", []))),
				int(cell.get("source", -1)),
				Vector2i(_data_to_vector(cell.get("atlas", []))),
				int(cell.get("alternative", 0))
			)

func _restore_trees(tree_data: Variant) -> void:
	if not (tree_data is Dictionary):
		return
	for path in tree_data:
		var tree := get_node_or_null(NodePath(path))
		if tree != null and tree.get_script() != null and tree.get_script().resource_path == "res://scripts/tree.gd":
			tree.health = int(tree_data[path])

func _restore_npcs(npc_data: Variant) -> void:
	if not (npc_data is Dictionary):
		return
	for path in npc_data:
		var npc := get_node_or_null(NodePath(path))
		var state: Variant = npc_data[path]
		if npc != null and state is Dictionary:
			npc.global_position = _data_to_vector(state.get("position", []))
			npc.last_direction = _data_to_vector(state.get("last_direction", [0, 1]))
			npc.behavior_state = str(state.get("behavior_state", npc.behavior_state))

func _restore_plants(plants_data: Variant) -> void:
	for plant in get_tree().get_nodes_in_group("Plants"):
		plant.free()
	used_cells.clear()
	if not (plants_data is Array):
		return
	for plant_data in plants_data:
		if not (plant_data is Dictionary):
			continue
		var seed := int(plant_data.get("seed", -1))
		if not Data.PLANT_DATA.has(seed):
			continue
		var plant_res := PlantResource.new()
		plant_res.setup(seed as Enum.Seed)
		plant_res.age = float(plant_data.get("age", 0.0))
		plant_res.death_count = int(plant_data.get("death_count", 0))
		var plant = plant_scene.instantiate()
		var coord := Vector2i(_data_to_vector(plant_data.get("coord", [])))
		plant.setup(coord, $Objects, plant_res, plant_death)
		plant.sprite_2d.frame = clampi(int(plant_res.age), 0, plant_res.h_frames)
		used_cells.append(coord)

func _restore_dropped_items(items_data: Variant) -> void:
	for item in get_tree().get_nodes_in_group("DroppedItems"):
		item.free()
	if not (items_data is Array):
		return
	var drop_parent: Node = get_node_or_null("Objects/trees")
	if drop_parent == null:
		drop_parent = environment if environment != null else $Objects
	for item_data in items_data:
		if not (item_data is Dictionary) or str(item_data.get("item_name", "")) != "wood":
			continue
		var item = log_scene.instantiate()
		drop_parent.add_child(item)
		item.global_position = _data_to_vector(item_data.get("position", []))

func _seed_for_plant(plant_res: PlantResource) -> int:
	for seed in Data.PLANT_DATA:
		if Data.PLANT_DATA[seed].get("name", "") == plant_res.name:
			return int(seed)
	return -1

func _vector_to_data(value: Vector2) -> Array:
	return [value.x, value.y]

func _data_to_vector(data: Variant) -> Vector2:
	if data is Array and data.size() >= 2:
		return Vector2(float(data[0]), float(data[1]))
	return Vector2.ZERO


func generate_world() -> void:
	world_seed = randi()
	noise.seed = world_seed
	sand_tiles_arr.clear()
	grass_tiles_arr.clear()
	water.clear()
	ground_1.clear()
	ground_2.clear()
	var terrain_noise: Dictionary = {}
	var sand_candidates: Array[Vector2i] = []
	var grass_candidates: Array[Vector2i] = []
	for x in range(-width/2, width/2):
		for y in range(-height/2, height/2):
			var noise_val: float = noise.get_noise_2d(x,y)
			var cell := Vector2i(x, y)
			terrain_noise[cell] = noise_val
			# placing ground
			if noise_val >= 0.0:
				if noise_val > 0.15:
					grass_candidates.append(cell)
				else:
					sand_candidates.append(cell)
				
			water.set_cell(cell, source_id, water_atlas)
		# Let the loading scene animate while the large TileMap is being built.
		if x % 8 == 0:
			await get_tree().process_frame

	# Keep sand connected to the edge as beaches. Any sand component fully
	# enclosed by grass is an inland depression, so leave it as water instead.
	var edge_sand: Dictionary = {}
	var pending: Array[Vector2i] = []
	for cell in sand_candidates:
		if cell.x == -width / 2 or cell.x == width / 2 - 1 or cell.y == -height / 2 or cell.y == height / 2 - 1:
			edge_sand[cell] = true
			pending.append(cell)
	var flood_steps := 0
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + offset
			if terrain_noise.has(neighbor) and terrain_noise[neighbor] <= 0.2 and not edge_sand.has(neighbor):
				edge_sand[neighbor] = true
				pending.append(neighbor)
		flood_steps += 1
		if flood_steps % 4096 == 0:
			await get_tree().process_frame
	for cell in sand_candidates:
		if edge_sand.has(cell):
			sand_tiles_arr.append(cell)
		else:
			water.set_cell(cell, source_id, water_atlas)

	grass_tiles_arr = grass_candidates
	ground_1.set_cells_terrain_connect(sand_tiles_arr, 0, terrain_sand_int, false)
	ground_2.set_cells_terrain_connect(grass_tiles_arr, 0, terrain_grass_int)
	await get_tree().process_frame
	await _generate_forests(grass_tiles_arr)

func _generate_forests(grass_cells_arr: Array[Vector2i]) -> void:
	if environment == null or tree_noise == null:
		return
	environment.clear()

	var grass_set: Dictionary = {}
	for cell in grass_cells_arr:
		grass_set[cell] = true

	# Keep safe clear areas around player, shop, and NPCs
	var protected_positions: Array[Vector2] = []
	if player != null:
		protected_positions.append(player.position)
	for npc in get_tree().get_nodes_in_group("NPC"):
		protected_positions.append(npc.position)
	var shop: Node2D = get_node_or_null("Objects/shop")
	if shop != null:
		protected_positions.append(shop.position)

	if protected_positions.is_empty():
		protected_positions = [
			Vector2(-14, 47),   # Player
			Vector2(85, 140),   # Shop
			Vector2(38, 47),    # John
			Vector2(100, 120),  # Kaia
			Vector2(-160, 20),  # Mira
			Vector2(-120, 110)  # Orin
		]

	var occupied_cells: Dictionary = {}
	var block_size: int = maxi(1, forest_block_size)
	var threshold: float = forest_noise_threshold

	for bx: int in range(-width / 2, width / 2, block_size):
		for by: int in range(-height / 2, height / 2, block_size):
			var center_x: int = bx + block_size / 2
			var center_y: int = by + block_size / 2
			var t_noise_val: float = tree_noise.get_noise_2d(float(center_x), float(center_y))

			var is_forest: bool = t_noise_val >= threshold
			if not is_forest:
				# Plains: rare solitary tree (e.g. 0.4% chance)
				var h_plains: int = int(((bx * 73856093) ^ (by * 19349663) ^ 10007) & 0x7FFFFFFF)
				if float(h_plains % 10000) / 10000.0 > solitary_tree_chance:
					continue

			# Keep forests lush without creating thousands of scene-tile instances.
			var density: float = 0.25
			if is_forest:
				density = remap(clampf(t_noise_val, threshold, 0.55), threshold, 0.55, 0.20, 0.55)

			var h: int = int(((bx * 73856093) ^ (by * 19349663) ^ 8461) & 0x7FFFFFFF)
			if float(h % 1000) / 1000.0 > density:
				continue

			# Jitter position within block
			var ox: int = int((h >> 4) % block_size)
			var oy: int = int((h >> 12) % block_size)
			var cell := Vector2i(bx + ox, by + oy)

			# A tree sprite extends beyond its cell, so require a small grass-only
			# clearing around it. This keeps trees away from water and shore edges.
			if not _has_grass_clearing(cell, grass_set):
				continue

			# Entity clearance check
			var world_pos := Vector2(cell.x * 16 + 8, cell.y * 16 + 8)
			var too_close_to_entity := false
			for prot_pos in protected_positions:
				if world_pos.distance_to(prot_pos) < 55.0:
					too_close_to_entity = true
					break
			if too_close_to_entity:
				continue

			# Spacing check to prevent overlapping collisions/sprites
			var too_close_to_tree := false
			for dx in range(-min_tree_distance + 1, min_tree_distance):
				for dy in range(-min_tree_distance + 1, min_tree_distance):
					if occupied_cells.has(cell + Vector2i(dx, dy)):
						too_close_to_tree = true
						break
				if too_close_to_tree:
					break
			if too_close_to_tree:
				continue

			# Place tree scene tile in environment layer (scene tile 2 in collection source 2)
			if occupied_cells.size() >= max_tree_count:
				continue
			environment.set_cell(cell, tree_source_id, Vector2i(0, 0), 2)
			occupied_cells[cell] = true
		if bx % (block_size * 8) == 0:
			await get_tree().process_frame

func _has_grass_clearing(cell: Vector2i, grass_set: Dictionary) -> bool:
	for x in range(-1, 2):
		for y in range(-1, 2):
			var neighbor := cell + Vector2i(x, y)
			if not grass_set.has(neighbor) or not _is_grass_tile(neighbor):
				return false
	return true

func _has_grass_tile_clearing(cell: Vector2i) -> bool:
	for x in range(-1, 2):
		for y in range(-1, 2):
			if not _is_grass_tile(cell + Vector2i(x, y)):
				return false
	return true

func _is_grass_tile(cell: Vector2i) -> bool:
	return ground_2.get_cell_source_id(cell) != -1

func _remove_water_trees() -> void:
	for cell in environment.get_used_cells():
		if environment.get_cell_source_id(cell) == tree_source_id and not _has_grass_tile_clearing(cell):
			environment.erase_cell(cell)

func _limit_tree_count() -> void:
	var kept := 0
	for cell in environment.get_used_cells():
		if environment.get_cell_source_id(cell) != tree_source_id:
			continue
		if kept >= max_tree_count:
			environment.erase_cell(cell)
		else:
			kept += 1
