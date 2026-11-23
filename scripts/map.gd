extends Node2D

const PAGE_NAMES := ["Player Status", "Inventory", "World", "Save & Load", "Settings"]
const PAGE_PATHS := [
	NodePath("pages/profile"),
	NodePath("pages/inventory"),
	NodePath("pages/worldmap"),
	NodePath("pages/save"),
	NodePath("pages/settings")
]
const FLOAT_TEXT_LIFETIME := 0.9

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

# Profile page UI references
@onready var profile_page: Node = $pages/profile/profile
@onready var health_bar: TextureProgressBar = $pages/profile/profile/status/health/healthbar
@onready var health_label: Label = $pages/profile/profile/status/health/health_percent/Label
@onready var heart_icon: Sprite2D = $pages/profile/profile/status/health/heart_icon
@onready var hunger_bar: TextureProgressBar = $pages/profile/profile/status/hunger/hungerbar
@onready var hunger_label: Label = $pages/profile/profile/status/hunger/hunger_percent/Label
@onready var level_label: Label = $pages/profile/profile/game_data/level_xp/level/Label
@onready var xp_bar: TextureProgressBar = $pages/profile/profile/game_data/level_xp/xpbar
@onready var xp_icon: AnimatedSprite2D = $pages/profile/profile/game_data/level_xp/xp_icon

var current_page := 0
var is_open := false
var compass_tween: Tween
var player_can_move_before_open := true
var player_physics_processing_before_open := true
var player: Node
var background_tween: Tween
var displayed_clock_digits: Dictionary[AnimatedSprite2D, int] = {}

# Cached progress values so VFX know what changed.
var _level: Node
var _last_health: int = -1
var _last_max_health: int = -1
var _last_farming_level: int = -1
var _last_farming_xp: int = -1
var _health_value_tween: Tween
var _xp_value_tween: Tween


func _ready() -> void:
	visible = false
	background.color.a = 0.0
	add_to_group("MapMenu")
	player = _find_player()

	WorldTime.time_changed.connect(_on_world_time_changed)
	PlayerInventory.money_changed.connect(_on_money_changed)
	FarmState.farming_level_changed.connect(_on_farming_level_changed)
	FarmState.farming_xp_changed.connect(_on_farming_xp_changed)

	# During boot the map's _ready runs before the level is registered as the
	# current scene, so resolve the level one frame later instead of caching null.
	_bind_level.call_deferred()

	_refresh_profile(false)
	_update_clock(WorldTime.get_current_minutes())
	_on_money_changed(PlayerInventory.money)
	_show_page(0)
	set_process(false)


func _process(_delta: float) -> void:
	if compass_tween == null or not compass_tween.is_valid():
		compass.rotation = _player_facing_angle()


func _find_player() -> Node:
	var grouped := get_tree().get_first_node_in_group("Player")
	if grouped != null:
		return grouped
	var scene := get_tree().current_scene
	if scene != null:
		return scene.get_node_or_null("Objects/Player")
	return null


func _bind_level() -> void:
	if _level != null and is_instance_valid(_level):
		return

	var candidate: Node = null
	var levels := get_tree().get_nodes_in_group("Level")
	if not levels.is_empty():
		candidate = levels[0]
	else:
		var scene := get_tree().current_scene
		if scene != null and scene.has_signal("health_changed"):
			candidate = scene

	if candidate == null or not candidate.has_signal("health_changed"):
		return

	_level = candidate
	if not _level.health_changed.is_connected(_on_health_changed):
		_level.health_changed.connect(_on_health_changed)
	_refresh_profile(false)


