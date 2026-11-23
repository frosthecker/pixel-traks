extends Node

## NPC Spawner - Populates the world with unique NPCs at their home locations

signal npc_spawned(npc: Node)
signal all_npcs_spawned

@export var spawn_on_start: bool = true

## Load NPC definitions from central registry
var npc_definitions: Array[Dictionary] = NPCDefinitions.get_all_definitions()

var spawned_npcs: Array[Node] = []

func _ready() -> void:
	# Create missing NPC scenes first
	_create_missing_scenes()
	
	if spawn_on_start:
		call_deferred("spawn_all_npcs")

func _create_missing_scenes() -> void:
	# This would create the .tscn files for NPCs that don't have them yet
	# For now, we'll create them programmatically if needed
	pass

func spawn_all_npcs() -> void:
	var level := get_tree().get_first_node_in_group("Level")
	if not level:
		return
	
	var objects_parent := level.get_node_or_null("Objects")
	if not objects_parent:
		# print("[NPCSpawner] No Objects parent found!")
		return
	
	spawned_npcs.clear()
	
	for def in npc_definitions:
		var npc := _spawn_npc(def, objects_parent)
		if npc:
			spawned_npcs.append(npc)
			npc_spawned.emit(npc)
	
	# Resolve social groups after all NPCs are spawned
	_resolve_social_groups()
	
	all_npcs_spawned.emit()
	# print("[NPCSpawner] Spawned ", spawned_npcs.size(), " NPCs")

func _spawn_npc(def: Dictionary, parent: Node) -> Node:
	var scene_path: String = def["scene"]
	var position: Vector2 = def["position"]
	var npc_id: String = str(def.get("id", def.get("npc_id", "")))
	var npc_name: String = str(def.get("name", ""))
	
	var scene := ResourceLoader.load(scene_path)
	if not scene:
		# print("[NPCSpawner] Failed to load scene: ", scene_path)
		return null
	
	var npc: Node = scene.instantiate()
	if not npc:
		# print("[NPCSpawner] Failed to instantiate: ", scene_path)
		return null
	
	# Set the persistent identity before _ready runs.
	if "npc_id" in npc and not npc_id.is_empty():
		npc.set("npc_id", npc_id)
	if "npc_name" in npc and not npc_name.is_empty():
		npc.set("npc_name", npc_name)
	
	# Add to scene
	parent.add_child(npc)
	npc.global_position = position
	
	# Add to NPC group
	npc.add_to_group("NPC")
	
	# print("[NPCSpawner] Spawned ", npc_name, " at ", position)
	return npc

func _resolve_social_groups() -> void:
	# Give NPCs time to initialize, then resolve pending groups
	call_deferred("_do_resolve_groups")

func _do_resolve_groups() -> void:
	var all_npcs := get_tree().get_nodes_in_group("NPC")
	for npc in all_npcs:
		if npc.has_method("resolve_pending_groups"):
			npc.resolve_pending_groups(all_npcs)

## Manual spawn for testing
func spawn_npc_at(index: int, position: Vector2) -> Node:
	if index < 0 or index >= npc_definitions.size():
		return null
	
	var def := npc_definitions[index].duplicate()
	def["position"] = position
	
	var level := get_tree().get_first_node_in_group("Level")
	var objects_parent := level.get_node_or_null("Objects") if level else null
	if not objects_parent:
		return null
	
	var npc := _spawn_npc(def, objects_parent)
	if npc:
		spawned_npcs.append(npc)
	
	return npc

## Despawn all NPCs (for testing/reset)
func despawn_all() -> void:
	for npc in spawned_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	spawned_npcs.clear()

## Get spawned NPC by name
func get_npc(name: String) -> Node:
	for npc in spawned_npcs:
		if is_instance_valid(npc) and npc.npc_name == name:
			return npc
	return null

## Get all spawned NPCs
func get_all_npcs() -> Array[Node]:
	return spawned_npcs.duplicate()