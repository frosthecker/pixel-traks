extends BTCondition

@export var target_var: StringName = &"target"
@export_flags_2d_physics var collision_mask: int = 1

func _tick(_delta: float) -> Status:
	var target = blackboard.get_var(target_var)
	if not is_instance_valid(target) or not target is Node2D:
		return FAILURE

	var query := PhysicsRayQueryParameters2D.create(agent.global_position, target.global_position)
	query.collision_mask = collision_mask
	query.exclude = [agent.get_rid()]
	var hit: Dictionary = agent.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return SUCCESS

	var collider = hit.get("collider")
	if collider == target:
		return SUCCESS
	if collider is Node and target is Node and target.is_ancestor_of(collider):
		return SUCCESS
	return FAILURE
