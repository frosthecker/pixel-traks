extends Node2D




func _on_player_tool_use(tool: Enum.Tool, pos: Vector2) -> void:
	match tool:
		Enum.Tool.HOE:
			print(pos)
