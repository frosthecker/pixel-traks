extends StaticBody2D

const SALE_TIMELINE := "res://AI/timelines/seller_sale.dtl"
const NO_CROPS_TIMELINE := "res://AI/timelines/seller_no_crops.dtl"

var player_in_range := false
var dialogue_running := false
var dialogic: Node
var upgrade_menu: PopupMenu

@onready var prompt: Label = $Prompt

func _ready() -> void:
	prompt.visible = false
	dialogic = get_node_or_null("/root/Dialogic")
	if dialogic and not dialogic.is_connected("timeline_ended", Callable(self, "_on_dialogue_ended")):
		dialogic.connect("timeline_ended", Callable(self, "_on_dialogue_ended"))
	_setup_upgrade_menu()

func _setup_upgrade_menu() -> void:
	upgrade_menu = PopupMenu.new()
	upgrade_menu.name = "UpgradeMenu"
	add_child(upgrade_menu)
	upgrade_menu.id_pressed.connect(_on_upgrade_selected)

func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range or dialogue_running:
		return
	if event.is_action_pressed("interact"):
		interact()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_U:
		_open_upgrade_menu()
		get_viewport().set_input_as_handled()

func interact(_interactor: Node2D = null) -> void:
	if player_in_range and not dialogue_running:
		_sell_crops()

func _open_upgrade_menu() -> void:
	upgrade_menu.clear()
	for tool in [Enum.Tool.HOE, Enum.Tool.WATER, Enum.Tool.AXE]:
		var tool_name: String = str(Data.TOOL_DISPLAY_NAMES.get(tool, "Tool"))
		var next := FarmState.get_next_tool_upgrade(tool)
		var item_id := int(tool) + 1
		if next.is_empty():
			upgrade_menu.add_item("%s — MAX" % tool_name, item_id)
			upgrade_menu.set_item_disabled(upgrade_menu.get_item_count() - 1, true)
		else:
			var cost := int(next.get("cost", 0))
			upgrade_menu.add_item("%s → %s (%d TC)" % [tool_name, str(next.get("name", "Upgrade")), cost], item_id)
			if PlayerInventory.money < cost:
				upgrade_menu.set_item_disabled(upgrade_menu.get_item_count() - 1, true)
	upgrade_menu.position = Vector2i(get_viewport().get_mouse_position())
	upgrade_menu.popup()

func _on_upgrade_selected(id: int) -> void:
	var tool := id - 1
	var next := FarmState.get_next_tool_upgrade(tool)
	if next.is_empty():
		return
	var upgrade_name := str(next.get("name", "Upgrade"))
	if FarmState.purchase_tool_upgrade(tool):
		FarmHud.notice("%s equipped!" % upgrade_name, Color(0.65, 1.0, 0.65))
	else:
		FarmHud.notice("Not enough TC for %s." % upgrade_name, Color(1.0, 0.55, 0.45))

func _sell_crops() -> void:
	var earnings := PlayerInventory.sell_all_crops()
	if dialogic == null:
		push_error("Dialogic is unavailable; seller dialogue could not start.")
		return

	dialogue_running = true
	if earnings > 0:
		var variable_system: Object = dialogic.get("VAR")
		if variable_system != null:
			variable_system.call("set_variable", "seller_sale_earnings", earnings)
		dialogic.call("start", SALE_TIMELINE)
	else:
		dialogic.call("start", NO_CROPS_TIMELINE)

func _on_dialogue_ended() -> void:
	dialogue_running = false

func _on_sell_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true
		prompt.text = "R: sell crops  •  U: tool upgrades"
		prompt.visible = true

func _on_sell_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
		prompt.visible = false
