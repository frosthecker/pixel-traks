extends Node

const PLAYER_SKINS = {
	Enum.Style.BASIC: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_v1.0.png"),
	Enum.Style.CURLY: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_curly_hair.png"),
	Enum.Style.GIRL: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_long_hair.png"),
	Enum.Style.MOP: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_mop_hair.png"),
	Enum.Style.SHORT: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_short_hair.png"),
	Enum.Style.SPIKEY: preload("res://assets/Sunnyside_World_Assets/Characters/Human/sunnyside_world_chatacter_anim_human_spikey_hair.png")
	
	}
const TILE_SIZE = 16
var PLANT_DATA = {
	Enum.Seed.BEETROOT: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/beetroot_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/beetroot_05.png",
		'name':'Beetroot',
		'h_frames': 3,
		'grow_speed': 0.6,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING, Enum.Season.FALL],
		'reward': Enum.Item.BEETROOT},
	Enum.Seed.CABBAGE: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cabbage_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cabbage_05.png",
		'name':'Cabbage',
		'h_frames': 3,
		'grow_speed': 1.0,
		'death_max': 2,
		'seasons': [Enum.Season.FALL],
		'reward': Enum.Item.CABBAGE},
	Enum.Seed.PUMPKIN: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/pumpkin_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/pumpkin_05.png",
		'name':'Pumpkin',
		'h_frames': 3,
		'grow_speed': 0.3,
		'death_max': 3,
		'seasons': [Enum.Season.SUMMER, Enum.Season.FALL],
		'reward': Enum.Item.PUMPKIN},
	Enum.Seed.WHEAT: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/wheat_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/wheat_05.png",
		'name':'Wheat',
		'h_frames': 3,
		'grow_speed': 1.0,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING, Enum.Season.SUMMER, Enum.Season.FALL],
		'reward': Enum.Item.WHEAT},
	Enum.Seed.CARROT: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/carrot_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/carrot_05.png",
		'name':'Carrot',
		'h_frames': 3,
		'grow_speed': 0.4,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING, Enum.Season.FALL],
		'reward': Enum.Item.CARROT},
	Enum.Seed.CAULIFLOWER: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cauliflower_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cauliflower_05.png",
		'name':'Cauliflower',
		'h_frames': 3,
		'grow_speed': 0.5,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING],
		'reward': Enum.Item.CAULIFLOWER},
	Enum.Seed.POTATO: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/potato_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/potato_05.png",
		'name':'Potato',
		'h_frames': 3,
		'grow_speed': 0.3,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING, Enum.Season.SUMMER],
		'reward': Enum.Item.POTATO},
	Enum.Seed.RADISH: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/radish_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/radish_05.png",
		'name':'Radish',
		'h_frames': 3,
		'grow_speed': 0.8,
		'death_max': 3,
		'seasons': [Enum.Season.SPRING, Enum.Season.SUMMER, Enum.Season.FALL],
		'reward': Enum.Item.RADISH}
	
		}
'''const MACHINE_UPGRADE_COST = {
	Enum.Machine.SPRINKLER: {
		'name': 'Sprinkler',
		'cost' :{Enum.Item.TOMATO: 30, Enum.Item.WHEAT: 20},
		'icon': preload("res://graphics/icons/sprinkler.png"),
		'color': Color.SEA_GREEN},
	Enum.Machine.FISHER: {
		'name': 'Fisher',
		'cost' :{Enum.Item.WOOD: 25, Enum.Item.FISH: 15},
		'icon': preload("res://graphics/icons/fisher.png"),
		'color': Color.SLATE_GRAY},
	Enum.Machine.SCARECROW: {
		'name': 'Scarecrow',
		'cost' : {Enum.Item.PUMPKIN: 15, Enum.Item.CORN: 15},
		'icon': preload("res://graphics/icons/scarecrow.png"),
		'color': Color.BURLYWOOD}}'''
var HOUSE_COST = {
	1: {Enum.Item.WOOD: 30},
	2: {Enum.Item.WOOD: 40}}
'''const STYLE_UPGRADES = {
	Enum.Style.COWBOY: {
		'name': 'Cowboy',
		'cost':{Enum.Item.WOOD: 8, Enum.Item.CORN: 6},
		'icon': preload("res://graphics/icons/cowboy.png"),
		'color': Color.SANDY_BROWN},
	Enum.Style.ENGLISH: {
		'name': 'Oldie',
		'cost':{Enum.Item.CORN: 8, Enum.Item.WHEAT: 6},
		'icon': preload("res://graphics/icons/english.png"),
		'color': Color.LIGHT_GRAY},
	Enum.Style.BASEBALL: {
		'name': 'Baseball',
		'cost':{Enum.Item.TOMATO: 8, Enum.Item.APPLE: 6},
		'icon': preload("res://graphics/icons/blue.png"),
		'color': Color.SKY_BLUE},
	Enum.Style.BEANIE: {
		'name': 'Beanie',
		'cost':{Enum.Item.PUMPKIN: 8, Enum.Item.WHEAT: 6},
		'icon': preload("res://graphics/icons/beanie.png"),
		'color': Color.INDIAN_RED},
	Enum.Style.STRAW: {
		'name': 'Straw',
		'cost':{Enum.Item.FISH: 8, Enum.Item.WOOD: 6},
		'icon': preload("res://graphics/icons/straw.png"),
		'color': Color.BURLYWOOD}}'''
