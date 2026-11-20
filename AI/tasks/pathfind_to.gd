extends BTAction

## Behavior tree task for pathfinding to a target position

@export var target_var: StringName = &"path_target"
@export var arrival_tolerance: float = 12.0
@export var recalculate_interval: float = 2.0

var last_recalculation: float = 0.0

func _tick(delta: float) -> Status:
	var nav = agent.get_node_or_null("NPCNavigation")
	if nav == null:
		return FAILURE
	
	var target: Vector2 = blackboard.get_var(target_var)
	if target == Vector2.INF or target == Vector2.ZERO:
		return FAILURE
	
	# Check if already at target
	if agent.global_position.distance_to(target) <= arrival_tolerance:
		nav.stop()
		return SUCCESS
	
	# Request/recalculate path periodically
	last_recalculation += delta
	if last_recalculation >= recalculate_interval or not nav.is_following_path:
		last_recalculation = 0.0
		var success := nav.request_path(target, true)
		if not success:
			return FAILURE
	
	# Check if path is complete
	if not nav.is_following_path and nav.get_remaining_distance() <= arrival_tolerance:
		return SUCCESS
	
	# Still following path
	return RUNNING