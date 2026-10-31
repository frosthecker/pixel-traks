extends Node2D

signal world_boot_completed
signal health_changed(current: int, maximum: int)

const GRASS_THRESHOLD := 0.15
const MIN_ISLAND_GRASS_CELLS := 40
## NPC placement, measured in tiles. NPCs are spread over the player's island:
## never right on top of the start, never too far to find, and well apart from each other.
const NPC_MIN_SPAWN_DISTANCE_CELLS := 6.0 ## Closest an NPC may be to the player's start
const NPC_MAX_SPAWN_DISTANCE_CELLS := 30.0 ## Farthest an NPC may be from the player's start
const NPC_MIN_SPACING_CELLS := 12.0 ## Minimum distance between two NPCs
const PROFILE_PATH := "user://profile.cfg"
const DAYLIGHT_UPDATE_INTERVAL := 0.1

var plant_scene = preload("res://scenes/objects/plant.tscn")
var log_scene = preload("res://scenes/objects/log.tscn")
var plant_info_scene = preload("res://scenes/UI/panel_container.tscn")
var used_cells: Array[Vector2i]
@onready var player: CharacterBody2D = $Objects/Player
@export var daytime_color: Gradient
@onready var day_timer: Timer = $Timers/DayTimer
@onready var healthbar: TextureProgressBar = get_node_or_null("Overlay/CanvasLayer/healthbar")
@onready var day_time_color: CanvasModulate = $Overlay/DayTimeColor
@onready var day_transition_layer: ColorRect = $Overlay/CanvasLayer/DayTransitionLayer
@onready var day_transition_layer_material: ShaderMaterial = day_transition_layer.material as ShaderMaterial
@onready var dark_dirt_layer: TileMapLayer = $Layers/DarkDirtLayer
@onready var plant_info_container: Control = $Overlay/UserInterface/map/pages/worldmap/WorldSections/pages/plant_info_container
var day_transition_tween: Tween

@export var noise_height_text: NoiseTexture2D
@export var noise_tree_text: NoiseTexture2D

@export_group("Forest Generation")
@export var forest_noise_threshold: float = -0.08 ## Noise threshold above which terrain is considered a forest biome
@export var forest_block_size: int = 4 ## Tile grid block size for placing trees
@export var min_tree_distance: int = 3 ## Minimum tile distance between trees to prevent collision overlap
@export var solitary_tree_chance: float = 0.06 ## Chance of occasional lone trees in open plains
@export_range(100, 2000, 25) var max_tree_count: int = 750 ## Keeps scene-tile physics affordable on low-end devices
var tree_frequency: float = 0.12 ## Backward-compatibility alias for forest_noise_threshold

@export_group("Skeletons")
@export var skeleton_scene: PackedScene
@export var max_skeletons: int = 2
@export var skeleton_spawn_interval: float = 45.0
@export var skeleton_spawn_min_distance: float = 240.0
@export var skeleton_spawn_max_distance: float = 400.0

@export_group("Player")
@export var player_max_health: int = 10
@export var player_hit_immunity: float = 0.7
@export var health_regen_delay: float = 8.0
@export var health_regen_interval: float = 4.0

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
var contrast_layer: CanvasLayer
var _skeleton_spawn_elapsed := 0.0
var _skeleton_scene_searched := false
var _damage_immune_until := 0.0
var _last_damage_time := -1000.0
var _regen_elapsed := 0.0
var _terrain_cache: Dictionary = {}
var _stuck_elapsed := 0.0
## True once John's opening intro has played in THIS world. It is stored inside the
## world's own save data, so it persists with the world and resets for a new one.
var intro_played := false
var _john_intro_default := ""
var _intro_active := false
var _boot_msec := 0
var _delete_dialog: ConfirmationDialog
var _npcs_spread := false ## Saved per world: NPCs have been spread out (older worlds get a one-time spread)


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
	_boot_msec = Time.get_ticks_msec()
	_capture_intro_default()
	_connect_dialogic_signals()
	if player != null and not player.is_in_group("Player"):
		player.add_to_group("Player")
	default_inventory = PlayerInventory.get_save_data()
	player_health = player_max_health
	_setup_contrast_layer()
	on_settings_changed()
	_setup_profile_persistence()
	# Generation intentionally yields so the loading animation stays responsive.
	# Do not expose the partially populated TileMaps during those yield points.
	_set_world_visible(false)
	# A save contains the generated tile layers, so restoring it must happen
	# instead of generating a fresh map first.  Passing this scene explicitly is
	# important while the loading screen is still the SceneTree's current scene.
	var resumed := false
	if not SaveGame.new_world_requested and SaveGame.has_resume():
		resumed = SaveGame.load_resume(self)
	var should_load: bool = SaveGame.has_save() and not SaveGame.new_world_requested and not resumed
	if resumed:
		if not _restored_world_data:
			await generate_world()
	elif should_load:
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
	_apply_intro_state()
	world_boot_complete = true
	_update_health_bar()
	world_boot_completed.emit()

