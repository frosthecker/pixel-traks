extends Area2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
#	pass


var items_in_range = {}

func _on_body_entered(body: Node2D) -> void:
	items_in_range[body] = body
	
func _on_body_exited(body: Node2D) -> void:
	if items_in_range.has(body):
		items_in_range.erase(body)
