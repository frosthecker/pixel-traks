class_name Vehicle extends VehicleBody3D

@export_group("Engine & Speed")
@export var torque: float = 12000.0
@export var max_speed_kmh: float = 140.0
@export var reverse_force: float = 6000.0
@export var brake_force: float = 40.0
@export var coast_brake: float = 1.5

@export_group("Steering")
@export var turn_speed: float = 5.0
@export var turn_amount: float = 0.38 # Smooth, predictable turning angle (~22 degrees)
@export var counter_steer_amount: float = 0.55 # Extra range when counter-steering into a slide (~31 degrees)

@export_group("Drift Mechanics")
@export var normal_rear_friction: float = 3.0 # Solid straight-line traction
@export var drift_rear_friction: float = 1.6 # Controlled, smooth slide (not ice)
@export var front_friction: float = 3.2 # Balanced front grip (prevents aggressive pivoting)
@export var friction_transition_speed: float = 5.0 # Smooth, progressive friction drop/recovery
@export var counter_steer_assist: float = 600.0 # Damps excess spin when counter-steering
@export var max_yaw_rate: float = 1.5 # Soft yaw rate cap (rad/s) to prevent sudden snapping
@export var drift_engine_boost: float = 1.15
@export var min_drift_speed_kmh: float = 10.0

@export_group("Wheels")
@export var front_left_wheel: VehicleWheel3D
@export var front_right_wheel: VehicleWheel3D
@export var rear_left_wheel: VehicleWheel3D
@export var rear_right_wheel: VehicleWheel3D
# Backward compatibility references
@export var wheel_trac_l: VehicleWheel3D
@export var wheel_trac_r: VehicleWheel3D

@export_group("Camera")
@export var mouse_sensitivity: float = 0.1

var is_drifting: bool = false
var current_steering: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Auto-locate wheels if not explicitly assigned
	if not front_left_wheel:
		front_left_wheel = get_node_or_null("fl_wheel")
	if not front_right_wheel:
		front_right_wheel = get_node_or_null("fr_wheel")
	if not rear_left_wheel:
		rear_left_wheel = get_node_or_null("bl_wheel")
	if not rear_right_wheel:
		rear_right_wheel = get_node_or_null("br_wheel")
	
	# Fallback to legacy exported variables
	if not front_left_wheel and wheel_trac_l:
		front_left_wheel = wheel_trac_l
	if not front_right_wheel and wheel_trac_r:
		front_right_wheel = wheel_trac_r
	
	# Set initial wheel friction
	if front_left_wheel:
		front_left_wheel.wheel_friction_slip = front_friction
	if front_right_wheel:
		front_right_wheel.wheel_friction_slip = front_friction
	if rear_left_wheel:
		rear_left_wheel.wheel_friction_slip = normal_rear_friction
	if rear_right_wheel:
		rear_right_wheel.wheel_friction_slip = normal_rear_friction

func _physics_process(delta: float) -> void:
	# Input reading
	var accel = Input.get_action_strength("accelerate")
	var rev = Input.get_action_strength("reverse")
	var steering_dir = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var drift_action = Input.is_action_pressed("drift")
	
	# Car local vectors:
	# In this model: local -X is forward, local +Z is left, local +Y is up
	var car_forward = -global_transform.basis.x.normalized()
	var car_up = global_transform.basis.y.normalized()
	var h_vel = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var forward_speed = car_forward.dot(h_vel)
	var speed_kmh = h_vel.length() * 3.6
	
	# Lateral slip angle calculation
	var cross_y = 0.0
	var slip_angle_deg = 0.0
	if h_vel.length() > 1.0:
		cross_y = car_forward.cross(h_vel.normalized()).y
		slip_angle_deg = rad_to_deg(asin(clamp(cross_y, -1.0, 1.0)))
	
	# Drift determination (drift button or high-speed power slide)
	var want_drift = drift_action and (speed_kmh > min_drift_speed_kmh)
	var is_power_sliding = abs(slip_angle_deg) > 12.0 and accel > 0.0 and speed_kmh > 20.0
	is_drifting = want_drift or is_power_sliding
	
	# Smooth, progressive wheel friction transition (no sudden drop/snap)
	var target_rear_fric = drift_rear_friction if is_drifting else normal_rear_friction
	if rear_left_wheel:
		rear_left_wheel.wheel_friction_slip = lerp(rear_left_wheel.wheel_friction_slip, target_rear_fric, friction_transition_speed * delta)
	if rear_right_wheel:
		rear_right_wheel.wheel_friction_slip = lerp(rear_right_wheel.wheel_friction_slip, target_rear_fric, friction_transition_speed * delta)
	if front_left_wheel:
		front_left_wheel.wheel_friction_slip = front_friction
	if front_right_wheel:
		front_right_wheel.wheel_friction_slip = front_friction
	
	# Adaptive steering:
	# Only allow wider angle when counter-steering into the slide;
	# when turning normally into the corner, keep angle bounded to prevent sudden sharp turns
	var is_counter_steering = is_drifting and ((steering_dir * cross_y) < 0.0)
	var max_steer = counter_steer_amount if is_counter_steering else turn_amount
	current_steering = lerp(current_steering, steering_dir * max_steer, turn_speed * delta)
	steering = current_steering
	
	# Soft yaw rate damper: prevents the car from snapping or spinning out violently
	if is_drifting:
		# Counter-steer stabilization: stabilizes car when catching a slide
		if is_counter_steering:
			var stab = -angular_velocity.y * counter_steer_assist * delta
			apply_torque(car_up * stab)
		
		# Softly clamp excess angular rotation to keep the slide smooth and steady
		if abs(angular_velocity.y) > max_yaw_rate:
			var excess = angular_velocity.y - sign(angular_velocity.y) * max_yaw_rate
			apply_torque(car_up * (-excess * 2000.0 * delta))
	
	# Engine & Brake control
	if accel > 0.0:
		brake = 0.0
		var speed_factor = clamp(1.0 - (speed_kmh / max_speed_kmh), 0.0, 1.0)
		var boost = drift_engine_boost if is_drifting else 1.0
		engine_force = accel * torque * speed_factor * boost
	elif rev > 0.0:
		if forward_speed > 2.0:
			# Foot brake when moving forward and pressing reverse
			engine_force = 0.0
			brake = rev * brake_force
		else:
			# Reverse gear
			brake = 0.0
			engine_force = -rev * reverse_force
	else:
		# Rolling / coasting resistance
		engine_force = 0.0
		brake = coast_brake

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var spring_arm = get_node_or_null("%SpringArm3D")
		if spring_arm:
			spring_arm.rotation_degrees.x -= event.relative.y * mouse_sensitivity
			spring_arm.rotation_degrees.x = clamp(spring_arm.rotation_degrees.x, -90.0, -15.0)
			
			spring_arm.rotation_degrees.y -= event.relative.x * mouse_sensitivity
			spring_arm.rotation_degrees.y = wrapf(spring_arm.rotation_degrees.y, 0.0, 360.0)
