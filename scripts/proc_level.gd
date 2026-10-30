extends Node2D

signal world_boot_completed

const GRASS_THRESHOLD := 0.15
const DAYLIGHT_UPDATE_INTERVAL := 0.1

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

@export_group("Skeletons")
@export var skeleton_scene: PackedScene
@export var max_skeletons: int = 3
@export var skeleton_spawn_interval: float = 12.0
@export var skeleton_spawn_min_distance: float = 170.0
@export var skeleton_spawn_max_distance: float = 300.0

@export_group("Player")
@export var player_max_health: int = 10
@export var player_hit_immunity: float = 0.7

var noise: Noise
var tree_noise: Noise
var world_seed: int = 0
var width: int = 256
var height: int = 256

@onready var water: TileMapLayer = $Layers/water
@onready var ground_1: TileMapLayer = $Layers/ground_1
@onready var ground_2: TileMapLayer = $Layers/ground_2
@onready var environment: TileMapLayer = $Objects/environment if has_node("Objects/environment") else $Layers/environment
@onready var cliff: TileMapLayer = $Layers/cliff

var source_id = 0
var tree_source_id = 2
var water_atlas = Vector2(4,1) #4,1 for normal tile

var sand_tiles_arr = []
var terrain_sand_int = 4

var grass_tiles_arr = []
var terrain_grass_int = 0
var _restored_world_data := false
var world_boot_complete := false
var _daylight_update_elapsed := 0.0
var player_health: int = 10
var spawn_position := Vector2.INF
var default_inventory: Dictionary = {}
var health_bar_back: ColorRect
var health_bar_fill: ColorRect
var contrast_layer: CanvasLayer
var _skeleton_spawn_elapsed := 0.0
var _skeleton_scene_searched := false
var _damage_immune_until := 0.0
@onready var healthbar: TextureProgressBar = $Overlay/CanvasLayer/healthbar


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
	add_to_group("Level")
	add_to_group("SettingsListeners")
	if player != null and not player.is_in_group("Player"):
		player.add_to_group("Player")
	default_inventory = PlayerInventory.get_save_data()
	player_health = player_max_health
	#_setup_health_bar()
	_setup_contrast_layer()
	on_settings_changed()
	# Generation intentionally yields so the loading animation stays responsive.
	# Do not expose the partially populated TileMaps during those yield points.
	_set_world_visible(false)
	# A save contains the generated tile layers, so restoring it must happen
	# instead of generating a fresh map first.  Passing this scene explicitly is
	# important while the loading screen is still the SceneTree's current scene.
	var should_load: bool = SaveGame.has_save() and not SaveGame.new_world_requested
	if should_load:
		SaveGame.load_game(self)
		# Saves created before procedural layers were persisted cannot be restored
		# exactly. Generate once to migrate them, then rewrite the save after this
		# scene becomes the current scene.
		if not _restored_world_data:
			await generate_world()
			call_deferred("_save_migrated_world")
	else:
		SaveGame.new_world_requested = false
		await _begin_new_world()
		call_deferred("_save_migrated_world")
	_set_world_visible(true)
	_play_startup_transition()
	world_boot_complete = true
	world_boot_completed.emit()

func _set_world_visible(show_world: bool) -> void:
	$Layers.visible = show_world
	$Objects.visible = show_world

func _save_migrated_world() -> void:
	if SaveGame.current_slot > 0:
		SaveGame.save_game(self)

func _play_startup_transition() -> void:
	if day_transition_layer_material == null:
		return
	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 1.0)
	var transition := create_tween()
	transition.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, _transition_time(1.0))
	transition.tween_callback(_finish_day_transition)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("day_change") and world_boot_complete:
		day_restart()

func _on_player_tool_use(tool: Enum.Tool, pos: Vector2, dir) -> void:
	_apply_tool_use(tool, pos, dir, player.current_seed, true)

func npc_tool_use(tool: Enum.Tool, pos: Vector2, dir: bool, seed: Enum.Seed) -> void:
	_apply_tool_use(tool, pos, dir, seed, false)

