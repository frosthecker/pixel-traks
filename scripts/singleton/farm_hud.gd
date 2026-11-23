extends CanvasLayer

## Small transient text banner used for season changes, level-ups and farming
## feedback. It is an autoload so every level and tool-use path can use it
## without wiring scene-specific UI.

@onready var banner_scene: PackedScene = preload("res://scenes/UI/banner.tscn")
var _banner_instance: Control
var _label: Label
var _vbox: VBoxContainer
var _banner_tween: Tween

# Resting offsets of the banner's VBoxContainer. We animate the offsets instead
# of `position`, because writing `position` on an anchored Control re-computes
# its offsets from scratch and breaks the horizontal centering.
var _base_top := 40.0
var _base_bottom := 40.0
const SLIDE_DISTANCE := 96.0

func _ready() -> void:
	layer = 90
	_build_banner()
	if not WorldTime.season_changed.is_connected(_on_season_changed):
		WorldTime.season_changed.connect(_on_season_changed)
	if not FarmState.farming_level_changed.is_connected(_on_farming_level_changed):
		FarmState.farming_level_changed.connect(_on_farming_level_changed)

func _build_banner() -> void:
	_banner_instance = banner_scene.instantiate()
	_vbox = _banner_instance.get_node("VBoxContainer")
	_label = _vbox.get_node("Label")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_top = _vbox.offset_top
	_base_bottom = _vbox.offset_bottom
	_label.modulate.a = 0.0
	add_child(_banner_instance)

func notice(text: String, color: Color = Color.WHITE, hold_seconds: float = 2.0) -> void:
	if _label == null:
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_label.modulate.a = 0.0

	# Start fully above the viewport, then drop down into place.
	_vbox.offset_top = _base_top - SLIDE_DISTANCE
	_vbox.offset_bottom = _base_bottom - SLIDE_DISTANCE

	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_label, "modulate:a", 1.0, 0.22)
	_banner_tween.tween_property(_vbox, "offset_top", _base_top, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_vbox, "offset_bottom", _base_bottom, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(hold_seconds).timeout

	if _label == null or not is_instance_valid(_label):
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_label, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_property(_vbox, "offset_top", _base_top - SLIDE_DISTANCE, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_property(_vbox, "offset_bottom", _base_bottom - SLIDE_DISTANCE, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

func _on_season_changed(season: int, _day_of_season: int) -> void:
	notice("%s has arrived." % Data.season_name(season), Data.SEASON_COLORS[clampi(season, 0, Data.SEASON_COLORS.size() - 1)], 3.0)

func _on_farming_level_changed(level: int, _xp: int, _xp_to_next: int) -> void:
	notice("Farming level %d!" % level, Color(0.65, 1.0, 0.65), 2.5)
