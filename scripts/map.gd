extends Node2D

const PAGE_NAMES := ["Player Status", "Inventory", "World", "Save & Load", "Settings"]
const PAGE_PATHS := [
	NodePath("pages/profile"),
	NodePath("pages/inventory"),
	NodePath("pages/worldmap"),
	NodePath("pages/save"),
	NodePath("pages/settings")
]

@onready var light_flicker: AnimatedSprite2D = $"light flicker"
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var header_label: Label = $header/HBoxContainer/Label
@onready var tabs: Node2D = $tabs
@onready var compass: Sprite2D = $compass/Sprite2D
@onready var background: ColorRect = $ColorRect
@onready var page_flip_anim: AnimatedSprite2D = $page_flip/AnimatedSprite2D
@onready var hour_tens: AnimatedSprite2D = $clock/hours/d2
@onready var hour_ones: AnimatedSprite2D = $clock/hours/d1
@onready var minute_tens: AnimatedSprite2D = $clock/mins/d2
@onready var minute_ones: AnimatedSprite2D = $clock/mins/d1
@onready var tc_label: Label = $pages/profile/profile/game_data/currency/coinContainer/Label

var current_page := 0
var is_open := false
var compass_tween: Tween
var player_can_move_before_open := true
var player_physics_processing_before_open := true
var player: Node
var background_tween: Tween
var displayed_clock_digits: Dictionary[AnimatedSprite2D, int] = {}


func _ready() -> void:
	visible = false
	background.color.a = 0.0
	add_to_group("MapMenu") # <-- ADD THIS LINE HERE
	
	player = get_tree().current_scene.get_node_or_null("Objects/Player")
	WorldTime.time_changed.connect(_on_world_time_changed)
	PlayerInventory.money_changed.connect(_on_money_changed)
	_update_clock(WorldTime.get_current_minutes())
	_on_money_changed(PlayerInventory.money)
	_show_page(0)



func _process(_delta: float) -> void:
	# 1. Check if our virtual UI button was pressed
	if player and player.get("inventory_but_pressed"):
		_toggle_map_menu(player)
		
	# Keep compass pointing in sync with player orientation
	if is_open and (compass_tween == null or not compass_tween.is_valid()):
		compass.rotation = _player_facing_angle()


func _input(event: InputEvent) -> void:
	# 2. Safely filter out anything that isn't a fresh keyboard key press
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# 3. Check for keyboard menu toggles
	if event.is_action_pressed("inventory"):
		if player:
			_toggle_map_menu(player)
		return
	elif event.is_action_pressed("ui_cancel") or event.keycode == KEY_ESCAPE:
		if is_open:
			close()
			get_viewport().set_input_as_handled()
		return

	# 4. Handle page controls ONLY if the map menu is actively open
	if is_open:
		if event.keycode == KEY_UP:
			page_flip_anim.play("next")
			await page_flip_anim.animation_finished
			_show_page(posmod(current_page - 1, PAGE_NAMES.size()))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			page_flip_anim.play("previous")
			await page_flip_anim.animation_finished
			_show_page(posmod(current_page + 1, PAGE_NAMES.size()))
			get_viewport().set_input_as_handled()


func _toggle_map_menu(player_node: Node) -> void:
	player_node.inventory_but_pressed = false
	if is_open:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func open():
	if is_open:
		return
	is_open = true
	visible = true
	if player == null:
		player = get_tree().current_scene.get_node_or_null("Objects/Player")
		
	_show_page(current_page)
	
	var tab_animation := animation_player.get_animation("tab_close")
	animation_player.seek(tab_animation.length, true)
	animation_player.play_backwards("tab_close")
	await animation_player.animation_finished
	_play_compass_calibration()


func close():
	if not is_open:
		return
	is_open = false
	if player != null and player.get("can_move") != null:
		player.can_move = player_can_move_before_open
		player.set_physics_process(player_physics_processing_before_open)
		
	animation_player.seek(0.0, true)
	animation_player.play("tab_close")
	await animation_player.animation_finished
	if not is_open:
		visible = false


