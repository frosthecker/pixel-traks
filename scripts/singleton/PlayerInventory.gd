extends Node

const SlotClass = preload("res://scripts/slot.gd")
const NUM_INVENTORY_SLOTS = 14
const ItemClass = preload("res://scripts/item.gd")
var inventory = {
	0: ['sword', 1], # slot_index: [item name, item quantity]
	1: ['sword', 1] # slot_index: [item name, item quantity]
}

func add_item(item_name, item_quantity):
	for item in inventory:
		if inventory[item][0] == item_name:
			var stack_size = int(JsonData.item_data[item_name]["stack_size"])
			var able_to_add = stack_size - inventory[item][1]
			if able_to_add >= item_quantity:
				inventory[item][1] += item_quantity
				update_slot_visual(item, inventory[item][0], inventory[item][1])
				return
			else:
				inventory[item][1] += able_to_add
				update_slot_visual(item, inventory[item][0], inventory[item][1])
				item_quantity = item_quantity-able_to_add
	
	for i in range(NUM_INVENTORY_SLOTS):
		if inventory.has(i) == false:
			inventory[i] = [item_name, item_quantity]
			update_slot_visual(i, inventory[i][0], inventory[i][1])
			return

func update_slot_visual(slot_index, item_name, new_quantity):
	# The inventory UI may not have entered the scene tree yet (for example,
	# when an item is picked up during level startup).  Keep the inventory data
	# as the source of truth; inventory.gd will render it from _ready().
	var slot_path = "Overlay/UserInterface/inventory/GridContainer/Slot" + str(slot_index + 1)
	var slot = get_tree().current_scene.get_node_or_null(slot_path)
	if slot == null:
		return

	if slot.item != null:
		slot.item.set_item(item_name, new_quantity)
	else:
		slot.initialize_item(item_name, new_quantity)
func remove_item(slot: SlotClass):
	inventory.erase(slot.slot_index)

func add_item_to_empty_slot(item: ItemClass, slot: SlotClass):
	inventory[slot.slot_index] = [item.item_name, item.item_quantity]
	
func add_item_quantity(slot: SlotClass, quantity_to_add: int):
	inventory[slot.slot_index][1] += quantity_to_add