func _refresh_profile(animate: bool) -> void:
	if _level != null and is_instance_valid(_level) and _level.has_signal("health_changed"):
		var current: Variant = _level.get("player_health")
		var maximum: Variant = _level.get("player_max_health")
		if current != null and maximum != null:
			_on_health_changed(int(current), int(maximum), animate)

	_on_farming_level_changed(FarmState.farming_level, FarmState.farming_xp, FarmState.xp_to_next_level(), animate)
	_on_farming_xp_changed(FarmState.farming_xp, FarmState.xp_to_next_level(), false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.is_action_pressed("inventory"):
		_toggle_map_menu(player)
		return
	elif event.is_action_pressed("ui_cancel") or event.keycode == KEY_ESCAPE:
		if is_open:
			close()
			get_viewport().set_input_as_handled()
		return

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


func _toggle_map_menu(_player_node: Node) -> void:
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
	set_process(true)
	if player == null:
		player = _find_player()
	_bind_level()
	_refresh_profile(false)

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
	set_process(false)
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

	if current_page == 0:
		_bind_level()
		_refresh_profile(false)
	elif current_page == 1:
		get_node("pages/inventory/inventory").initialize_inventory()
	elif current_page == 2:
		_refresh_world_page()


func _on_health_changed(current: int, maximum: int, animate := true) -> void:
	var previous := _last_health
	_last_health = current
	_last_max_health = maximum

	if health_bar != null:
		health_bar.max_value = maximum
		if animate and previous >= 0 and current != previous:
			_play_health_vfx(previous, current)
		else:
			health_bar.value = current

	if health_label != null:
		health_label.text = "%d/%d" % [current, maximum]


func _play_health_vfx(previous: int, current: int) -> void:
	var is_damage := current < previous

	if health_bar != null:
		if _health_value_tween != null and _health_value_tween.is_valid():
			_health_value_tween.kill()
		health_bar.value = previous
		_health_value_tween = create_tween()
		_health_value_tween.set_trans(Tween.TRANS_QUAD)
		_health_value_tween.set_ease(Tween.EASE_OUT)
		_health_value_tween.tween_property(health_bar, "value", current, 0.45)

		_flash_canvas_item(health_bar, Color(1.0, 0.32, 0.38) if is_damage else Color(0.45, 1.0, 0.55))
		_pop_scale(health_bar, 1.08, 0.4)

		if is_damage:
			_shake(health_bar, 3.0, 0.25)

	if heart_icon != null:
		_pop_scale(heart_icon, 1.4, 0.4)

	if health_label != null:
		_flash_canvas_item(health_label, Color(1.0, 0.7, 0.7) if is_damage else Color(0.7, 1.0, 0.8))

	var difference := current - previous
	if difference != 0 and health_bar != null:
		var color := Color(1.0, 0.45, 0.45) if difference < 0 else Color(0.5, 1.0, 0.6)
		_spawn_floating_text(health_bar.get_parent(), Vector2(152, 30), "%+d HP" % difference, color)


func _on_farming_level_changed(level: int, xp: int, xp_to_next: int, animate := true) -> void:
	var leveled_up := animate and _last_farming_level >= 0 and level > _last_farming_level
	_last_farming_level = level
	_last_farming_xp = xp

	if level_label != null:
		level_label.text = "Lv. %d" % level

	_update_xp_display(xp, xp_to_next, false)

	if leveled_up:
		_play_level_vfx()
		var xp_parent: Node = xp_icon.get_parent() if xp_icon != null else null
		_spawn_floating_text(xp_parent, Vector2(60, 96), "LEVEL UP!", Color(1.0, 0.9, 0.35))


func _on_farming_xp_changed(xp: int, xp_to_next: int, animate := true) -> void:
	var previous := _last_farming_xp
	var gained := animate and previous >= 0 and xp > previous
	_last_farming_xp = xp

	_update_xp_display(xp, xp_to_next, gained)

	if gained:
		_play_xp_vfx()
		var xp_parent: Node = xp_bar.get_parent() if xp_bar != null else null
		_spawn_floating_text(xp_parent, Vector2(60, 120), "+%d XP" % (xp - previous), Color(0.6, 1.0, 0.7))


func _update_xp_display(xp: int, xp_to_next: int, animate: bool) -> void:
	var maximum := maxi(1, xp_to_next)

	if xp_bar != null:
		xp_bar.max_value = maximum
		if animate:
			if _xp_value_tween != null and _xp_value_tween.is_valid():
				_xp_value_tween.kill()
			var start := clampf(float(xp_bar.value), 0.0, float(maximum))
			xp_bar.value = start
			_xp_value_tween = create_tween()
			_xp_value_tween.set_trans(Tween.TRANS_QUAD)
			_xp_value_tween.set_ease(Tween.EASE_OUT)
			_xp_value_tween.tween_property(xp_bar, "value", float(xp), 0.5)
		else:
			xp_bar.value = xp

	if xp_icon != null and xp_to_next > 0:
		var progress := clampf(float(xp) / float(xp_to_next), 0.0, 1.0)
		xp_icon.speed_scale = 0.75 + progress * 1.75


func _play_xp_vfx() -> void:
	if xp_bar != null:
		_flash_canvas_item(xp_bar, Color(0.5, 1.0, 0.6))
		_pop_scale(xp_bar, 1.06, 0.35)
	if xp_icon != null:
		_pop_scale(xp_icon, 1.5, 0.5)


func _play_level_vfx() -> void:
	if level_label != null:
		_pop_scale(level_label, 1.35, 0.5)
	if xp_icon != null:
		_pop_scale(xp_icon, 1.7, 0.55)


func _flash_canvas_item(item: CanvasItem, flash_color: Color) -> void:
	if item == null:
		return
	var alpha := float(item.modulate.a)
	var target := Color(1.0, 1.0, 1.0, alpha)
	item.modulate = Color(flash_color.r, flash_color.g, flash_color.b, alpha)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "modulate", target, 0.5)


