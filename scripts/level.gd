extends Node2D


var plant_scene = preload("res://scenes/objects/plant.tscn")
var log_scene = preload("res://scenes/objects/log.tscn")
var sprinkler_scene = preload("res://scenes/objects/sprinkler.tscn")
var plant_info_scene = preload("res://scenes/UI/panel_container.tscn")
var used_cells: Array[Vector2i]
@onready var player: CharacterBody2D = $Objects/Player
@onready var npc_spawner: Node = $NPCSpawner
@export var daytime_color: Gradient
@onready var day_timer: Timer = $Timers/DayTimer
@onready var day_time_color: CanvasModulate = $Overlay/DayTimeColor
@onready var day_transition_layer: ColorRect = $Overlay/CanvasLayer/DayTransitionLayer
@onready var day_transition_layer_material: ShaderMaterial = day_transition_layer.material as ShaderMaterial
@onready var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
@onready var plant_info_container: Control = $Overlay/CanvasLayer/plant_info_container

var day_transition_tween: Tween

func _ready() -> void:
	# Restore before the loading scene hands visibility to the level. All scene
	# children have entered the tree by the time the parent is ready.
	SaveGame.load_game()
	_play_startup_transition()
	
	# Spawn NPCs after a brief delay to ensure level is ready
	call_deferred("_spawn_npcs")

func _spawn_npcs() -> void:
	if npc_spawner and npc_spawner.has_method("spawn_all_npcs"):
		npc_spawner.spawn_all_npcs()

func _play_startup_transition() -> void:
	if day_transition_layer_material == null:
		return
	day_transition_layer.visible = true
	day_transition_layer_material.set_shader_parameter("progress", 1.0)
	var transition := create_tween()
	transition.tween_property(day_transition_layer_material, "shader_parameter/progress", 0.0, 1.0)
	transition.tween_callback(_finish_day_transition)

func _on_npc_spawned(npc: Node) -> void:
	print("[Level] NPC spawned: ", npc.npc_name if npc.has_method("npc_name") else npc.name)

func _on_all_npcs_spawned() -> void:
	print("[Level] All NPCs spawned and initialized")
	# NPCs are now ready for social group resolution

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
			for target_cell in _area_offsets(grid_coord, FarmState.get_tool_area_radius(Enum.Tool.HOE)):
				_till_cell(target_cell, light_dirt_layer)
		Enum.Tool.WATER:
			for target_cell in _area_offsets(grid_coord, FarmState.get_tool_area_radius(Enum.Tool.WATER)):
				_water_cell_at(target_cell, light_dirt_layer, dark_dirt_layer)
		Enum.Tool.HAMMER:
			_place_sprinkler(grid_coord)
		Enum.Tool.FISH:
			if has_soil:
				print('fishing')
		Enum.Tool.SEED:
			if has_soil and grid_coord not in used_cells:
				var cell = $Layers/LightDirtLayer.get_cell_tile_data(grid_coord)
				if cell and cell.get_custom_data('seedable'):
					if not Data.seed_in_season(seed, WorldTime.current_season):
						if show_plant_info:
							FarmHud.notice("%s cannot grow in %s." % [str(Data.PLANT_DATA[seed]['name']), WorldTime.get_season_name()], Color(1.0, 0.55, 0.45))
						return
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
			var hit_count := FarmState.get_axe_hits() if tool == Enum.Tool.AXE else 1
			for object in get_tree().get_nodes_in_group('Objects'):
				if object.position.distance_to(pos) < 20:
					for _hit in range(hit_count):
						object.hit(tool)

