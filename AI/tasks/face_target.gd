extends BTAction

@export var target_var: StringName = &"target"

func _tick(_delta: float) -> Status:
	var target = blackboard.get_var(target_var)
	if not is_instance_valid(target) or not target is Node2D:
		return FAILURE

	var direction: Vector2 = agent.global_position.direction_to(target.global_position).round()
	if direction.is_zero_approx():
		return SUCCESS
	agent.last_direction = direction
	if agent.has_method("animate"):
		agent.animate()
	return SUCCESS
