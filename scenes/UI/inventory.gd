extends Node2D

const SlotClass = preload("res://scripts/slot.gd")
@onready var inventory_slots = $GridContainer
var holding_item = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	
	for inv_slot in inventory_slots.get_children():
		inv_slot.connect("gui_input", slot_gui_input.bind(inv_slot))


func slot_gui_input(event: InputEvent, slot: SlotClass):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT && event.pressed:
			if holding_item != null:
				if !slot.item:
					slot.putIntoSlot(holding_item)
					holding_item = null
				else:
					var temp_item = slot.item
					slot.pickFromSlot()
					temp_item.global_position = event.global_position
					slot.putIntoSlot(holding_item)
					holding_item = temp_item
			elif slot.item:
				holding_item = slot.item
				slot.pickFromSlot()
				holding_item.global_position = get_global_mouse_position()
				
func _input(event: InputEvent) -> void:
	if holding_item:
		holding_item.global_position = get_global_mouse_position()

func popup_open():
	$AnimationPlayer.play("popup_open")

func popup_close():
	$AnimationPlayer.play("popup_close")
	
