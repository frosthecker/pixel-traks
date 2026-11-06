extends CharacterBody2D

var direction: Vector2
var last_direction: Vector2 = Vector2.DOWN
var speed = 50
var current_tool: Enum.Tool = Enum.Tool.AXE
var current_seed: Enum.Seed
var can_move: bool = true
var is_in_water: bool = false
var water_layer: TileMapLayer
var ground_1_layer: TileMapLayer
var ground_2_layer: TileMapLayer
@onready var sprite2d: Sprite2D = $Sprite2D
@onready var tool_ui: Control = $ToolUI
@onready var animation_tree: AnimationTree = $Animation/AnimationTree
@onready var animation_player: AnimationPlayer = $Animation/AnimationPlayer
@onready var move_state_machine = animation_tree.get("parameters/MoveStateMachine/playback")
@onready var tool_state_machine = animation_tree.get("parameters/ToolStateMachine/playback")
signal tool_use(tool: Enum.Tool, pos: Vector2, dir: bool)
@onready var sprite: Sprite2D = $Sprite2D
var current_style = 0
@onready var tool_button: TextureButton = $CanvasLayer/tool
@onready var inventory_button: TextureButton = $CanvasLayer/inventory
@onready var chat_button: TextureButton = $CanvasLayer/chat
@onready var seed_button: TextureButton = $CanvasLayer/seed
var tool_but_pressed: bool = false
var seed_but_pressed: bool = false
var inventory_but_pressed: bool = false
var chat_but_pressed: bool = false
var action_but_pressed: bool = false
var pick_but_pressed: bool = false
var style_but_pressed: bool = false

#grass sfx variables
@onready var grass_sfx = $grass
var footstep_timer: float = 0.0
@export var footstep_interval: float = 0.35

func _ready() -> void:
	animation_tree.active = true

func _physics_process(delta: float) -> void:
	if current_style == 2:
		sprite2d.vframes = 18
	else:
		sprite2d.vframes = 17
	if not can_move and not animation_tree.get("parameters/ToolOneShot/active"):
		can_move = true
	if can_move:
		move()
		_update_water_state()
		if is_in_water:
			animate_swimming()
		else:
			animate()
			update_footsteps(delta)
		get_basic_input()

func update_footsteps(delta: float) -> void:
	if is_in_water or direction.is_zero_approx():
		footstep_timer = 0.0
		return
							
	footstep_timer -= delta
								
	if footstep_timer <= 0.0:
		if not grass_sfx.playing:
			grass_sfx.pitch_scale = randf_range(0.9, 1.1)
			grass_sfx.play()
																			
		footstep_timer = footstep_interval

## store world layers in cache memory to make game load faster
func _cache_world_layers() -> void:
	if is_instance_valid(water_layer):
		return
	var level := get_tree().current_scene
	if level == null:
		return
	water_layer = level.get_node_or_null("Layers/water") as TileMapLayer
	ground_1_layer = level.get_node_or_null("Layers/ground_1") as TileMapLayer
	ground_2_layer = level.get_node_or_null("Layers/ground_2") as TileMapLayer

