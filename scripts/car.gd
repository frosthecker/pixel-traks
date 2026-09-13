class_name Vehicle extends VehicleBody3D

@export var torque: int = 3000
@export var max_RPM: int = 600
@export var turn_speed: float = 3.0
@export var turn_amount: float = 0.4
@export var wheel_trac_l: VehicleWheel3D
@export var wheel_trac_r: VehicleWheel3D
@export_group("camera")
@export var mouse_sensitivity: float = 0.1


func _ready() -> void:
	#captures mouse movement real time
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	
	#Calculation of strength of x and y axis directions
	var dir = Input.get_action_strength("accelerate") - Input.get_action_strength("reverse")
	var steering_dir = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right") 
	
	#left and right wheel RPM calculation
	var RPM_l = wheel_trac_l.get_rpm()
	var RPM_r = wheel_trac_r.get_rpm()
	var avg_RPM = (RPM_l + RPM_r)/2
	
	#forward/acceleration force calculation
	engine_force = dir * torque * (1.0 - avg_RPM/max_RPM)
	
	#steering force calculation
	steering = lerp(steering, steering_dir*turn_amount, turn_speed*delta)
	
	#automatic brake system - friction of car with ground if null forward direction
	if dir == 0:
		brake = 3

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		%SpringArm3D.rotation_degrees.x -= event.relative.y + mouse_sensitivity
		%SpringArm3D.rotation_degrees.x = clamp(%SpringArm3D.rotation_degrees.x, -90.0, -15.0)
		
		%SpringArm3D.rotation_degrees.y -= event.relative.x + mouse_sensitivity
		%SpringArm3D.rotation_degrees.y = clamp(%SpringArm3D.rotation_degrees.y, 0, 360.0)
