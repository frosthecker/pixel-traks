extends BTAction

func _tick(_delta: float) -> Status:
	if bool(agent.get("dialogue_running")):
		return RUNNING
	return SUCCESS
