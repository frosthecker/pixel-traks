extends BTAction

## Behavior tree task for NPC social interactions

@export var interaction_type: String = "chat"  # chat, trade, gift, cooperate, share_rumor

func _tick(_delta: float) -> Status:
	var social = agent.get_node_or_null("NPCSocial")
	if social == null:
		return FAILURE
	
	# Find nearby NPCs to interact with
	var nearby_npcs = _get_nearby_npcs()
	if nearby_npcs.is_empty():
		return FAILURE
	
	# Pick a suitable target based on interaction type
	var target = _choose_target(nearby_npcs)
	if target == null:
		return FAILURE
	
	# Initiate interaction through social component
	# The social component handles the actual interaction asynchronously
	var success = social.call("_initiate_interaction", target, interaction_type)
	if not success:
		return FAILURE
	
	# Wait for interaction to complete (handled by social component signals)
	return RUNNING

func _get_nearby_npcs() -> Array[Node]:
	var npcs := []
	var space_state := agent.get_world_2d().direct_space_state
	var query := PhysicsCircleQueryParameters2D.create(agent.global_position, 100.0)
	query.collision_mask = 1 << 10  # NPC layer
	query.exclude = [agent.get_rid()]
	
	var results := space_state.intersect_shape(query)
	for result in results:
		if result.collider and result.collider.has_method("get_unique_npc_id") and result.collider != agent:
			npcs.append(result.collider)
	
	return npcs

func _choose_target(npcs: Array[Node]) -> Node:
	if npcs.is_empty():
		return null
	
	# Prefer NPCs with higher relationship
	var best_target := null
	var best_score := -INF
	
	for npc in npcs:
		var social := npc.get_node_or_null("NPCSocial")
		if social == null:
			continue
		
		var rel := agent.call("get_relationship", npc.get_unique_npc_id())
		if rel == null:
			continue
		
		# Score based on interaction type and relationship
		var score := 0.0
		match interaction_type:
			"chat":
				score = rel.affinity + rel.familiarity * 0.5
			"trade":
				score = rel.affinity * 0.5 + rel.trust * 0.5
			"gift":
				score = rel.affinity + rel.generosity if rel.has("generosity") else 0
			"cooperate":
				score = rel.affinity + rel.trust
			"share_rumor":
				score = rel.familiarity * 0.7
		
		if score > best_score:
			best_score = score
			best_target = npc
	
	return best_target