func _pop_scale(item: CanvasItem, multiplier: float, duration: float) -> void:
	if item == null:
		return
	var base: Vector2 = item.get("scale")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", base * multiplier, duration * 0.35)
	tween.tween_property(item, "scale", base, duration * 0.65)


func _shake(item: CanvasItem, strength: float, duration: float) -> void:
	if item == null:
		return
	var base: Vector2 = item.get("position")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "position", base + Vector2(-strength, 0.0), duration * 0.2)
	tween.tween_property(item, "position", base + Vector2(strength, 0.0), duration * 0.2)
	tween.tween_property(item, "position", base + Vector2(-strength * 0.5, 0.0), duration * 0.2)
	tween.tween_property(item, "position", base, duration * 0.4)


func _spawn_floating_text(parent: Node, local_position: Vector2, text: String, color: Color) -> void:
	if parent == null:
		return
	var floater := Label.new()
	floater.text = text
	floater.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floater.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	floater.size = Vector2(110, 26)
	floater.position = local_position - Vector2(55, 13)
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floater.z_index = 20
	floater.add_theme_color_override("font_color", color)
	floater.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 1.0))
	floater.add_theme_constant_override("outline_size", 4)
	floater.add_theme_font_size_override("font_size", 14)
	parent.add_child(floater)

	var start_y := floater.position.y
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(floater, "position:y", start_y - 28.0, FLOAT_TEXT_LIFETIME)
	tween.tween_property(floater, "modulate:a", 0.0, FLOAT_TEXT_LIFETIME * 0.6).set_delay(FLOAT_TEXT_LIFETIME * 0.4)
	tween.chain().tween_callback(floater.queue_free)


func _refresh_world_page() -> void:
	var traders: Array[String] = []
	for npc in get_tree().get_nodes_in_group("NPC"):
		var activity := str(npc.get("behavior_state") if npc.get("behavior_state") != null else "nearby")
		traders.append("%s — %s" % [npc.name, activity.capitalize()])

	var world_sections := get_node_or_null("pages/worldmap/WorldSections")
	if world_sections == null:
		return

	var trader_label := world_sections.get_node_or_null("pages/traders") as Label
	if trader_label != null:
		trader_label.text = "No traders nearby" if traders.is_empty() else "\n".join(traders.slice(0, 3))

	var pages := world_sections.get_node_or_null("pages")
	if pages != null:
		var world_label := pages.get_node_or_null("world")
		if world_label == null:
			world_label = Label.new()
			world_label.name = "world"
			world_label.horizontal_alignment = 1
			world_label.vertical_alignment = 1
			world_label.theme = world_sections.theme
			pages.add_child(world_label)
		var level := get_tree().current_scene
		var map_size := "Unknown"
		if level != null and level.get("width") != null and level.get("height") != null:
			map_size = "%d × %d" % [int(level.get("width")), int(level.get("height"))]
		world_label.text = "Day %d  •  %s\n%s  •  World size: %s" % [WorldTime.day_count, WorldTime.format_time(), WorldTime.format_date(), map_size]


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
