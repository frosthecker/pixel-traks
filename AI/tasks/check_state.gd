extends BTCondition

## Checks the explicit state selected on the NPC scene/script.
@export var required_state: StringName = &"idle"

func _tick(_delta: float) -> Status:
	var current_state = agent.get("behavior_state")
	if current_state != null and StringName(current_state) == required_state:
		return SUCCESS
	return FAILURE
