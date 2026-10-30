extends StaticBody2D

const SALE_TIMELINE := "res://AI/timelines/seller_sale.dtl"
const NO_CROPS_TIMELINE := "res://AI/timelines/seller_no_crops.dtl"

var player_in_range := false
var dialogue_running := false
var dialogic: Node

@onready var prompt: Label = $Prompt

func _ready() -> void:
	prompt.visible = false
	dialogic = get_node_or_null("/root/Dialogic")
	if dialogic and not dialogic.is_connected("timeline_ended", Callable(self, "_on_dialogue_ended")):
		dialogic.connect("timeline_ended", Callable(self, "_on_dialogue_ended"))

func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and not dialogue_running and event.is_action_pressed("interact"):
		_sell_crops()
		get_viewport().set_input_as_handled()

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
		prompt.text = "Press R to sell crops"
		prompt.visible = true

func _on_sell_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
		prompt.visible = false