func _apply_tool_use(tool: Enum.Tool, pos: Vector2, dir: bool, seed: Enum.Seed, show_plant_info: bool) -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
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
				else:
					dark_dirt_layer.set_cell(dark_coord + tile_adjuster, 0, Vector2i(12, 7), 0)
				if connected_cells.size() > 1:
					dark_dirt_layer.set_cells_terrain_connect(connected_cells, 0, 3)
		Enum.Tool.FISH:
			if has_soil:
				print('fishing')
		Enum.Tool.SEED:
			if has_soil and grid_coord not in used_cells:
				var cell = light_dirt_layer.get_cell_tile_data(grid_coord)
				if cell and cell.get_custom_data('seedable'):
					var plant_res = PlantResource.new()
					plant_res.setup(seed)
					var plant = plant_scene.instantiate()
					plant.setup(grid_coord + tile_adjuster, $Objects, plant_res, plant_death)
					used_cells.append(grid_coord)

					if show_plant_info:
						var plant_info = plant_info_scene.instantiate()
						plant_info_container.add(plant_info)
						plant_info.setup(plant_res)

		Enum.Tool.AXE, Enum.Tool.SWORD:
			for object in get_tree().get_nodes_in_group('Objects'):
				if object.has_method("hit") and object.global_position.distance_to(pos) < 24:
					object.hit(tool)
func _process(delta: float) -> void:
	# The procedural level scene may not have a day-color gradient assigned yet.
	# Skip the visual update until it does instead of calling sample() on null.
	if daytime_color == null or day_timer == null or day_time_color == null:
		return
	_daylight_update_elapsed += delta
	if _daylight_update_elapsed < DAYLIGHT_UPDATE_INTERVAL:
		return
	_daylight_update_elapsed = 0.0
	var daytime_point = 1 - (day_timer.time_left / day_timer.wait_time)
	var color = daytime_color.sample(daytime_point)
	day_time_color.color = color

func day_restart() -> void:
	if day_transition_tween and day_transition_tween.is_running():
		return
	if day_transition_layer_material == null:
		push_error("DayTransitionLayer does not have a ShaderMaterial.")
		return

	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 0.0)
	day_transition_tween = create_tween()
	day_transition_tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 1.0, _transition_time(1.0))
	day_transition_tween.tween_interval(_transition_time(0.5))
	day_transition_tween.tween_callback(level_reset)
	day_transition_tween.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, _transition_time(1.0))
	day_transition_tween.tween_callback(_finish_day_transition)

func _finish_day_transition() -> void:
	day_transition_layer.visible = false

func level_reset():
	for plant in get_tree().get_nodes_in_group('Plants'):
		plant.grow(plant.coord in dark_dirt_layer.get_used_cells())
	dark_dirt_layer.clear()
	plant_info_container.update_all()
	WorldTime.day_count += 1
	WorldTime.set_time(WorldTime.start_minutes)
	_clear_skeletons()
	var died := player_health <= 0
	player_health = player_max_health
	if died and spawn_position.is_finite():
		player.global_position = spawn_position
	_update_health_bar()
	day_timer.start()

func plant_death(coord: Vector2i):
	used_cells.erase(coord)

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
		"world_seed": world_seed,
		"spawn_position": _vector_to_data(spawn_position) if spawn_position.is_finite() else [],
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
			"current_style": int(player.current_style),
			"health": player_health
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
	world_seed = int(save_data.get("world_seed", 0))

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
		player_health = clampi(int(player_data.get("health", player_max_health)), 1, player_max_health)
		_update_health_bar()

	var spawn_data: Variant = save_data.get("spawn_position", [])
	if spawn_data is Array and spawn_data.size() >= 2:
		spawn_position = _data_to_vector(spawn_data)

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


func _randomize_world_seed() -> void:
	world_seed = randi()
	noise.seed = world_seed
	tree_noise.seed = world_seed + 1

