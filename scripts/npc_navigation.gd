class_name NPCNavigation extends Node

signal path_completed
signal path_blocked(blocked_position: Vector2)
signal path_recalculated(new_path: Array)

@export var agent_radius: float = 16.0
@export var path_optimization: bool = true
@export var max_path_length: float = 5000.0
@export var recalculation_interval: float = 1.0
@export var stuck_threshold: float = 8.0
@export var stuck_time: float = 2.0

@export var movement_speed_multiplier: float = 1.0
@export var stop_at_target: bool = true
@export var arrival_distance: float = 12.0

var current_path: Array = []
var current_path_index: int = 0
var target_position: Vector2 = Vector2.INF
var is_following_path: bool = false
var last_recalculation_time: float = 0.0
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO
var avoidance_enabled: bool = true

var _npc: Node
var _nav_map: RID

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	pass

func _follow_path(delta: float) -> void:
	pass

func _apply_avoidance(base_direction: Vector2) -> Vector2:
	return base_direction

func _check_stuck(delta: float) -> void:
	pass

func _on_stuck() -> void:
	pass

func _maybe_recalculate_path(delta: float) -> void:
	pass

func _is_path_valid() -> bool:
	return true

func _on_path_completed() -> void:
	pass

func request_path(target: Vector2, force_recalculate: bool = false) -> bool:
	return false

func stop() -> void:
	pass

func set_paused(paused: bool) -> void:
	pass

func set_speed_multiplier(multiplier: float) -> void:
	pass

func set_arrival_distance(distance: float) -> void:
	pass

func get_current_path() -> Array:
	return []

func get_remaining_distance() -> float:
	return 0.0

func get_next_waypoint() -> Vector2:
	return Vector2.INF