extends BTAction

@export var group: StringName
@export var target_var: StringName = &"target"
@export var max_distance: float = -1.0

var target: Node
var last_reported_target: Node


func _tick(_delta: float) -> Status:
	var nodes: Array[Node] = _get_target_nodes()
	var candidates: Array[Node] = []

	for node in nodes:
		if is_instance_valid(node) and node != agent and node is CharacterBody2D:
			candidates.append(node)

	if candidates.is_empty():
		blackboard.set_var(target_var, null)
		print("No target found in group: ", group)
		return FAILURE

	# Use the closest matching target instead of relying on group order.
	target = candidates[0]
	var closest_distance: float = agent.global_position.distance_squared_to(target.global_position)
	for candidate in candidates.slice(1):
		var candidate_distance: float = agent.global_position.distance_squared_to(candidate.global_position)
		if candidate_distance < closest_distance:
			target = candidate
			closest_distance = candidate_distance

	if max_distance >= 0.0 and sqrt(closest_distance) > max_distance:
		blackboard.set_var(target_var, null)
		return FAILURE

	blackboard.set_var(target_var, target)
	if target != last_reported_target:
		print("Found target: ", target.name)
		last_reported_target = target
	return SUCCESS

func _get_target_nodes() -> Array[Node]:
	if not group.is_empty():
		return agent.get_tree().get_nodes_in_group(group)

	var nodes: Array[Node] = []
	_collect_character_bodies(agent.get_tree().root, nodes)
	return nodes

func _collect_character_bodies(node: Node, result: Array[Node]) -> void:
	if node is CharacterBody2D and node != agent:
		result.append(node)

	for child in node.get_children():
		_collect_character_bodies(child, result)