func _capture_intro_default() -> void:
	var john: Node = get_node_or_null("Objects/John")
	if john != null and john.get("intro_timeline") != null:
		_john_intro_default = str(john.get("intro_timeline"))

func _connect_dialogic_signals() -> void:
	var dialogic: Node = get_node_or_null("/root/Dialogic")
	if dialogic == null:
		return
	if dialogic.has_signal("timeline_started") and not dialogic.is_connected("timeline_started", _on_dialogic_started):
		dialogic.connect("timeline_started", _on_dialogic_started)
	if dialogic.has_signal("timeline_ended") and not dialogic.is_connected("timeline_ended", _on_dialogic_ended):
		dialogic.connect("timeline_ended", _on_dialogic_ended)

## John only runs his intro while his `intro_timeline` is set. Kaia, Mira and Orin
## have it empty in the scene, so empty means "no intro". After the intro has been
## played once in a world, blank it; in a fresh world, restore it.
func _apply_intro_state() -> void:
	var john: Node = get_node_or_null("Objects/John")
	if john != null and john.get("intro_timeline") != null:
		john.set("intro_timeline", "" if intro_played else _john_intro_default)

func _current_timeline_path() -> String:
	var dialogic: Node = get_node_or_null("/root/Dialogic")
	if dialogic == null:
		return ""
	var timeline: Variant = dialogic.get("current_timeline")
	if timeline is Resource:
		return String(timeline.resource_path)
	return ""

func _on_dialogic_started() -> void:
	var path := _current_timeline_path()
	var looks_like_intro := path.to_lower().contains("intro") \
			or (_john_intro_default != "" and path == _john_intro_default)
	# Dynamically built timelines have no path: treat one that starts right after
	# boot, before the intro has ever played, as the intro.
	if path == "" and not intro_played and Time.get_ticks_msec() - _boot_msec < 20000:
		looks_like_intro = true
	if not looks_like_intro:
		return
	if intro_played:
		# Safety net: something still tried to start the intro, so end it.
		var dialogic: Node = get_node_or_null("/root/Dialogic")
		if dialogic != null and dialogic.has_method("end_timeline"):
			dialogic.call_deferred("end_timeline")
		return
	_intro_active = true

func _on_dialogic_ended() -> void:
	if not _intro_active:
		return
	_intro_active = false
	intro_played = true
	_apply_intro_state()
	# Write it down right away if this world already has a save slot; the flag is
	# also part of every normal save/resume of the level.
	if world_boot_complete and SaveGame.current_slot > 0:
		SaveGame.save_game(self)

## Opens a confirmation, then wipes this world and starts over as a new player.
## Also callable from a menu button: get_tree().get_first_node_in_group("Level").request_delete_world()
func request_delete_world() -> void:
	if not world_boot_complete:
		return
	if _delete_dialog == null:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.title = "Delete world"
		_delete_dialog.dialog_text = "Delete this world and start over as a brand-new player?\nThis cannot be undone."
		_delete_dialog.ok_button_text = "Delete"
		_delete_dialog.confirmed.connect(_delete_world_and_restart)
		add_child(_delete_dialog)
	_delete_dialog.popup_centered()

