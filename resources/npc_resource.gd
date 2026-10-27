class_name NPCResource extends Resource

const NPCBiodataType = preload("res://resources/npc_biodata.gd")

@export var texture: Texture2D
@export_file("*.dch") var dialogue_character: String = ""
@export_file("*.dtl") var dialogue_timeline: String = ""
@export_file("*.dtl") var intro_timeline: String = ""
@export var random_timelines: Array[String] = []
@export var dialogue_distance: float = 32.0
@export var key_prompt_delay: float = 5.0
@export var biodata: NPCBiodataType
