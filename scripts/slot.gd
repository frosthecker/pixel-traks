extends Panel

var ItemClass = preload("res://scenes/UI/item.tscn")
var item = null 

var empty_tex = preload("res://assets/Pocket Inventory Series #2 Pixel Map v1.2/Sprites/Content/Holders/3.png")
var default_tex = preload("res://assets/Pocket Inventory Series #2 Pixel Map v1.2/Sprites/Content/Holders/4.png")

var default_style: StyleBoxTexture = null
var empty_style: StyleBoxTexture = null
var slot_index


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	default_style = StyleBoxTexture.new()
	empty_style = StyleBoxTexture.new()
	default_style.texture = default_tex
	empty_style.texture = empty_tex
	#if randi() % 2 == 0:
	#	item = ItemClass.instantiate()
	#	add_child(item)
	refresh_style()
	
func refresh_style():
	if item == null:
		set('theme_override_styles/panel', empty_style)	
	else:
		set('theme_override_styles/panel', default_style)

func pickFromSlot():
	remove_child(item)
	var InventoryNode = find_parent("inventory")
	InventoryNode.add_child(item)
	item = null
	refresh_style()

func putIntoSlot(new_item):
	item = new_item
	item.position = Vector2(0,0)
	var InventoryNode = find_parent("inventory")
	InventoryNode.remove_child(item)
	add_child(item)
	refresh_style() 

func initialize_item(item_name, item_quantity):
	if item == null:
		item = ItemClass.instantiate()
		add_child(item)
		item.set_item(item_name, item_quantity)
	else:
		item.set_item(item_name, item_quantity)
	refresh_style()
