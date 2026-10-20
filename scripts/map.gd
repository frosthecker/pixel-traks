extends Node2D
@onready var light_flicker: AnimatedSprite2D = $"light flicker"
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func open():
	light_flicker.play("open")
	animation_player.play_backwards("tab_close")
	animation_player.play("compass_calibrate")

func close():
	animation_player.play("tab_close")
	light_flicker.play("close")
