extends Node

const SlotClass = preload("res://scripts/slot.gd")
const NUM_INVENTORY_SLOTS = 14
const ItemClass = preload("res://scripts/item.gd")
var inventory = {
	#0: ['sword', 1], # slot_index: [item name, item quantity]
	#1: ['sword', 1] # slot_index: [item name, item quantity]
}

var hotbar = {
	#0: ['sword', 1], # slot_index: [item name, item quantity]
	#1: ['sword', 1] # slot_index: [item name, item quantity]
}

var money := 0

func get_save_data() -> Dictionary:
	return {
		"inventory": _serialize_slots(inventory),
		"hotbar": _serialize_slots(hotbar),
		"money": money
	}

func load_save_data(save_data: Dictionary) -> void:
	inventory = _deserialize_slots(save_data.get("inventory", {}))
	hotbar = _deserialize_slots(save_data.get("hotbar", {}))
	money = max(0, int(save_data.get("money", 0)))
	_refresh_inventory_ui()

func _serialize_slots(slots: Dictionary) -> Dictionary:
	var serialized := {}
	for slot_index in slots:
		var item: Variant = slots[slot_index]
		if item is Array and item.size() >= 2:
			serialized[str(slot_index)] = [str(item[0]), int(item[1])]
	return serialized

func _deserialize_slots(serialized: Variant) -> Dictionary:
	var slots := {}
	if not (serialized is Dictionary):
		return slots
	for raw_index in serialized:
		var item: Variant = serialized[raw_index]
		if item is Array and item.size() >= 2:
			slots[int(raw_index)] = [str(item[0]), int(item[1])]
	return slots

func _refresh_inventory_ui() -> void:
	var inventory_ui := get_tree().current_scene.get_node_or_null("Overlay/UserInterface/inventory")
	if inventory_ui == null:
		return
	for slot in inventory_ui.inventory_slots.get_children():
		if slot.item != null:
			slot.item.queue_free()
			slot.item = null
			slot.refresh_style()
	inventory_ui.initialize_inventory()

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

func sell_all_crops() -> int:
	var earnings := 0
	for slot_index in inventory.keys():
		var item: Variant = inventory[slot_index]
		if not (item is Array and item.size() >= 2):
			continue

		var item_name := str(item[0])
		var item_data: Variant = JsonData.item_data.get(item_name, {})
		if not (item_data is Dictionary) or item_data.get("item_category") != "Plant":
			continue

		var sell_price := int(item_data.get("sell_price", 0))
		if sell_price <= 0:
			continue
		earnings += int(item[1]) * sell_price
		inventory.erase(slot_index)

	if earnings > 0:
		money += earnings
		_refresh_inventory_ui()
	return earnings
