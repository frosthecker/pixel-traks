extends StaticBody2D

var player = null
var being_picked_up  = false

func _physics_process(delta: float) -> void:
	if being_picked_up and is_instance_valid(player):
		# Move smoothly toward the player
		global_position = global_position.move_toward(player.global_position, 300 * delta)
		
		var distance = global_position.distance_to(player.global_position)
		if distance < 10:
			queue_free()
			
#func _on_body_entered(body: Node2D) -> void:
#	if body.name == "Player" or body.is_in_group("Player"):
#		queue_free()
		
func pick_up_item(body):
	player = body
	being_picked_up = true