func _area_offsets(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	radius = maxi(0, radius)
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			cells.append(center + Vector2i(x, y))
	return cells

func _till_cell(grid_coord: Vector2i, light_dirt_layer: TileMapLayer) -> void:
	var cell = $Layers/GrassLayer.get_cell_tile_data(grid_coord)
	if not (cell and cell.get_custom_data('farmable')):
		return
	if light_dirt_layer.get_cell_source_id(grid_coord) != -1:
		return
	var connected_cells: Array[Vector2i] = [grid_coord]
	for y in range(-1, 2):
		for x in range(-1, 2):
			if x == 0 and y == 0:
				continue
			var neighbor := grid_coord + Vector2i(x, y)
			if light_dirt_layer.get_cell_source_id(neighbor) != -1:
				connected_cells.append(neighbor)

	# An isolated cell must start as a complete dirt tile. Once it has a dirt
	# neighbor, terrain-connect can safely create the borders.
	light_dirt_layer.set_cell(grid_coord, 0, Vector2i(6, 35), 0)
	if connected_cells.size() > 1:
		light_dirt_layer.set_cells_terrain_connect(connected_cells, 0, 1)

func _water_cell_at(light_cell: Vector2i, light_dirt_layer: TileMapLayer, dark_layer: TileMapLayer) -> void:
	if light_dirt_layer.get_cell_source_id(light_cell) == -1:
		return
	var world_pos := light_dirt_layer.to_global(light_dirt_layer.map_to_local(light_cell))
	var dark_coord: Vector2i = dark_layer.local_to_map(dark_layer.to_local(world_pos))
	if dark_layer.get_cell_source_id(dark_coord) != -1:
		return
	var connected_cells: Array[Vector2i] = [dark_coord]
	for y in range(-1, 2):
		for x in range(-1, 2):
			if x == 0 and y == 0:
				continue
			var neighbor := dark_coord + Vector2i(x, y)
			if dark_layer.get_cell_source_id(neighbor) != -1:
				connected_cells.append(neighbor)

	# Terrain-connect cannot create an isolated terrain reliably.
	# Place the complete dark-dirt tile first, then connect neighbors.
	dark_layer.set_cell(dark_coord, 0, Vector2i(12, 7), 0)
	if connected_cells.size() > 1:
		dark_layer.set_cells_terrain_connect(connected_cells, 0, 3)

func _place_sprinkler(grid_coord: Vector2i) -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
	if light_dirt_layer.get_cell_source_id(grid_coord) == -1:
		FarmHud.notice("Sprinklers must be placed on tilled soil.", Color(1.0, 0.55, 0.45))
		return
	if grid_coord in used_cells:
		FarmHud.notice("There is already a crop in that soil.", Color(1.0, 0.55, 0.45))
		return
	for machine in get_tree().get_nodes_in_group("FarmMachines"):
		if machine.coord == grid_coord:
			FarmHud.notice("A sprinkler is already there.", Color(1.0, 0.55, 0.45))
			return

	var machine_data: Dictionary = Data.MACHINE_DATA.get(Enum.Machine.SPRINKLER, {})
	var cost := int(machine_data.get("cost_money", 0))
	if not PlayerInventory.spend_money(cost):
		FarmHud.notice("Need %d TC to place a sprinkler." % cost, Color(1.0, 0.55, 0.45))
		return
	var machine = sprinkler_scene.instantiate()
	machine.setup(grid_coord, $Objects, int(machine_data.get("radius", 2)))
	_align_plant_to_grid(machine)
	FarmHud.notice("Sprinkler placed. It waters every morning.", Color(0.65, 1.0, 0.65))

## Repaints the soil around each sprinkler so automated watering is visible
## after the morning reset clears the previous day's dark dirt.
func _refresh_sprinkler_water() -> void:
	var light_dirt_layer: TileMapLayer = $Layers/LightDirtLayer
	for machine in get_tree().get_nodes_in_group("FarmMachines"):
		if int(machine.machine_type) != Enum.Machine.SPRINKLER:
			continue
		for target_cell in _area_offsets(machine.coord, int(machine.radius)):
			_water_cell_at(target_cell, light_dirt_layer, dark_dirt_layer)

func _collect_watered_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append_array(dark_dirt_layer.get_used_cells())
	for machine in get_tree().get_nodes_in_group("FarmMachines"):
		if int(machine.machine_type) != Enum.Machine.SPRINKLER:
			continue
		var machine_coord: Vector2i = machine.coord
		cells.append_array(_area_offsets(machine_coord, int(machine.radius)))
	return cells
			
func _process(delta: float) -> void:
		var daytime_point = 1 - (day_timer.time_left / day_timer.wait_time)
		var color = daytime_color.sample(daytime_point)
		day_time_color.color = color
		if Input.is_action_just_pressed("day_change"):
			day_restart()

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
	WorldTime.advance_days(1)
	var watered_cells := _collect_watered_cells()
	for plant in get_tree().get_nodes_in_group('Plants'):
		plant.grow(plant.coord in watered_cells)
	dark_dirt_layer.clear()
	_refresh_sprinkler_water()
	plant_info_container.update_all()
	WorldTime.set_time(WorldTime.start_minutes)
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
		# Use enhanced save data if available
		var npc_data: Dictionary = {
			"position": _vector_to_data(npc.global_position),
			"last_direction": _vector_to_data(npc.last_direction),
			"behavior_state": npc.behavior_state
		}
		
		# Try to get full save data from enhanced NPCs
		if npc.has_method("get_save_data"):
			var enhanced_data: Variant = npc.get_save_data()
			if enhanced_data:
				npc_data = enhanced_data
		
		npcs[str(npc.get_path())] = npc_data

	var plants: Array = []
	for plant in get_tree().get_nodes_in_group("Plants"):
		plants.append({
			"coord": _vector_to_data(plant.coord),
			"seed": _seed_for_plant(plant.res),
			"age": plant.res.age,
			"death_count": plant.res.death_count,
			"quality": int(plant.res.quality),
			"care_days": int(plant.res.care_days),
			"watered_days": int(plant.res.watered_days)
		})

	var machines: Array = []
	for machine in get_tree().get_nodes_in_group("FarmMachines"):
		machines.append({
			"coord": _vector_to_data(Vector2(machine.coord)),
			"type": int(machine.machine_type)
		})

	var dropped_items: Array = []
	for item in get_tree().get_nodes_in_group("DroppedItems"):
		dropped_items.append({
			"item_name": item.item_name,
			"position": _vector_to_data(item.global_position)
		})

	return {
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
		"machines": machines,
		"dropped_items": dropped_items,
		"trees": trees,
		"npcs": npcs
	}

func apply_save_data(save_data: Dictionary) -> void:
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
		WorldTime.set_day_count(int(time_data.get("day_count", 1)))
		WorldTime.set_time(int(time_data.get("minutes", WorldTime.start_minutes)))
		var remaining := float(time_data.get("day_timer_remaining", day_timer.wait_time))
		day_timer.start(clampf(remaining, 0.01, day_timer.wait_time))

	_restore_tile_layer($Layers/LightDirtLayer, save_data.get("light_dirt", []))
	_restore_tile_layer($Layers/DarkDirtLayer, save_data.get("dark_dirt", []))
	_restore_machines(save_data.get("machines", []))
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

func _align_plant_to_grid(node: Node2D) -> void:
	node.global_position -= $Objects.global_position

func _restore_machines(machine_data: Variant) -> void:
	for machine in get_tree().get_nodes_in_group("FarmMachines"):
		machine.free()
	if not (machine_data is Array):
		return
	for entry in machine_data:
		if not (entry is Dictionary):
			continue
		var type := int(entry.get("type", Enum.Machine.SPRINKLER))
		if type != Enum.Machine.SPRINKLER:
			continue
		var coord := Vector2i(_data_to_vector(entry.get("coord", [])))
		var data: Dictionary = Data.MACHINE_DATA.get(type, {})
		var machine = sprinkler_scene.instantiate()
		machine.setup(coord, $Objects, int(data.get("radius", 2)))
		_align_plant_to_grid(machine)

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
	
	# First pass: restore basic state for all NPCs
	for path in npc_data:
		var npc := get_node_or_null(NodePath(path))
		var state: Variant = npc_data[path]
		if npc != null and state is Dictionary:
			npc.global_position = _data_to_vector(state.get("position", []))
			npc.last_direction = _data_to_vector(state.get("last_direction", [0, 1]))
			npc.behavior_state = str(state.get("behavior_state", npc.behavior_state))
	
	# Second pass: restore enhanced data for NPCs that support it
	for path in npc_data:
		var npc := get_node_or_null(NodePath(path))
		var state: Variant = npc_data[path]
		if npc != null and state is Dictionary and npc.has_method("load_save_data"):
			npc.load_save_data(state)
	
	# Third pass: resolve social groups (needs all NPCs loaded)
	var all_npcs := get_tree().get_nodes_in_group("NPC")
	for path in npc_data:
		var npc := get_node_or_null(NodePath(path))
		if npc != null and npc.has_method("resolve_pending_groups"):
			npc.resolve_pending_groups(all_npcs)

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
		plant_res.quality = int(plant_data.get("quality", Enum.Quality.NORMAL))
		plant_res.care_days = int(plant_data.get("care_days", 0))
		plant_res.watered_days = int(plant_data.get("watered_days", 0))
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
	for item_data in items_data:
		if not (item_data is Dictionary) or str(item_data.get("item_name", "")) != "wood":
			continue
		var item = log_scene.instantiate()
		$Objects/trees.add_child(item)
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
