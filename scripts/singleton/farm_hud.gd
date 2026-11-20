extends CanvasLayer

## Small transient text banner used for season changes, level-ups and farming
## feedback. It is an autoload so every level and tool-use path can use it
## without wiring scene-specific UI.

var _label: Label
var _tween: Tween

func _ready() -> void:
	layer = 90
	_build_label()
	if not WorldTime.season_changed.is_connected(_on_season_changed):
		WorldTime.season_changed.connect(_on_season_changed)
	if not FarmState.farming_level_changed.is_connected(_on_farming_level_changed):
		FarmState.farming_level_changed.connect(_on_farming_level_changed)

func _build_label() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.offset_left = -260.0
	_label.offset_right = 260.0
	_label.offset_top = 44.0
	_label.offset_bottom = 80.0
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_label.add_theme_constant_override("outline_size", 5)
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func notice(text: String, color: Color = Color.WHITE, hold_seconds: float = 2.0) -> void:
	if _label == null:
		return
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.45)

func _on_season_changed(season: int, _day_of_season: int) -> void:
	notice("%s has arrived." % Data.season_name(season), Data.SEASON_COLORS[clampi(season, 0, Data.SEASON_COLORS.size() - 1)], 3.0)

func _on_farming_level_changed(level: int, _xp: int, _xp_to_next: int) -> void:
	notice("Farming level %d!" % level, Color(0.65, 1.0, 0.65), 2.5)
