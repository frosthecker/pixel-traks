extends Node

## Persistent farming progression shared by every level. SaveGame writes this
## alongside the player inventory so tool upgrades and farming XP survive a
## world reload.

signal farming_level_changed(level: int, xp: int, xp_to_next: int)
signal tool_upgraded(tool: int, tier: int)

const BASE_XP := 40
const XP_PER_LEVEL := 25

var farming_level: int = 1
var farming_xp: int = 0
var tool_tiers: Dictionary = {}

func _ready() -> void:
	_ensure_defaults()

func _ensure_defaults() -> void:
	for key in Data.TOOL_UPGRADE_DATA:
		if not tool_tiers.has(key):
			tool_tiers[key] = 0

func reset() -> void:
	farming_level = 1
	farming_xp = 0
	tool_tiers.clear()
	_ensure_defaults()
	farming_level_changed.emit(farming_level, farming_xp, xp_to_next_level())

func get_save_data() -> Dictionary:
	_ensure_defaults()
	return {
		"level": farming_level,
		"xp": farming_xp,
		"tool_tiers": tool_tiers.duplicate(true)
	}

func load_save_data(save_data: Dictionary) -> void:
	farming_level = maxi(1, int(save_data.get("level", 1)))
	farming_xp = maxi(0, int(save_data.get("xp", 0)))
	tool_tiers.clear()
	_ensure_defaults()
	var tiers: Variant = save_data.get("tool_tiers", {})
	if tiers is Dictionary:
		for key in tiers:
			var tool_key := str(key)
			if tool_tiers.has(tool_key):
				tool_tiers[tool_key] = maxi(0, int(tiers[key]))
	farming_level_changed.emit(farming_level, farming_xp, xp_to_next_level())

func xp_to_next_level() -> int:
	return BASE_XP + (farming_level - 1) * XP_PER_LEVEL

func add_farming_xp(amount: int) -> void:
	if amount <= 0:
		return
	farming_xp += amount
	var leveled_up := false
	while farming_xp >= xp_to_next_level():
		farming_xp -= xp_to_next_level()
		farming_level += 1
		leveled_up = true
	if leveled_up:
		farming_level_changed.emit(farming_level, farming_xp, xp_to_next_level())

func get_tool_key(tool: int) -> String:
	return str(Data.TOOL_UPGRADE_KEYS.get(tool, ""))

func get_tool_tier(tool: int) -> int:
	var key := get_tool_key(tool)
	if key.is_empty():
		return 0
	return int(tool_tiers.get(key, 0))

func get_next_tool_upgrade(tool: int) -> Dictionary:
	var key := get_tool_key(tool)
	var tiers: Array = Data.TOOL_UPGRADE_DATA.get(key, [])
	var tier := get_tool_tier(tool)
	if tier < 0 or tier >= tiers.size():
		return {}
	return tiers[tier]

## Returns the stat from the currently equipped tier, or `default_value` for
## the starting tool.
func get_tool_stat(tool: int, stat: String, default_value: Variant = 0) -> Variant:
	var key := get_tool_key(tool)
	var tiers: Array = Data.TOOL_UPGRADE_DATA.get(key, [])
	var tier := get_tool_tier(tool)
	if tier <= 0 or tier > tiers.size():
		return default_value
	return tiers[tier - 1].get(stat, default_value)

func get_tool_area_radius(tool: int) -> int:
	return int(get_tool_stat(tool, "radius", 0))

func get_axe_hits() -> int:
	return 1 + int(get_tool_stat(Enum.Tool.AXE, "extra_hits", 0))

func purchase_tool_upgrade(tool: int) -> bool:
	var next := get_next_tool_upgrade(tool)
	if next.is_empty():
		return false
	var cost := int(next.get("cost", 0))
	if not PlayerInventory.spend_money(cost):
		return false
	var key := get_tool_key(tool)
	tool_tiers[key] = get_tool_tier(tool) + 1
	tool_upgraded.emit(tool, get_tool_tier(tool))
	return true
