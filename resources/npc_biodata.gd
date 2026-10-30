class_name NPCBiodata extends Resource

@export var display_name: String = ""
@export_multiline var personality: String = ""
@export var movement_speed: float = 25.0
@export var daily_schedule: Array[Dictionary] = []
@export var favorite_locations: Array[Vector2] = []
@export var relationship_values: Dictionary = {}
@export var current_mood: StringName = &"neutral"
