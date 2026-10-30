extends BTAction

@export var target_pos_var := &"pos"
@export var dir_var := &"dir"
@export var speed_var: float = 40.0
@export var tolerance: float = 10.0

var last_position: Vector2
var stuck_time: float = 0.0
var active_target: Vector2

func _tick(delta: float) -> Status:
	var target_pos: Vector2 = blackboard.get_var(target_pos_var)
	var dir: Vector2 = blackboard.get_var(dir_var)

	if target_pos != active_target:
		active_target = target_pos
		last_position = agent.global_position
		stuck_time = 0.0
	
	if agent.global_position.distance_to(target_pos) <= tolerance:
		agent.move(Vector2.ZERO, 0.0)
		return SUCCESS 

	if agent.global_position.distance_to(last_position) < 0.1:
		stuck_time += delta
	else:
		stuck_time = 0.0
	last_position = agent.global_position

	# A collision in the requested direction means this target is unreachable.
	# Fail the sequence so random_pos can choose another target.
	if agent.get_slide_collision_count() > 0:
		for index in range(agent.get_slide_collision_count()):
			var collision: KinematicCollision2D = agent.get_slide_collision(index)
			if collision.get_normal().dot(dir) < -0.2:
				agent.move(Vector2.ZERO, 0.0)
				return FAILURE

	if stuck_time >= 0.75:
		agent.move(Vector2.ZERO, 0.0)
		return FAILURE

	agent.move(dir, speed_var)
	return RUNNING
	