##fetch basic inputs from user and map it to expected functions and animations
func get_basic_input():
	if Input.is_action_just_pressed("style") or style_but_pressed == true:
		current_style = posmod(current_style + 1, Enum.Style.size()) as Enum.Style
		sprite.texture = Data.PLAYER_SKINS[current_style] 
		style_but_pressed = false
		
	if Input.is_action_just_pressed("tool_backward") or tool_but_pressed:
		current_tool = posmod(current_tool + 1, Enum.Tool.size()) as Enum.Tool
		print(current_tool)
		tool_ui.reveal(true)
		tool_but_pressed = false
		
	if Input.is_action_just_pressed("seed_forward") or seed_but_pressed:
		current_seed = posmod(current_seed + 1, Enum.Seed.size()) as Enum.Seed
		tool_ui.reveal(false)
		print(current_seed)
		seed_but_pressed = false
		
	if Input.is_action_just_pressed("action") or action_but_pressed:
		# Check if the player is facing up or down
		if last_direction == Vector2.UP or last_direction == Vector2.DOWN:
			print("Cannot use tools while facing up or down!")
			action_but_pressed = false
			return # Exit the block early so the tool is not used
			
		can_move = false
		tool_state_machine.travel(Data.TOOL_STATE_ANIMATIONS[current_tool])
		animation_tree.set("parameters/ToolOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		action_but_pressed = false
		
	if Input.is_action_just_pressed("pick") or pick_but_pressed:
		for pickup_item in $PickupZone.items_in_range.values():
			# Trees/stumps also implement hit() and can overlap a dropped log.
			# Prefer an actual pickup instead of stopping at the first hit-able body.
			if pickup_item.has_method("pick_up_item"):
				pickup_item.pick_up_item(self)
				$PickupZone.items_in_range.erase(pickup_item)
				break
		pick_but_pressed = false

	if Input.is_action_just_pressed("interact") or chat_but_pressed:
		chat_but_pressed = false
		interact_with_nearest_npc()
##make player move 
func move():
	direction = Input.get_vector("left", "right", "down", "up")
	if direction:
		last_direction = Vector2(round(direction.x), round(direction.y))
	velocity = direction * speed
	move_and_slide()

##basic movement, idle and tool state animator
func animate():
	if direction:
		var direction_animation = Vector2(round(direction.x), round(direction.y))
		move_state_machine.travel("walk")
		animation_tree.set("parameters/MoveStateMachine/idle/blend_position", direction_animation)
		animation_tree.set("parameters/MoveStateMachine/walk/blend_position", direction_animation)
		var tool_direction = Vector2(round(direction.x), round(direction.y)) if direction else Vector2.DOWN
		for animation in Data.TOOL_STATE_ANIMATIONS.values():
			var animation_name: String = "parameters/ToolStateMachine/" + animation + "/blend_position"
			animation_tree.set(animation_name, tool_direction)
	else:
		move_state_machine.travel("idle")

##animates swimming section (requires separate function because it needs checking of whether player is on water or not)
func animate_swimming() -> void:
	play_swim_animation()

##simple function which plays the swim animation
func play_swim_animation() -> void:
	# Convert current or last direction to a rounded animation vector
	var look_direction = Vector2(round(last_direction.x), round(last_direction.y))
	
	# Always keep the blend position updated so your character faces the correct way
	animation_tree.set("parameters/MoveStateMachine/swim/blend_position", look_direction)
	
	if direction:
		move_state_machine.travel("swim")
	#else:
		# If you don't have a distinct "swim_idle" state, traveling to "idle" is fine,
		# but if your "idle" state doesn't look like swimming, the character will pop out of the water.
		#move_state_machine.travel("idle") 

##this is the function that checks whether the player is on the water tile, if yes, plays swim animation
func _is_water_cell() -> bool:
	_cache_world_layers()
	if not is_instance_valid(water_layer):
		return false
	var cell := water_layer.local_to_map(water_layer.to_local(global_position))
	if water_layer.get_cell_source_id(cell) == -1:
		return false
	# The procedural map uses water as its base layer, then paints land over it.
	# A cell is therefore water only when it has no ground tile on either land layer.
	var has_land := false
	if is_instance_valid(ground_1_layer):
		has_land = ground_1_layer.get_cell_source_id(cell) != -1
	if is_instance_valid(ground_2_layer):
		has_land = has_land or ground_2_layer.get_cell_source_id(cell) != -1
	return not has_land

##updates the water animation state
func _update_water_state() -> void:
	var now_in_water := _is_water_cell()
	if now_in_water == is_in_water:
		return
	is_in_water = now_in_water
	# Cleaned up: No longer disabling the animation tree here

#emits the tool use signal as soon as any tool based animation is played
func tool_use_emit():
	# Tool placement is emitted when the action starts. This method remains for
	# existing animation tracks but must not emit a second time.
	var use_position : Vector2 =  global_position if current_tool == Enum.Tool.WATER else global_position + last_direction * Data.TILE_SIZE
	tool_use.emit(current_tool, use_position, sprite2d.flip_h)
	
	


func _on_tool_pressed() -> void:
	tool_but_pressed = true


func _on_seed_pressed() -> void:
	seed_but_pressed = true


func _on_inventory_pressed() -> void:
	# Find the map menu instance safely by group name rather than hardcoded path
	var map_menu = get_tree().get_first_node_in_group("MapMenu")
	
	if map_menu:
		if map_menu.is_open:
			map_menu.close()
		else:
			map_menu.open()



func _on_chat_pressed() -> void:
	chat_but_pressed = true
	interact_with_nearest_npc()


func _on_action_pressed() -> void:
	action_but_pressed = true


func _on_pick_pressed() -> void:
	pick_but_pressed = true


func interact_with_nearest_npc() -> void:
	if not is_inside_tree():
		return
	var dialogic_node := get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.get("current_timeline") != null:
		return

	var candidates: Array = []
	var npcs = get_tree().get_nodes_in_group("NPC")
	for npc in npcs:
		if not is_instance_valid(npc) or not (npc is Node2D):
			continue
		var dist: float = global_position.distance_to(npc.global_position)
		var max_dist: float = float(npc.get("dialogue_distance")) if npc.get("dialogue_distance") != null else 32.0
		var in_range: bool = dist <= max_dist or (npc.get("player_in_range") == true)
		if in_range:
			candidates.append({"node": npc, "dist": dist})

	var shop = get_tree().current_scene.get_node_or_null("Objects/shop") if get_tree().current_scene else null
	if shop != null and is_instance_valid(shop):
		var dist: float = global_position.distance_to(shop.global_position)
		if shop.get("player_in_range") == true or dist <= 36.0:
			var already_added := false
			for c in candidates:
				if c["node"] == shop:
					already_added = true
					break
			if not already_added:
				candidates.append({"node": shop, "dist": dist})

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var closest_target: Node = candidates[0]["node"]

	if closest_target is Node2D:
		var to_target: Vector2 = (closest_target.global_position - global_position).normalized()
		if not to_target.is_zero_approx():
			last_direction = Vector2(round(to_target.x), round(to_target.y))
			if last_direction.is_zero_approx():
				last_direction = Vector2.DOWN
			animation_tree.set("parameters/MoveStateMachine/idle/blend_position", last_direction)

	if closest_target.has_method("interact"):
		closest_target.call("interact", self)


func _on_style_pressed() -> void:
	style_but_pressed = true
