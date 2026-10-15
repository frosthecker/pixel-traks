extends BTAction

@export var range_min_in_dir: float = 40.0
@export var range_max_in_dir: float = 100.0

@export var position_var: StringName = &"pos"
@export var dir_var: StringName = &"dir"

func _tick(_delta: float) -> Status:
	var dir: Vector2 = rando_dir()
	var pos: Vector2 = agent.global_position + dir * randf_range(range_min_in_dir, range_max_in_dir)

	# Do not deliberately choose a target through a collision wall or obstacle.
	# Try several random directions before accepting a fallback target.
	for _attempt in range(8):
		dir = rando_dir()
		var candidate: Vector2 = agent.global_position + dir * randf_range(range_min_in_dir, range_max_in_dir)
		if _path_is_clear(candidate):
			pos = candidate
			break
	
	blackboard.set_var(position_var, pos)
	print("random move ", dir, " -> ", pos)
	return SUCCESS

func _path_is_clear(target: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(agent.global_position, target)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [agent.get_rid()]
	return agent.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func rando_dir() -> Vector2:
	var directions: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var dir: Vector2 = directions[randi_range(0, directions.size() - 1)]
	blackboard.set_var(dir_var, dir)
	return dir
	