func generate_world() -> void:
	_randomize_world_seed()
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
			var noise_val: float = noise.get_noise_2d(x, y)
			var cell := Vector2i(x, y)
			terrain_noise[cell] = noise_val
			# placing ground
			if noise_val >= 0.0:
				if noise_val > GRASS_THRESHOLD:
					grass_candidates.append(cell)
				else:
					sand_candidates.append(cell)

			water.set_cell(cell, source_id, water_atlas)
		# Let the loading scene animate while the large TileMap is being built.
		if x % 8 == 0:
			await get_tree().process_frame

	# Keep sand connected to the edge as beaches. Any sand component fully
	# enclosed by grass is an inland depression, so leave it as water instead.
	var min_x := -width / 2
	var max_x := width / 2 - 1
	var min_y := -height / 2
	var max_y := height / 2 - 1
	var open_cells: Dictionary = {}
	var pending: Array[Vector2i] = []

	var edge_cells: Array[Vector2i] = []
	for x in range(min_x, max_x + 1):
		edge_cells.append(Vector2i(x, min_y))
		edge_cells.append(Vector2i(x, max_y))
	for y in range(min_y, max_y + 1):
		edge_cells.append(Vector2i(min_x, y))
		edge_cells.append(Vector2i(max_x, y))
	for cell in edge_cells:
		if terrain_noise[cell] <= GRASS_THRESHOLD and not open_cells.has(cell):
			open_cells[cell] = true
			pending.append(cell)

	var flood_steps := 0
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + offset
			if not open_cells.has(neighbor) and terrain_noise.has(neighbor) \
					and terrain_noise[neighbor] <= GRASS_THRESHOLD:
				open_cells[neighbor] = true
				pending.append(neighbor)
		flood_steps += 1
		if flood_steps % 4096 == 0:
			await get_tree().process_frame

	for cell in sand_candidates:
		if open_cells.has(cell):
			sand_tiles_arr.append(cell)

	grass_tiles_arr = grass_candidates
	ground_1.set_cells_terrain_connect(sand_tiles_arr, 0, terrain_sand_int, false)
	ground_2.set_cells_terrain_connect(grass_tiles_arr, 0, terrain_grass_int)
	await get_tree().process_frame
	_place_entities_on_grass()
	await _generate_forests(grass_tiles_arr)

func _place_entities_on_grass() -> void:
	var grass_set: Dictionary = {}
	for cell in grass_tiles_arr:
		grass_set[cell] = true
	if grass_set.is_empty():
		return

	var entities: Array[Node2D] = []
	if player != null:
		entities.append(player)
	for npc in get_tree().get_nodes_in_group("NPC"):
		entities.append(npc)
	var shop: Node2D = get_node_or_null("Objects/shop")
	if shop != null:
		entities.append(shop)
	if entities.is_empty():
		return

	var origin: Vector2 = entities[0].global_position
	var offsets: Array[Vector2] = []
	for entity in entities:
		offsets.append(entity.global_position - origin)

	var anchor: Vector2i = _find_spawn_cell(grass_set)
	var anchor_pos: Vector2 = ground_2.to_global(ground_2.map_to_local(anchor))
	var taken: Dictionary = {}
	for i in entities.size():
		var wanted: Vector2i = ground_2.local_to_map(ground_2.to_local(anchor_pos + offsets[i]))
		var cell: Vector2i = _nearest_free_grass_cell(wanted, grass_set, taken)
		taken[cell] = true
		entities[i].global_position = ground_2.to_global(ground_2.map_to_local(cell))
	if player != null:
		spawn_position = player.global_position

func _find_spawn_cell(grass_set: Dictionary) -> Vector2i:
	var cells: Array = grass_set.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.length_squared() < b.length_squared())
	for radius in [8, 4, 1]:
		for cell in cells:
			var open := true
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					if not grass_set.has(cell + Vector2i(x, y)):
						open = false
						break
				if not open:
					break
			if open:
				return cell
	return cells[0]

