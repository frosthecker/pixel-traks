extends Node2D

const CREATURE_SCENE = preload("res://addons/procedural_creatures/Runtime/CreatureActor.tscn")
var creature_actor: Node2D

enum Habitat { LAND, WATER, AIR }
@export var habitat: Habitat = Habitat.LAND
## Leave blank to generate a family appropriate to the creature's habitat.
@export_file("*.json") var preset_path: String = ""

# State machine variables
enum State { IDLE, WALKING }
var current_state: State = State.IDLE
var state_timer: float = 0.0
var move_velocity: Vector2 = Vector2.ZERO

# Customizable behavior settings
@export var walk_speed: float = 45.0
@export var min_idle_time: float = 1.5
@export var max_idle_time: float = 4.0
@export var min_walk_time: float = 1.0
@export var max_walk_time: float = 3.0

var last_safe_ground_position := Vector2.ZERO
var _level: Node
var _player: Node2D
var _occupy_check_elapsed := 0.0
var _actor_check_elapsed := 0.0
var _actor_processing := true
const OCCUPY_CHECK_INTERVAL := 0.15
## Creatures farther than this from the player are frozen until the player
## comes back. Their C# actor still renders when visible, but idle distant
## actors no longer consume per-frame simulation time.
const ACTIVE_DISTANCE_SQ := 1000.0 * 1000.0
const ACTOR_CHECK_INTERVAL := 0.5

func _ready() -> void:
	# The actor generates a texture every animation tick. These settings keep a
	# population inexpensive: low-detail animation and no raster work off screen.
	creature_actor = CREATURE_SCENE.instantiate()
	creature_actor.set("PresetPath", preset_path)
	if preset_path.is_empty():
		creature_actor.set("FamilyId", _family_for_habitat())
		creature_actor.set("SeedText", str(randi()))
	creature_actor.set("Paused", false)
	creature_actor.set("AutoMove", true)
	creature_actor.set("AnimationFps", 8)
	creature_actor.set("Quality", 0)
	creature_actor.set("CullOffscreen", true)
	creature_actor.set("CullMargin", 32)
	add_child(creature_actor)
	last_safe_ground_position = creature_actor.get("GroundPosition")
	_level = get_tree().get_first_node_in_group("Level")
	_player = get_tree().get_first_node_in_group("Player") as Node2D
	_occupy_check_elapsed = randf() * OCCUPY_CHECK_INTERVAL
	_enter_idle_state()

func _physics_process(delta: float) -> void:
	if not creature_actor:
		return

	_actor_check_elapsed += delta
	if _actor_check_elapsed >= ACTOR_CHECK_INTERVAL:
		_actor_check_elapsed = 0.0
		_update_actor_processing()
	if not _actor_processing:
		return

	# CreatureActor is a visual/motor node, not a PhysicsBody2D. Validate its
	# position against the generated TileMaps and undo any step that crosses the
	# habitat boundary or a tree. Checking a few times per second instead of
	# twice every physics frame keeps dozens of creatures cheap.
	_occupy_check_elapsed += delta
	var check_now := _occupy_check_elapsed >= OCCUPY_CHECK_INTERVAL
	if check_now:
		_occupy_check_elapsed = 0.0
		if not _can_occupy(creature_actor.global_position):
			creature_actor.call("Teleport", last_safe_ground_position)
			_enter_idle_state()
			creature_actor.set("MoveVelocity", Vector2.ZERO)
			return
		last_safe_ground_position = creature_actor.get("GroundPosition")

	# Count down the current state timer
	state_timer -= delta
	if state_timer <= 0.0:
		if current_state == State.IDLE:
			_enter_walk_state()
		else:
			_enter_idle_state()

	# Feed the current velocity (either zero or walking) to the C# motor
	if check_now and not move_velocity.is_zero_approx():
		if not _can_occupy(creature_actor.global_position + move_velocity * delta):
			_enter_idle_state()
	creature_actor.set("MoveVelocity", move_velocity)

func _update_actor_processing() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("Player") as Node2D
	if _player == null:
		return
	var should_process := global_position.distance_squared_to(_player.global_position) <= ACTIVE_DISTANCE_SQ
	if should_process == _actor_processing:
		return
	_actor_processing = should_process
	creature_actor.set_process(should_process)
	creature_actor.set_physics_process(should_process)
	creature_actor.set("Paused", not should_process)
	if not should_process:
		_enter_idle_state()
		creature_actor.set("MoveVelocity", Vector2.ZERO)

func _enter_idle_state() -> void:
	current_state = State.IDLE
	move_velocity = Vector2.ZERO
	state_timer = randf_range(min_idle_time, max_idle_time)

func _enter_walk_state() -> void:
	current_state = State.WALKING
	# Pick a random angle (0 to 360 degrees in radians) and multiply by speed
	var random_angle = randf_range(0.0, TAU)
	move_velocity = Vector2.RIGHT.rotated(random_angle) * walk_speed
	state_timer = randf_range(min_walk_time, max_walk_time)

func _family_for_habitat() -> String:
	match habitat:
		Habitat.WATER: return "aquatic"
		Habitat.AIR: return "winged"
		_: # Land: pick from all land families
			var land_families := ["quadruped", "biped", "reptile", "arthropod", "amorphous", "serpent"]
			return land_families.pick_random()

func _can_occupy(world_position: Vector2) -> bool:
	if _level == null or not is_instance_valid(_level):
		_level = get_tree().get_first_node_in_group("Level")
	return _level != null and _level.can_creature_occupy(world_position, habitat)
