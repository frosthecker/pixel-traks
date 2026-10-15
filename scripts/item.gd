extends Node2D

var item_name
var item_quantity

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var rand_val = randi() % 3
	if rand_val == 0:
		item_name = 'sword'
	elif rand_val == 1:
		item_name = 'shovel'
	else:
		item_name = 'axe'
	
	$item_tex.texture = load("res://assets/Sunnyside_World_Assets/UI/" + item_name + ".png")
	var stack_size = int(JsonData.item_data[item_name]["stack_size"])
	item_quantity = randi() % stack_size + 1
	
	if stack_size == 1:
		$Label.text = "..."
	else:
		$Label.text = str(item_quantity)

func set_item(nm, qt):
	item_name = nm
	item_quantity = qt
	$item_tex.texture = load("res://assets/Sunnyside_World_Assets/UI/" + item_name + ".png")
	
	var stack_size = int(JsonData.item_data[item_name]["stack_size"])
	if stack_size == 1:
		$Label.text = "..."
	else:
		$Label.text = str(item_quantity)

func add_item_quantity(amount_to_add):
	item_quantity += amount_to_add
	$Label.text = str(item_quantity)
	
func decrease_item_quantity(amount_to_remove):
	item_quantity -= amount_to_remove
	$Label.text = str(item_quantity)
	