func _nearest_free_grass_cell(wanted: Vector2i, grass_set: Dictionary, taken: Dictionary) -> Vector2i:
	for r in range(0, 24):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := wanted + Vector2i(dx, dy)
				if grass_set.has(cell) and not taken.has(cell) and _has_grass_clearing(cell, grass_set):
					return cell
	return wanted

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

	var block_size: int = maxi(1, forest_block_size)
	var threshold: float = forest_noise_threshold

	var candidates: Array = []
	for bx: int in range(-width / 2, width / 2, block_size):
		for by: int in range(-height / 2, height / 2, block_size):
			var center_x: int = bx + block_size / 2
			var center_y: int = by + block_size / 2
			var t_noise_val: float = tree_noise.get_noise_2d(float(center_x), float(center_y))

			var is_forest: bool = t_noise_val >= threshold
			if not is_forest:
				# Plains: rare solitary tree (e.g. 0.4% chance)
				var h_plains: int = int(((bx * 73856093) ^ (by * 19349663) ^ 10007 ^ (world_seed * 83492791)) & 0x7FFFFFFF)
				if float(h_plains % 10000) / 10000.0 > solitary_tree_chance:
					continue

			# Keep forests lush without creating thousands of scene-tile instances.
			var density: float = 0.25
			if is_forest:
				density = remap(clampf(t_noise_val, threshold, 0.55), threshold, 0.55, 0.20, 0.55)

			var h: int = int(((bx * 73856093) ^ (by * 19349663) ^ 8461 ^ (world_seed * 83492791)) & 0x7FFFFFFF)
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
			var world_pos: Vector2 = environment.map_to_local(cell)
			var blocked := false
			for prot_pos in protected_positions:
				if world_pos.distance_to(prot_pos) < 55.0:
					blocked = true
					break
			if blocked:
				continue

			candidates.append([(h >> 20) ^ (h & 0xFFFF), cell])
		if bx % (block_size * 8) == 0:
			await get_tree().process_frame

	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var occupied_cells: Dictionary = {}
	for entry in candidates:
		if occupied_cells.size() >= max_tree_count:
			break
		var cell: Vector2i = entry[1]
		# Spacing check to prevent overlapping collisions/sprites
		var too_close := false
		for dx in range(-min_tree_distance + 1, min_tree_distance):
			for dy in range(-min_tree_distance + 1, min_tree_distance):
				if occupied_cells.has(cell + Vector2i(dx, dy)):
					too_close = true
					break
			if too_close:
				break
		if too_close:
			continue
		# Place tree scene tile in environment layer (scene tile 2 in collection source 2)
		environment.set_cell(cell, tree_source_id, Vector2i(0, 0), 2)
		occupied_cells[cell] = true

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


func _physics_process(delta: float) -> void:
	if not world_boot_complete:
		return
	_skeleton_spawn_elapsed += delta
	if _skeleton_spawn_elapsed < skeleton_spawn_interval:
		return
	_skeleton_spawn_elapsed = 0.0
	_try_spawn_skeleton()

func _try_spawn_skeleton() -> void:
	if player == null:
		return
	if get_tree().get_nodes_in_group("Skeletons").size() >= max_skeletons:
		return
	var scene := _get_skeleton_scene()
	if scene == null:
		return
	for attempt in 16:
		var spawn_pos: Vector2 = player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(skeleton_spawn_min_distance, skeleton_spawn_max_distance)
		var cell: Vector2i = ground_2.local_to_map(ground_2.to_local(spawn_pos))
		if not _has_land_clearing(cell) or environment.get_cell_source_id(cell) != -1:
			continue
		var skeleton: Node2D = scene.instantiate()
		$Objects.add_child(skeleton)
		skeleton.global_position = ground_2.to_global(ground_2.map_to_local(cell))
		return

func _get_skeleton_scene() -> PackedScene:
	if skeleton_scene != null:
		return skeleton_scene
	if _skeleton_scene_searched:
		return null
	_skeleton_scene_searched = true
	var path := _find_scene_file("res://")
	if path == "":
		push_warning("No skeleton scene found. Assign skeleton_scene on the level node.")
		return null
	skeleton_scene = load(path) as PackedScene
	return skeleton_scene

