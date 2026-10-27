extends Control

const LEVEL_SCENE_PATH := "res://scenes/levels/proc_level.tscn"
const MINIMUM_DISPLAY_SECONDS := 5.0

func _ready() -> void:
	call_deferred("_load_level")

func _load_level() -> void:
	var started_at := Time.get_ticks_msec()
	# This level's scripts use autoloads (Data, PlayerInventory, and SaveGame).
	# Godot may compile a scene's scripts before those names are available when it
	# is requested on the background loader thread, producing misleading parse
	# errors in otherwise valid .tscn files. Load on the main thread instead.
	# The loading screen remains visible while this happens.
	var level_scene := load(LEVEL_SCENE_PATH) as PackedScene

	var elapsed := float(Time.get_ticks_msec() - started_at) / 1000.0
	if elapsed < MINIMUM_DISPLAY_SECONDS:
		await get_tree().create_timer(MINIMUM_DISPLAY_SECONDS - elapsed).timeout

	if level_scene == null:
		push_error("The level scene could not be loaded.")
		return

	# Do not use change_scene_to_packed() here. It removes this scene before the
	# new one has had a chance to draw, exposing the renderer clear color for a
	# frame. Keep the loading screen on top until the level is in the scene tree
	# and has rendered once.
	var level := level_scene.instantiate()
	var scene_tree := get_tree()
	scene_tree.root.add_child(level)
	scene_tree.current_scene = level
	# Procedural generation yields over multiple frames so this animation stays
	# responsive. Keep the loading scene visible until that work is complete.
	if not bool(level.get("world_boot_complete")) and level.has_signal("world_boot_completed"):
		await level.world_boot_completed

	await RenderingServer.frame_post_draw
	queue_free()
