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
		'reward': Enum.Item.BEETROOT},
	Enum.Seed.CABBAGE: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cabbage_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cabbage_05.png",
		'name':'Cabbage',
		'h_frames': 3,
		'grow_speed': 1.0,
		'death_max': 2,
		'reward': Enum.Item.CABBAGE},
	Enum.Seed.PUMPKIN: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/pumpkin_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/pumpkin_05.png",
		'name':'Pumpkin',
		'h_frames': 3,
		'grow_speed': 0.3,
		'death_max': 3,
		'reward': Enum.Item.PUMPKIN},
	Enum.Seed.WHEAT: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/wheat_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/wheat_05.png",
		'name':'Wheat',
		'h_frames': 3,
		'grow_speed': 1.0,
		'death_max': 3,
		'reward': Enum.Item.WHEAT},
	Enum.Seed.CARROT: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/carrot_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/carrot_05.png",
		'name':'Carrot',
		'h_frames': 3,
		'grow_speed': 0.4,
		'death_max': 3,
		'reward': Enum.Item.CARROT},
	Enum.Seed.CAULIFLOWER: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cauliflower_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/cauliflower_05.png",
		'name':'Cauiflower',
		'h_frames': 3,
		'grow_speed': 0.5,
		'death_max': 3,
		'reward': Enum.Item.CAULIFLOWER},
	Enum.Seed.POTATO: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/potato_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/potato_05.png",
		'name':'Potato',
		'h_frames': 3,
		'grow_speed': 0.3,
		'death_max': 3,
		'reward': Enum.Item.POTATO},
	Enum.Seed.RADISH: {
		'texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/radish_spritesheet.png",
		'icon_texture': "res://assets/Sunnyside_World_Assets/Elements/Crops/radish_05.png",
		'name':'Radish',
		'h_frames': 3,
		'grow_speed': 0.8,
		'death_max': 3,
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
const TOOL_STATE_ANIMATIONS = {
	Enum.Tool.HOE: 'Hoe',
	Enum.Tool.AXE: 'Axe',
	Enum.Tool.WATER: 'Water',
	Enum.Tool.SWORD: 'Sword',
	Enum.Tool.FISH: 'Fish',
	Enum.Tool.SEED: 'Seed',
	Enum.Tool.HAMMER: 'Hammer',
	}