func _find_scene_file(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for file in dir.get_files():
		var clean := file.trim_suffix(".remap")
		if clean.to_lower().begins_with("skeleton") and clean.ends_with(".tscn"):
			return dir_path.path_join(clean)
	for sub_dir in dir.get_directories():
		if sub_dir == "addons" or sub_dir.begins_with("."):
			continue
		var found := _find_scene_file(dir_path.path_join(sub_dir))
		if found != "":
			return found
	return ""

func _is_land_tile(cell: Vector2i) -> bool:
	return ground_2.get_cell_source_id(cell) != -1 or ground_1.get_cell_source_id(cell) != -1

func is_land_position(world_position: Vector2) -> bool:
	var cell := ground_1.local_to_map(ground_1.to_local(world_position))
	return _is_land_tile(cell)

func _has_land_clearing(cell: Vector2i) -> bool:
	for x in range(-1, 2):
		for y in range(-1, 2):
			if not _is_land_tile(cell + Vector2i(x, y)):
				return false
	return true

func damage_player(amount: int, _from_position: Vector2 = Vector2.ZERO) -> void:
	if not world_boot_complete or player_health <= 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _damage_immune_until:
		return
	_damage_immune_until = now + player_hit_immunity
	player_health = maxi(0, player_health - amount)
	_update_health_bar()
	#player.modulate = Color(1.0, 0.35, 0.35)
	#create_tween().tween_property(player, "modulate", Color.WHITE, 0.25)
	player.get_node("Animation/AnimationPlayer").play('hurt_left')
	
	_shake_camera(2.5)
	if player_health <= 0:
		_on_player_died()

func _shake_camera(strength: float) -> void:
	var shake_enabled: bool = GameSettings.get_value("video", "screen_shake")
	var reduced_motion: bool = GameSettings.get_value("accessibility", "reduced_motion")
	if not shake_enabled or reduced_motion:
		return
	var camera: Camera2D = null
	for child in player.get_children():
		if child is Camera2D:
			camera = child
			break
	if camera == null:
		return
	var tween := create_tween()
	for i in 5:
		tween.tween_property(camera, "offset", Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.04)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.04)

func _on_player_died() -> void:
	_clear_skeletons()
	day_restart()

func _clear_skeletons() -> void:
	for skeleton in get_tree().get_nodes_in_group("Skeletons"):
		skeleton.queue_free()


func _update_health_bar() -> void:
	# Calculate the health percentage (0 to 100) dynamically
	var health_pct : float = (float(player_health) / float(maxi(player_max_health, 1))) * 100.0
	healthbar.value = health_pct

func _setup_contrast_layer() -> void:
	contrast_layer = CanvasLayer.new()
	contrast_layer.layer = 100
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen_texture : hint_screen_texture, filter_nearest;\nuniform float contrast = 1.4;\nvoid fragment() {\n\tvec3 color = texture(screen_texture, SCREEN_UV).rgb;\n\tcolor = (color - 0.5) * contrast + 0.5;\n\tCOLOR = vec4(clamp(color, 0.0, 1.0), 1.0);\n}\n"
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	rect.material = shader_material
	contrast_layer.add_child(rect)
	contrast_layer.visible = false
	add_child(contrast_layer)

func on_settings_changed() -> void:
	if contrast_layer != null:
		contrast_layer.visible = GameSettings.get_value("accessibility", "high_contrast")

func _transition_time(seconds: float) -> float:
	if GameSettings.get_value("accessibility", "reduced_motion"):
		return seconds * 0.3
	return seconds

func _begin_new_world() -> void:
	SaveGame.current_slot = 0
	_clear_world_entities()
	PlayerInventory.load_save_data(default_inventory.duplicate(true))
	WorldTime.day_count = 1
	WorldTime.set_time(WorldTime.start_minutes)
	player_health = player_max_health
	_update_health_bar()
	await generate_world()
	day_timer.start()

func _clear_world_entities() -> void:
	for plant in get_tree().get_nodes_in_group("Plants"):
		plant.free()
	for item in get_tree().get_nodes_in_group("DroppedItems"):
		item.free()
	_clear_skeletons()
	used_cells.clear()
	$Layers/LightDirtLayer.clear()
	$Layers/DarkDirtLayer.clear()

func _cover_screen() -> void:
	if day_transition_layer_material == null:
		return
	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 1.0)

func _load_or_create_world() -> void:
	_cover_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	_set_world_visible(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_clear_world_entities()
	_restored_world_data = false
	if SaveGame.has_save():
		SaveGame.load_game(self)
		if not _restored_world_data:
			await generate_world()
	else:
		await _begin_new_world()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	_set_world_visible(true)
	_play_startup_transition()
	world_boot_complete = true

func load_world(slot: int) -> void:
	if not world_boot_complete or not SaveGame.has_save(slot):
		return
	world_boot_complete = false
	SaveGame.current_slot = slot
	await _load_or_create_world()

func start_new_world() -> void:
	if not world_boot_complete:
		return
	world_boot_complete = false
	SaveGame.current_slot = 0
	await _load_or_create_world()
