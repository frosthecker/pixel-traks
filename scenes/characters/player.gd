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
		get_basic_input()

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
	if Input.is_action_just_pressed("style"):
		current_style = posmod(current_style + 1, Enum.Style.size()) as Enum.Style
		sprite.texture = Data.PLAYER_SKINS[current_style] 
	if Input.is_action_just_pressed("tool_backward"):
		current_tool = posmod(current_tool + 1, Enum.Tool.size()) as Enum.Tool
		print(current_tool)
		tool_ui.reveal(true)
		
	if Input.is_action_just_pressed("seed_forward"):
		current_seed = posmod(current_seed + 1, Enum.Seed.size()) as Enum.Seed
		tool_ui.reveal(false)
		print(current_seed)
	
	if Input.is_action_just_pressed("action"):
		# Check if the player is facing up or down
		if last_direction == Vector2.UP or last_direction == Vector2.DOWN:
			print("Cannot use tools while facing up or down!")
			return # Exit the block early so the tool is not used
			
		can_move = false
		tool_state_machine.travel(Data.TOOL_STATE_ANIMATIONS[current_tool])
		animation_tree.set("parameters/ToolOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
	if Input.is_action_pressed("pick"):
		for pickup_item in $PickupZone.items_in_range.values():
			if pickup_item.has_method("hit"):
				print("tree picked")
				break
			elif pickup_item.has_method("pick_up_item"):
				pickup_item.pick_up_item(self)
				$PickupZone.items_in_range.erase(pickup_item)
				print('log picked')
				break

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