func _show_page(page_index: int) -> void:
	current_page = posmod(page_index, PAGE_NAMES.size())
	header_label.text = PAGE_NAMES[current_page]
	for index in PAGE_PATHS.size():
		var page := get_node(PAGE_PATHS[index]) as CanvasItem
		var page_is_active := index == current_page
		page.visible = page_is_active
		for content in page.get_children():
			if content is CanvasItem:
				(content as CanvasItem).visible = page_is_active
		var tab := tabs.get_node("tab%d" % (index + 1)) as AnimatedSprite2D
		tab.frame = 1 if index == current_page else 0

	if current_page == 1:
		get_node("pages/inventory/inventory").initialize_inventory()
	elif current_page == 2:
		_refresh_world_page()


func _refresh_world_page() -> void:
	var traders: Array[String] = []
	for npc in get_tree().get_nodes_in_group("NPC"):
		var activity := str(npc.get("behavior_state") if npc.get("behavior_state") != null else "nearby")
		traders.append("%s — %s" % [npc.name, activity.capitalize()])
	var trader_summary := get_node_or_null("pages/worldmap/WorldSections/TradersScroll/TraderList/TraderSummary") as Label
	if trader_summary != null:
		trader_summary.text = "No traders nearby" if traders.is_empty() else "\n".join(traders.slice(0, 3))

	var world_summary := get_node_or_null("pages/worldmap/WorldSections/WorldScroll/WorldList/WorldSummary") as Label
	if world_summary == null:
		return
	var level := get_tree().current_scene
	var map_size := "Unknown"
	if level != null and level.get("width") != null and level.get("height") != null:
		map_size = "%d × %d" % [int(level.get("width")), int(level.get("height"))]
	world_summary.text = "Day %d  •  %s\nWorld size: %s" % [WorldTime.day_count, WorldTime.format_time(), map_size]


func _play_compass_calibration() -> void:
	if compass_tween != null and compass_tween.is_valid():
		compass_tween.kill()
	compass.rotation = -TAU
	compass_tween = create_tween()
	compass_tween.set_trans(Tween.TRANS_QUINT)
	compass_tween.set_ease(Tween.EASE_OUT)
	compass_tween.tween_property(compass, "rotation", TAU + _player_facing_angle(), 0.8)


func _player_facing_angle() -> float:
	if player == null:
		return 0.0
	var facing := player.get("last_direction") as Vector2
	if facing == Vector2.ZERO:
		return 0.0
	return facing.angle() + PI / 2.0


func _tween_background(target_alpha: float) -> void:
	if background_tween != null and background_tween.is_valid():
		background_tween.kill()
	background_tween = create_tween()
	background_tween.tween_property(background, "color:a", target_alpha, 1.2)


func _on_world_time_changed(minutes: int) -> void:
	_update_clock(minutes)


func _update_clock(total_minutes: int) -> void:
	var hours := clampi(total_minutes / 60, 0, 23)
	var minutes := clampi(total_minutes % 60, 0, 59)
	_set_clock_digit(hour_tens, hours / 10)
	_set_clock_digit(hour_ones, hours % 10)
	_set_clock_digit(minute_tens, minutes / 10)
	_set_clock_digit(minute_ones, minutes % 10)


func _set_clock_digit(digit_sprite: AnimatedSprite2D, digit: int) -> void:
	if displayed_clock_digits.get(digit_sprite, -1) == digit:
		return
	displayed_clock_digits[digit_sprite] = digit

	var transition_animation := StringName(str(posmod(digit - 1, 10)))
	digit_sprite.stop()
	digit_sprite.animation = transition_animation
	digit_sprite.set_frame_and_progress(0, 0.0)
	digit_sprite.play(transition_animation)


func _on_money_changed(amount: int) -> void:
	tc_label.text = "%d TC" % amount


func _on_cross_pressed() -> void:
	close()


func _on_up_pressed() -> void:
	page_flip_anim.play("next")
	await page_flip_anim.animation_finished
	_show_page(posmod(current_page - 1, PAGE_NAMES.size()))
	get_viewport().set_input_as_handled()


func _on_down_pressed() -> void:
	page_flip_anim.play("previous")
	await page_flip_anim.animation_finished
	_show_page(posmod(current_page + 1, PAGE_NAMES.size()))
	get_viewport().set_input_as_handled()
