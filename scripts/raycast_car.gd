class_name vehicle extends VehicleBody3D

@export var torque: int = 3000
@export var max_RPM: int = 600
@export var turn_speed: float = 3.0
@export var turn_amount: float = 0.4

func _physics_process(delta: float) -> void:
	var dir = Input.get_action_strength("accelerate") - Input.get_action_strength("reverse")
	var steering_dir = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right") 
	
	engine_force = 0
	steering - 0