const SEASON_NAMES = ["Spring", "Summer", "Fall", "Winter"]
const SEASON_GROWTH_MULTIPLIER = [1.0, 1.1, 1.0, 0.8]
const SEASON_COLORS = [
	Color(0.55, 0.9, 0.55),
	Color(1.0, 0.85, 0.35),
	Color(0.95, 0.6, 0.3),
	Color(0.65, 0.8, 1.0)
]

const QUALITY_NAMES = ["Normal", "Silver", "Gold", "Iridium"]
const QUALITY_STARS = ["", "★", "★★", "★★★"]
const QUALITY_SELL_MULTIPLIER = [1.0, 1.25, 1.6, 2.0]
const QUALITY_COLORS = [
	Color.WHITE,
	Color(0.78, 0.88, 1.0),
	Color(1.0, 0.84, 0.3),
	Color(0.85, 0.62, 1.0)
]

## Tool upgrade chains. Tier 0 is the starting tool; each entry is the next
## purchasable tier. "radius" is the number of cells around the target that a
## hoe/watering can affects. "extra_hits" adds axe damage.
const TOOL_UPGRADE_KEYS = {
	Enum.Tool.HOE: "hoe",
	Enum.Tool.WATER: "water",
	Enum.Tool.AXE: "axe"
}
const TOOL_DISPLAY_NAMES = {
	Enum.Tool.HOE: "Hoe",
	Enum.Tool.WATER: "Watering Can",
	Enum.Tool.AXE: "Axe"
}
const TOOL_UPGRADE_DATA = {
	"hoe": [
		{"name": "Copper Hoe", "cost": 120, "radius": 1},
		{"name": "Steel Hoe", "cost": 360, "radius": 2}
	],
	"water": [
		{"name": "Copper Watering Can", "cost": 100, "radius": 1},
		{"name": "Steel Watering Can", "cost": 320, "radius": 2}
	],
	"axe": [
		{"name": "Copper Axe", "cost": 160, "extra_hits": 1},
		{"name": "Steel Axe", "cost": 420, "extra_hits": 2}
	]
}

const MACHINE_DATA = {
	Enum.Machine.SPRINKLER: {
		"name": "Sprinkler",
		"cost_money": 180,
		"radius": 2,
		"description": "Waters every tilled cell around it each morning."
	},
	Enum.Machine.SCARECROW: {
		"name": "Scarecrow",
		"cost_money": 140,
		"radius": 4,
		"description": "Keeps crows away from nearby crops."
	}
}

func season_name(season: int) -> String:
	return SEASON_NAMES[clampi(season, 0, SEASON_NAMES.size() - 1)]

func season_growth_multiplier(season: int) -> float:
	return float(SEASON_GROWTH_MULTIPLIER[clampi(season, 0, SEASON_GROWTH_MULTIPLIER.size() - 1)])

func seed_in_season(seed: int, season: int) -> bool:
	var crop: Variant = PLANT_DATA.get(seed)
	if not (crop is Dictionary):
		return true
	var seasons: Variant = crop.get("seasons", [])
	if not (seasons is Array) or seasons.is_empty():
		return true
	return season in seasons

func first_seed_in_season(season: int) -> int:
	for seed in PLANT_DATA:
		if seed_in_season(int(seed), season):
			return int(seed)
	return int(Enum.Seed.BEETROOT)

func quality_name(quality: int) -> String:
	return QUALITY_NAMES[clampi(quality, 0, QUALITY_NAMES.size() - 1)]

func quality_stars(quality: int) -> String:
	return QUALITY_STARS[clampi(quality, 0, QUALITY_STARS.size() - 1)]

func quality_multiplier(quality: int) -> float:
	return float(QUALITY_SELL_MULTIPLIER[clampi(quality, 0, QUALITY_SELL_MULTIPLIER.size() - 1)])

func quality_color(quality: int) -> Color:
	return QUALITY_COLORS[clampi(quality, 0, QUALITY_COLORS.size() - 1)]

const TOOL_STATE_ANIMATIONS = {
	Enum.Tool.HOE: 'Hoe',
	Enum.Tool.AXE: 'Axe',
	Enum.Tool.WATER: 'Water',
	Enum.Tool.SWORD: 'Sword',
	Enum.Tool.FISH: 'Fish',
	Enum.Tool.SEED: 'Seed',
	Enum.Tool.HAMMER: 'Hammer',
	}
