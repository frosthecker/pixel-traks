extends VehicleBody3D

@export var max_engine_force: float = 3000.0
@export var max_brake_force: float = 100.0
@export var max_speed: float = 10.0
@export var max_steering_angle: float = 0.5
@export var drift_steering_angle: float = 0.75 # Extra steering angle while drifting

@export var normal_friction: float = 3.0
@export var drift_friction: float = 0.8 # Lower friction allows rear wheels to slide

@onready var front_left_wheel: VehicleWheel3D = $f1_wheel
@onready var front_right_wheel: VehicleWheel3D = $fr_wheel
@onready var rear_left_wheel: VehicleWheel3D = $b1_wheel
@onready var rear_right_wheel: VehicleWheel3D = $br_wheel

var is_drifting: bool = false

func _physics_process(delta: float) -> void:
	# Driving Inputs
	var steer_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var accelerate_input = Input.get_action_strength("accelerate")
	var brake_input = Input.get_action_strength("brake")

	# VehicleBody3D's model-forward direction is +Z, matching this car model.
	engine_force = accelerate_input * max_engine_force
	brake = brake_input * max_brake_force
	if accelerate_input > 0.0:
		sleeping = false
		var forward: Vector3 = global_transform.basis.z.normalized()
		var target_velocity: Vector3 = Vector3(forward.x, 0.0, forward.z) * (accelerate_input * max_speed)
		linear_velocity = Vector3(target_velocity.x, linear_velocity.y, target_velocity.z)
	elif brake_input > 0.0:
		var horizontal_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, max_brake_force * delta)
		linear_velocity = Vector3(horizontal_velocity.x, linear_velocity.y, horizontal_velocity.z)
	
	# Handle Drift State Input
	if Input.is_action_pressed("drift"):
		is_drifting = true
	else:
		is_drifting = false

	# Apply Steering & Drift Handling
	if is_drifting:
		# Increase turning radius and drop rear wheel traction
		steering = steer_input * drift_steering_angle
		rear_left_wheel.wheel_friction_slip = drift_friction
		rear_right_wheel.wheel_friction_slip = drift_friction
		
		# Optional: Add rotational force to help initiate the tail slide
		if steer_input != 0:
			apply_torque_impulse(Vector3.UP * steer_input * 100.0 * delta)
	else:
		# Restore regular driving mechanics
		steering = steer_input * max_steering_angle
		rear_left_wheel.wheel_friction_slip = normal_friction
		rear_right_wheel.wheel_friction_slip = normal_friction
