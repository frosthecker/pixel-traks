class_name NPCSocial extends Node

signal social_interaction_started(participant_a: Node, participant_b: Node, interaction_type: String)
signal social_interaction_ended(participant_a: Node, participant_b: Node, interaction_type: String, outcome: String)
signal relationship_changed(target_id: String, old_tier: int, new_tier: int, affinity_change: float)
signal group_formed(group_id: String, members: Array[Node])
signal group_disbanded(group_id: String)
signal rumor_spread(rumor: Dictionary, from_npc: Node, to_npc: Node)

@export var interaction_range: float = 64.0
@export var conversation_chance: float = 0.3
@export var trade_chance: float = 0.1
@export var max_conversation_duration: float = 10.0
@export var social_check_interval: float = 5.0

var social_groups: Dictionary = {}
var pending_interactions: Array = []
var interaction_history: Array = []

var npc_memory: Variant
var npc_relationships: Dictionary = {}
var current_interaction: Dictionary = {}
var interaction_timer: float = 0.0
var social_check_timer: float = 0.0

var _npc: Node

func _ready() -> void:
	_npc = get_parent()
	if _npc == null:
		push_error("NPCSocial must be child of CharacterBody2D")
		return
	
	_initialize_relationships()

func _physics_process(delta: float) -> void:
	social_check_timer += delta
	if social_check_timer >= 5.0:
		social_check_timer = 0.0
		_check_social_opportunities()
	if not current_interaction.is_empty():
		_update_current_interaction(delta)

func _initialize_relationships() -> void:
	pass

func _check_social_opportunities() -> void:
	pass

func _get_nearby_npcs() -> Array:
	return []

func _get_prop(node: Node, prop: String, default: Variant) -> Variant:
	if node.has(prop):
		return node.get(prop)
	return default

func _should_initiate_interaction(other_npc: Node, relationship: Variant) -> bool:
	return false

func _choose_interaction_type(other_npc: Node, relationship: Variant) -> String:
	return "chat"

func _initiate_interaction(other_npc: Node, interaction_type: String) -> void:
	pass

func _accept_interaction(initiator: Node, interaction_type: String) -> bool:
	return false

func _pause_ai_for_interaction() -> void:
	pass

func _resume_ai_after_interaction() -> void:
	pass

func _execute_interaction(interaction_type: String) -> void:
	pass

func _start_chat() -> void:
	pass

func _continue_chat() -> void:
	pass

func _show_dialogue_bubble(text: String) -> void:
	emit_signal("show_bubble", text)

func _start_trade() -> void:
	pass

func _execute_trade(my_item: String, their_item: String) -> void:
	pass

func _start_gift() -> void:
	pass

func _start_cooperate() -> void:
	pass

func _start_compete() -> void:
	pass

func _start_fight() -> void:
	pass

func _start_flirt() -> void:
	pass

func _start_insult() -> void:
	pass

func _start_apologize() -> void:
	pass

func _start_share_rumor() -> void:
	pass

func _update_current_interaction(delta: float) -> void:
	pass

func _end_interaction(outcome: String) -> void:
	pass

func get_relationship(entity_id: String) -> Variant:
	return null

func modify_relationship(entity_id: String, affinity_change: float, reason: String = "", target_type: String = "npc") -> void:
	pass

func get_relationship_tier(entity_id: String) -> int: return 0
func get_affinity(entity_id: String) -> float: return 0.0
func get_relationship_modifiers(entity_id: String) -> Dictionary: return {}

func form_social_group(group_id: String, group_type: String, members: Array, leader: Node = null) -> void:
	pass

func leave_social_group(group_id: String) -> void:
	pass

func disband_social_group(group_id: String) -> void:
	pass

func _on_group_joined(group_id: String, group_type: String) -> void: pass
func _on_group_member_left(group_id: String, member: Node) -> void: pass
func _on_group_disbanded(group_id: String) -> void: pass

func hear_rumor(content: String, source: String, believed: bool = true) -> void:
	pass

func get_unique_npc_id() -> String: return "npc_%d" % _npc.get_instance_id()
func _get_inventory_items() -> Array: return []
func _get_item_value(item: String) -> int: return 10
func _add_inventory_item(item: String) -> void: pass
func _remove_inventory_item(item: String) -> void: pass
func face_target(target: Node) -> void: pass
func take_damage(amount: int) -> void: pass

func get_social_save_data() -> Dictionary: return {}
func load_social_save_data(data: Dictionary) -> void: pass
func resolve_pending_groups(all_npcs: Array) -> void: pass