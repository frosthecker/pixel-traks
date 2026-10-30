extends BTCondition

@export var target_var: StringName = &"target"
@export var min_distance: float = -1.0
@export var max_distance: float = -1.0

func _tick(_delta: float) -> Status:
	var target = blackboard.get_var(target_var)
	if not is_instance_valid(target) or not target is Node2D:
		return FAILURE

	var distance: float = agent.global_position.distance_to(target.global_position)
	if min_distance >= 0.0 and distance < min_distance:
		return FAILURE
	if max_distance >= 0.0 and distance > max_distance:
		return FAILURE
	return SUCCESS
