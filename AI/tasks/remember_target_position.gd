extends BTAction

@export var target_var: StringName = &"target"
@export var position_var: StringName = &"last_target_position"

func _tick(_delta: float) -> Status:
	var target = blackboard.get_var(target_var)
	if not is_instance_valid(target) or not target is Node2D:
		return FAILURE
	blackboard.set_var(position_var, target.global_position)
	return SUCCESS
