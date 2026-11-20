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
	_enter_idle_state()

func _physics_process(delta: float) -> void:
	if not creature_actor:
		return

	# CreatureActor is a visual/motor node, not a PhysicsBody2D. Validate its
	# position against the generated TileMaps and undo any step that crosses the
	# habitat boundary or a tree.
	if _can_occupy(creature_actor.global_position):
		last_safe_ground_position = creature_actor.get("GroundPosition")
	else:
		creature_actor.call("Teleport", last_safe_ground_position)
		_enter_idle_state()
		return

	# Count down the current state timer
	state_timer -= delta
	if state_timer <= 0.0:
		if current_state == State.IDLE:
			_enter_walk_state()
		else:
			_enter_idle_state()
			
	# Feed the current velocity (either zero or walking) to the C# motor
	if not _can_occupy(creature_actor.global_position + move_velocity * delta):
		_enter_idle_state()
	creature_actor.set("MoveVelocity", move_velocity)

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
	var level := get_tree().get_first_node_in_group("Level")
	return level != null and level.can_creature_occupy(world_position, habitat)
