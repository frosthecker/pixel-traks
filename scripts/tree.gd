extends StaticBody2D

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var stump: Sprite2D = $stump
@onready var flash_sprite_2d: Sprite2D = $FlashSprite2D
var health := 3:
	set(value):
		health = value
		if health <= 0:
			stump.show()
			flash_sprite_2d.hide()
			var shape = RectangleShape2D.new()
			shape.size = Vector2i(16,14)
			collision_shape.shape = shape
			collision_shape.position.y = 9

func hit(tool: Enum.Tool):
	if tool == Enum.Tool.AXE:
		flash_sprite_2d.flash()
		health-=1
