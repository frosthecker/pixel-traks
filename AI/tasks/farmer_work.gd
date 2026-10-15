extends BTAction

func _tick(_delta: float) -> Status:
	if not agent.has_method("farmer_work_step"):
		return FAILURE
	if agent.farmer_work_step():
		return SUCCESS
	return RUNNING
