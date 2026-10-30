extends BTAction

@export var target_var := &"target"
@export var speed_var = 40
@export var tolerance = 20

var last_position: Vector2
var stuck_time: float = 0.0
var active_target: Vector2
var navigation_agent: NavigationAgent2D

func _setup_navigation() -> void:
	if navigation_agent == null:
		navigation_agent = agent.get_node_or_null("NavigationAgent2D")

func _tick(delta: float) -> Status:
	_setup_navigation()
	var target: CharacterBody2D = blackboard.get_var(target_var)
	if target != null:
		var target_position = target.global_position
		var dir: Vector2
		
		if target_position != active_target:
			active_target = target_position
			last_position = agent.global_position
			stuck_time = 0.0
			if navigation_agent != null:
				navigation_agent.target_position = target_position
		
		if agent.global_position.distance_to(target_position) <= tolerance:
			agent.move(Vector2.ZERO, 0.0)
			return SUCCESS 

		# Follow the navigation path around obstacles once the map is ready.
		# During startup, use direct movement until NavigationServer syncs.
		if navigation_agent != null and navigation_agent.get_navigation_map().is_valid():
			var next_path_position := navigation_agent.get_next_path_position()
			if next_path_position != agent.global_position:
				dir = agent.global_position.direction_to(next_path_position)
			else:
				dir = agent.global_position.direction_to(target_position)
		else:
			dir = agent.global_position.direction_to(target_position)

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
	return FAILURE
	
