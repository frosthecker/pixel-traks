extends Node2D

@onready var hotbar = $HotbarSlots
@onready var slots = hotbar.get_children()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#visible = false
#	var slots = inventory_slots.get_children()
	for i in range(slots.size()):
#		slots[i].connect("gui_input", slot_gui_input.bind(slots[i]))
		slots[i].slot_index = i
	initialize_hotbar()
	
func initialize_hotbar():
#	var slots = inventory_slots.get_children()
	for i in range(slots.size()):
		if PlayerInventory.hotbar.has(i):
			var hotbar_item = PlayerInventory.hotbar[i]
			slots[i].initialize_item(hotbar_item[0], hotbar_item[1])
