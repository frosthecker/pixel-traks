extends Node2D

const SlotClass = preload("res://scripts/slot.gd")
@onready var inventory_slots = $GridContainer
var holding_item = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	var slots = inventory_slots.get_children()
	for i in range(slots.size()):
		slots[i].connect("gui_input", slot_gui_input.bind(slots[i]))
		slots[i].slot_index = i
	initialize_inventory()
	
func initialize_inventory():
	var slots = inventory_slots.get_children()
	for i in range(slots.size()):
		if PlayerInventory.inventory.has(i):
			var inventory_item = PlayerInventory.inventory[i]
			slots[i].initialize_item(inventory_item[0], inventory_item[1])

func slot_gui_input(event: InputEvent, slot: SlotClass):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT && event.pressed:
			if holding_item != null:
				if !slot.item:
					left_click_empty_slot(slot)
				else:
					#different item, so swap
					if holding_item.item_name != slot.item.item_name:
						left_click_different_item(event, slot)
					#same item, so try to merge
					else:
						left_click_same_item(slot)
			#not holding item
			elif slot.item:
				left_click_not_holding(slot)
				
func _input(event: InputEvent) -> void:
	if holding_item:
		holding_item.global_position = get_global_mouse_position()

func left_click_empty_slot(slot: SlotClass):
	PlayerInventory.add_item_to_empty_slot(holding_item, slot)
	slot.putIntoSlot(holding_item)
	holding_item = null	

func left_click_different_item(event: InputEvent, slot: SlotClass):
	PlayerInventory.remove_item(slot)
	PlayerInventory.add_item_to_empty_slot(holding_item, slot)
	var temp_item = slot.item
	slot.pickFromSlot()
	temp_item.global_position = event.global_position
	slot.putIntoSlot(holding_item)
	holding_item = temp_item

func left_click_same_item(slot: SlotClass):
	var stack_size = int(JsonData.item_data[slot.item.item_name]["stack_size"])
	var able_to_add = stack_size - slot.item.item_quantity
	if able_to_add >= holding_item.item_quantity:
		PlayerInventory.add_item_quantity(slot, holding_item.item_quantity)
		slot.item.add_item_quantity(holding_item.item_quantity)
		holding_item.queue_free()
		holding_item = null
	else:
		PlayerInventory.add_item_quantity(slot, able_to_add)
		slot.item.add_item_quantity(able_to_add)
		holding_item.decrease_item_quantity(able_to_add)

func left_click_not_holding(slot: SlotClass):
	PlayerInventory.remove_item(slot)
	holding_item = slot.item
	slot.pickFromSlot()
	holding_item.global_position = get_global_mouse_position()


func popup_open():
	$AnimationPlayer.play("popup_open")

func popup_close():
	$AnimationPlayer.play("popup_close")
	
