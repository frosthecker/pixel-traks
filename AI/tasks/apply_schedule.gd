extends BTAction

@export var goal_var: StringName = &"current_goal"
@export var location_var: StringName = &"target_location"

var last_activity: String = ""

func _tick(_delta: float) -> Status:
	var biodata = agent.get("biodata")
	if biodata == null or biodata.daily_schedule.is_empty():
		return SUCCESS

	var clock := agent.get_node_or_null("/root/WorldTime")
	if clock == null:
		return SUCCESS

	var entry: Dictionary = _find_schedule_entry(biodata.daily_schedule, clock.get_current_minutes())
	if entry.is_empty():
		return SUCCESS

	var activity: String = str(entry.get("activity", "idle"))
	blackboard.set_var(goal_var, activity)
	if entry.has("target_location"):
		blackboard.set_var(location_var, entry["target_location"])
	if not bool(agent.get("dialogue_running")):
		agent.set("behavior_state", _activity_to_state(activity))

	if activity != last_activity:
		last_activity = activity
		print(agent.name, " schedule: ", activity, " at ", clock.format_time())
	return SUCCESS

func _find_schedule_entry(schedule: Array[Dictionary], now: int) -> Dictionary:
	for entry in schedule:
		var start: int = int(entry.get("start_minute", 0))
		var end: int = int(entry.get("end_minute", 1440))
		if start <= end and now >= start and now < end:
			return entry
		if start > end and (now >= start or now < end):
			return entry
	return {}

func _activity_to_state(activity: String) -> String:
	match activity:
		"sleep":
			return "sleep"
		"work", "farm", "eat":
			return "work"
		"follow_player":
			return "follow_player"
		"chase":
			return "chase"
		"talk":
			return "talk"
		"wander":
			return "wander"
		_:
			return "idle"