func _delete_world_and_restart() -> void:
	world_boot_complete = false # stops autosaves from rewriting the world during teardown
	var slot: int = SaveGame.current_slot
	if slot > 0:
		SaveGame.delete_save(slot)
	# If the save system keeps a separate "resume" file, clear that too.
	for method_name in ["clear_resume", "delete_resume"]:
		for method_info in SaveGame.get_method_list():
			if method_info.get("name") == method_name and (method_info.get("args", []) as Array).is_empty():
				SaveGame.call(method_name)
	SaveGame.current_slot = 0
	SaveGame.new_world_requested = true # skip resume/load; _ready builds a fresh world
	intro_played = false
	_apply_intro_state()
	# Reloading the scene re-runs everything (NPC intros included) like a first launch.
	if scene_file_path != "":
		get_tree().change_scene_to_file(scene_file_path)
	else:
		get_tree().reload_current_scene()

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
	# Ctrl+Shift+Backspace (Cmd+Shift+Backspace on macOS) opens "Delete world".
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.is_command_or_control_pressed() and event.shift_pressed \
			and (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE):
		request_delete_world()

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
				if object.global_position.distance_to(pos) < 24:
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

	if _terrain_cache.is_empty():
		_cache_terrain()

	return {
		"world_seed": world_seed,
		"spawn_position": _vector_to_data(spawn_position) if spawn_position.is_finite() else [],
		"shop_position": _vector_to_data(_get_shop().global_position) if _get_shop() != null else [],
		"world": {
			"water": _terrain_cache["water"],
			"ground_1": _terrain_cache["ground_1"],
			"ground_2": _terrain_cache["ground_2"],
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
		"npcs": npcs,
		"intro_played": intro_played,
		"npcs_spread_v2": _npcs_spread
	}

func apply_save_data(save_data: Dictionary) -> void:
	# Saves made before this flag existed were already past the intro.
	intro_played = bool(save_data.get("intro_played", true))
	_npcs_spread = bool(save_data.get("npcs_spread_v2", false))
	world_seed = int(save_data.get("world_seed", 0))

	var world_data: Variant = save_data.get("world", {})
	if world_data is Dictionary and world_data.has("water") and world_data.has("ground_1") and world_data.has("ground_2") and world_data.has("environment"):
		_restore_tile_layer(water, world_data.get("water", []))
		_restore_tile_layer(ground_1, world_data.get("ground_1", []))
		_restore_tile_layer(ground_2, world_data.get("ground_2", []))
		_restore_tile_layer(environment, world_data.get("environment", []))
		_remove_water_trees()
		_limit_tree_count()
		_cache_terrain()
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
		_last_damage_time = Time.get_ticks_msec() / 1000.0
		_update_health_bar()

	var spawn_data: Variant = save_data.get("spawn_position", [])
	if spawn_data is Array and spawn_data.size() >= 2:
		spawn_position = _data_to_vector(spawn_data)

	var shop_node := _get_shop()
	if shop_node != null:
		var shop_data: Variant = save_data.get("shop_position", [])
		if shop_data is Array and shop_data.size() >= 2:
			shop_node.global_position = _data_to_vector(shop_data)
		else:
			_place_shop_near_player()

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
	_rescue_stranded_npcs()
	_restore_plants(save_data.get("plants", []))
	_restore_dropped_items(save_data.get("dropped_items", []))

func _serialize_tile_layer(layer: TileMapLayer) -> Dictionary:
	var packed := PackedInt32Array()
	for coord in layer.get_used_cells():
		var atlas := layer.get_cell_atlas_coords(coord)
		packed.append(coord.x)
		packed.append(coord.y)
		packed.append(layer.get_cell_source_id(coord))
		packed.append(atlas.x)
		packed.append(atlas.y)
		packed.append(layer.get_cell_alternative_tile(coord))
	return {"packed": Marshalls.raw_to_base64(packed.to_byte_array())}

func _cache_terrain() -> void:
	_terrain_cache = {
		"water": {"full": true},
		"ground_1": _serialize_tile_layer(ground_1),
		"ground_2": _serialize_tile_layer(ground_2)
	}

func _fill_water(layer: TileMapLayer) -> void:
	for x in range(-width / 2, width / 2):
		for y in range(-height / 2, height / 2):
			layer.set_cell(Vector2i(x, y), source_id, water_atlas)

func _restore_tile_layer(layer: TileMapLayer, cell_data: Variant) -> void:
	layer.clear()
	if cell_data is Dictionary:
		if cell_data.has("full"):
			_fill_water(layer)
			return
		var values := Marshalls.base64_to_raw(str(cell_data.get("packed", ""))).to_int32_array()
		for i in range(0, values.size() - 5, 6):
			layer.set_cell(Vector2i(values[i], values[i + 1]), values[i + 2], Vector2i(values[i + 3], values[i + 4]), values[i + 5])
		return
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

## For existing worlds: bring NPCs that are stranded on other islands back to the
## player's island, and (once per world) spread them out the same way new worlds do.
func _rescue_stranded_npcs() -> void:
	if player == null:
		return
	var land: Dictionary = {}
	for cell in ground_1.get_used_cells():
		land[cell] = true
	for cell in ground_2.get_used_cells():
		land[cell] = true
	var start: Vector2i = ground_2.local_to_map(ground_2.to_local(player.global_position))
	if not land.has(start):
		return
	var reachable: Dictionary = {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + offset
			if land.has(neighbor) and not reachable.has(neighbor):
				reachable[neighbor] = true
				stack.append(neighbor)
	var grass_set: Dictionary = {}
	var reachable_grass: Array = []
	for cell in ground_2.get_used_cells():
		grass_set[cell] = true
		if reachable.has(cell):
			reachable_grass.append(cell)
	if reachable_grass.is_empty():
		return
	var avoid_cells: Array[Vector2i] = [start]
	var shop_node := _get_shop()
	if shop_node != null:
		avoid_cells.append(ground_2.local_to_map(ground_2.to_local(shop_node.global_position)))
	var taken: Dictionary = {}
	var npc_cells: Array[Vector2i] = []
	for npc in get_tree().get_nodes_in_group("NPC"):
		var npc_cell: Vector2i = ground_2.local_to_map(ground_2.to_local(npc.global_position))
		if _npcs_spread and reachable.has(npc_cell):
			npc_cells.append(npc_cell)
			continue
		var new_cell: Vector2i = _pick_npc_cell(reachable_grass, grass_set, start, avoid_cells, npc_cells, taken)
		taken[new_cell] = true
		npc_cells.append(new_cell)
		npc.global_position = _cell_to_global(new_cell)
	_npcs_spread = true

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
	_cache_terrain()

func _get_shop() -> Node2D:
	var found: Node2D = get_node_or_null("Objects/shop")
	if found != null:
		return found
	for child in $Objects.get_children():
		var lowered := String(child.name).to_lower()
		if child is Node2D and (lowered.contains("shop") or lowered.contains("seller") or lowered.contains("stall") or lowered.contains("trader")):
			return child
	return null

func _place_shop_near_player() -> void:
	var shop_node := _get_shop()
	if shop_node == null or player == null:
		return
	var grass_set: Dictionary = {}
	for cell in ground_2.get_used_cells():
		grass_set[cell] = true
	var wanted: Vector2i = ground_2.local_to_map(ground_2.to_local(player.global_position + Vector2(64, 48)))
	var cell: Vector2i = _nearest_free_grass_cell(wanted, grass_set, {})
	shop_node.global_position = ground_2.to_global(ground_2.map_to_local(cell))

func _cell_to_global(cell: Vector2i) -> Vector2:
	return ground_2.to_global(ground_2.map_to_local(cell))

func _place_entities_on_grass() -> void:
	var grass_set: Dictionary = {}
	for cell in grass_tiles_arr:
		grass_set[cell] = true
	if grass_set.is_empty():
		return
	var islands := _find_islands(grass_set)
	if islands.is_empty():
		return

	var main_set: Dictionary = {}
	for cell in islands[0]:
		main_set[cell] = true
	var taken: Dictionary = {}
	var placed: Array[Vector2] = []

	var anchor: Vector2i = _find_spawn_cell(main_set)
	if player != null:
		player.global_position = _cell_to_global(anchor)
		taken[anchor] = true
		placed.append(player.global_position)
		spawn_position = player.global_position
	var avoid_cells: Array[Vector2i] = [anchor]
	var shop: Node2D = _get_shop()
	if shop != null:
		var shop_cell: Vector2i = _nearest_free_grass_cell(anchor + Vector2i(4, 3), main_set, taken)
		taken[shop_cell] = true
		shop.global_position = _cell_to_global(shop_cell)
		placed.append(shop.global_position)
		avoid_cells.append(shop_cell)

	# Spread the NPCs across the player's own island so each one is in a different
	# area, all reachable on foot, none stacked together and none too far away.
	var npc_cells: Array[Vector2i] = []
	for npc in get_tree().get_nodes_in_group("NPC"):
		var npc_cell: Vector2i = _pick_npc_cell(islands[0], grass_set, anchor, avoid_cells, npc_cells, taken)
		taken[npc_cell] = true
		npc_cells.append(npc_cell)
		npc.global_position = _cell_to_global(npc_cell)
		placed.append(npc.global_position)
	_npcs_spread = true

## Picks a grass cell that is between the min/max distance from the player's start,
## away from the start/shop, and as far as possible from the NPCs already placed
## (but at least NPC_MIN_SPACING_CELLS). If the island is too small to satisfy the
## rules, they are relaxed step by step instead of failing.
func _pick_npc_cell(cells: Array, grass_set: Dictionary, anchor: Vector2i, avoid_cells: Array[Vector2i], npc_cells: Array[Vector2i], taken: Dictionary) -> Vector2i:
	var min_dist := NPC_MIN_SPAWN_DISTANCE_CELLS
	var max_dist := NPC_MAX_SPAWN_DISTANCE_CELLS
	var spacing := NPC_MIN_SPACING_CELLS
	for _relax in 5:
		var best := Vector2i.ZERO
		var best_score := -1.0
		for _attempt in 200:
			var cell: Vector2i = cells[randi() % cells.size()]
			if taken.has(cell) or not _has_grass_clearing(cell, grass_set):
				continue
			var from_start := (cell - anchor).length()
			if from_start < min_dist or from_start > max_dist:
				continue
			var too_close_to_avoid := false
			for avoid in avoid_cells:
				if (cell - avoid).length() < 8.0:
					too_close_to_avoid = true
					break
			if too_close_to_avoid:
				continue
			var nearest := 9999.0
			for other in npc_cells:
				nearest = minf(nearest, (cell - other).length())
			if nearest < spacing:
				continue
			if nearest > best_score:
				best_score = nearest
				best = cell
		if best_score >= 0.0:
			return best
		min_dist *= 0.5
		max_dist *= 1.25
		spacing *= 0.7
	return cells[randi() % cells.size()]

func _find_islands(grass_set: Dictionary) -> Array:
	var land: Dictionary = grass_set.duplicate()
	for cell in sand_tiles_arr:
		land[cell] = true
	var visited: Dictionary = {}
	var islands: Array = []
	for start in land:
		if visited.has(start):
			continue
		var grass_cells: Array = []
		var stack: Array[Vector2i] = [start]
		visited[start] = true
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			if grass_set.has(current):
				grass_cells.append(current)
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = current + offset
				if land.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					stack.append(neighbor)
		if grass_cells.size() >= MIN_ISLAND_GRASS_CELLS:
			islands.append(grass_cells)
	islands.sort_custom(func(a: Array, b: Array): return a.size() > b.size())
	return islands

func _scatter_cell(island: Array, grass_set: Dictionary, taken: Dictionary, placed: Array[Vector2]) -> Vector2i:
	var fallback: Vector2i = island[randi() % island.size()]
	for attempt in 80:
		var cell: Vector2i = island[randi() % island.size()]
		if taken.has(cell) or not _has_grass_clearing(cell, grass_set):
			continue
		fallback = cell
		var world_pos := _cell_to_global(cell)
		var far_enough := true
		for other in placed:
			if world_pos.distance_to(other) < 96.0:
				far_enough = false
				break
		if far_enough:
			return cell
	return fallback

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
		protected_positions.append(player.global_position)
	for npc in get_tree().get_nodes_in_group("NPC"):
		protected_positions.append(npc.global_position)
	var shop: Node2D = _get_shop()
	if shop != null:
		protected_positions.append(shop.global_position)

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
			var density: float = 1.0 # plains: solitary_tree_chance alone decides
			if is_forest:
				density = remap(clampf(t_noise_val, threshold, 0.55), threshold, 0.55, 0.40, 0.80)

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
			# `cell` is a ground_2 cell; compare in world space.
			var world_pos: Vector2 = _cell_to_global(cell)
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
		# The environment layer lives under $Objects, which is offset from the ground
		# layers, so the same cell number is a different place. Go through world space.
		var env_cell: Vector2i = environment.local_to_map(environment.to_local(_cell_to_global(cell)))
		if environment.get_cell_source_id(env_cell) != -1:
			continue
		# Place tree scene tile in environment layer (scene tile 2 in collection source 2)
		environment.set_cell(env_cell, tree_source_id, Vector2i(0, 0), 2)
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
	for env_cell in environment.get_used_cells():
		if environment.get_cell_source_id(env_cell) != tree_source_id:
			continue
		var world_pos: Vector2 = environment.to_global(environment.map_to_local(env_cell))
		var ground_cell: Vector2i = ground_2.local_to_map(ground_2.to_local(world_pos))
		if not _has_grass_tile_clearing(ground_cell):
			environment.erase_cell(env_cell)

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
	_check_player_stuck(delta)
	_regenerate_health(delta)
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
		var env_cell: Vector2i = environment.local_to_map(environment.to_local(spawn_pos))
		if not _has_land_clearing(cell) or environment.get_cell_source_id(env_cell) != -1:
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
	_last_damage_time = now
	player_health = maxi(0, player_health - amount)
	_update_health_bar()
	player.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(player, "modulate", Color.WHITE, 0.25)
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
	health_changed.emit(player_health, player_max_health)
	# Drive the health bar that is already in the scene (Overlay/CanvasLayer/healthbar).
	# Its max_value is the editor default (100), so set it to the real max here.
	if healthbar != null:
		healthbar.max_value = player_max_health
		healthbar.value = player_health
	for bar in get_tree().get_nodes_in_group("HealthBar"):
		if bar is Range and bar != healthbar:
			bar.max_value = player_max_health
			bar.value = player_health

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
	intro_played = false
	_npcs_spread = false
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

func _regenerate_health(delta: float) -> void:
	if player_health <= 0 or player_health >= player_max_health:
		_regen_elapsed = 0.0
		return
	if Time.get_ticks_msec() / 1000.0 - _last_damage_time < health_regen_delay:
		_regen_elapsed = 0.0
		return
	_regen_elapsed += delta
	if _regen_elapsed >= health_regen_interval:
		_regen_elapsed = 0.0
		player_health += 1
		_update_health_bar()

func _check_player_stuck(delta: float) -> void:
	if player == null or player.get("can_move") == null:
		return
	var map_ui := get_node_or_null("Overlay/UserInterface/map")
	var ui_open: bool = map_ui != null and bool(map_ui.get("is_open"))
	var dialogic_node := get_node_or_null("/root/Dialogic")
	var in_dialogue: bool = dialogic_node != null and dialogic_node.get("current_timeline") != null
	var locked: bool = not bool(player.get("can_move")) or not player.is_physics_processing()
	if not locked or ui_open or in_dialogue:
		_stuck_elapsed = 0.0
		return
	_stuck_elapsed += delta
	if _stuck_elapsed >= 3.0:
		_stuck_elapsed = 0.0
		player.can_move = true
		player.set_physics_process(true)
		player.process_mode = Node.PROCESS_MODE_INHERIT

func _setup_profile_persistence() -> void:
	var profile_root := get_node_or_null("Overlay/UserInterface/map/pages/profile")
	if profile_root == null:
		return
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	for field in _find_text_fields(profile_root):
		var key := str(profile_root.get_path_to(field))
		if config.has_section_key("profile", key):
			field.text = str(config.get_value("profile", key))
		if field is LineEdit:
			field.text_changed.connect(_on_profile_line_changed.bind(key))
		else:
			field.text_changed.connect(_on_profile_text_edited.bind(field, key))

func _find_text_fields(node: Node) -> Array:
	var fields: Array = []
	for child in node.get_children():
		if child is LineEdit or child is TextEdit:
			fields.append(child)
		fields.append_array(_find_text_fields(child))
	return fields

func _on_profile_line_changed(new_text: String, key: String) -> void:
	_store_profile_value(key, new_text)

func _on_profile_text_edited(field: TextEdit, key: String) -> void:
	_store_profile_value(key, field.text)

func _store_profile_value(key: String, value: String) -> void:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	config.set_value("profile", key, value)
	config.save(PROFILE_PATH)
