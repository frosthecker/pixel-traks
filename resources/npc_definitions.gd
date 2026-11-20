class_name NPCDefinitions extends Resource

## Central registry of all NPC definitions for easy spawning and management

static var NPC_DEFINITIONS: Array[Dictionary] = [
	# === FARMERS & AGRICULTURAL ===
	{
		"id": "john_farmer",
		"name": "John",
		"role": "Farmer",
		"scene": "res://AI/scenes/john.tscn",
		"script": "res://AI/scripts/john.gd",
		"biodata": "res://resources/john_biodata.tres",
		"position": Vector2(100, 100),
		"groq_id": "John",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [100, 100]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [100, 100]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "elara_farmer",
		"name": "Elara",
		"role": "Organic Farmer",
		"scene": "res://AI/scenes/elara.tscn",
		"script": "res://AI/scripts/elara.gd",
		"biodata": "res://resources/elara_biodata.tres",
		"position": Vector2(-150, -150),
		"groq_id": "Elara",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-150, -150]},
			{"activity": "eat", "start": 780, "end": 840},
			{"activity": "work", "start": 840, "end": 1140, "pos": [-150, -150]},
			{"activity": "socialize", "start": 1140, "end": 1260},
			{"activity": "wander", "start": 1260, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "tomas_farmer",
		"name": "Tomas",
		"role": "Veteran Farmer",
		"scene": "res://AI/scenes/tomas.tscn",
		"script": "res://AI/scripts/tomas.gd",
		"biodata": "res://resources/tomas_biodata.tres",
		"position": Vector2(250, 150),
		"groq_id": "Tomas",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 660, "pos": [250, 150]},
			{"activity": "work", "start": 660, "end": 1020, "pos": [250, 150]},
			{"activity": "socialize", "start": 1020, "end": 1140},
			{"activity": "work", "start": 1140, "end": 1320, "pos": [250, 150]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "sarah_beekeeper",
		"name": "Sarah",
		"role": "Beekeeper",
		"scene": "res://AI/scenes/sarah.tscn",
		"script": "res://AI/scripts/sarah.gd",
		"biodata": "res://resources/sarah_biodata.tres",
		"position": Vector2(-100, 200),
		"groq_id": "Sarah",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-100, 200]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1140, "pos": [-100, 200]},
			{"activity": "wander", "start": 1140, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	# === CRAFTERS & ARTISANS ===
	{
		"id": "kaia_blacksmith",
		"name": "Kaia",
		"role": "Blacksmith",
		"scene": "res://AI/scenes/kaia.tscn",
		"script": "res://AI/scripts/kaia.gd",
		"biodata": "res://resources/kaia_biodata.tres",
		"position": Vector2(300, -100),
		"groq_id": "Kaia",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [300, -100]},
			{"activity": "eat", "start": 720, "end": 780},
			{"activity": "work", "start": 780, "end": 1140, "pos": [300, -100]},
			{"activity": "socialize", "start": 1140, "end": 1260},
			{"activity": "work", "start": 1260, "end": 1380, "pos": [350, -150]},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "marcus_weaver",
		"name": "Marcus",
		"role": "Weaver/Tailor",
		"scene": "res://AI/scenes/marcus_weaver.tscn",
		"script": "res://AI/scripts/marcus_weaver.gd",
		"biodata": "res://resources/marcus_weaver_biodata.tres",
		"position": Vector2(50, -180),
		"groq_id": "MarcusWeaver",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [50, -180]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1200, "pos": [50, -180]},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "elena_potter",
		"name": "Elena",
		"role": "Potter",
		"scene": "res://AI/scenes/elena.tscn",
		"script": "res://AI/scripts/elena.gd",
		"biodata": "res://resources/elena_biodata.tres",
		"position": Vector2(-200, -100),
		"groq_id": "Elena",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-200, -100]},
			{"activity": "eat", "start": 780, "end": 840},
			{"activity": "work", "start": 840, "end": 1140, "pos": [-200, -100]},
			{"activity": "socialize", "start": 1140, "end": 1260},
			{"activity": "wander", "start": 1260, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "finn_carpenter",
		"name": "Finn",
		"role": "Carpenter",
		"scene": "res://AI/scenes/finn.tscn",
		"script": "res://AI/scripts/finn.gd",
		"biodata": "res://resources/finn_biodata.tres",
		"position": Vector2(180, 220),
		"groq_id": "Finn",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [180, 220]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [180, 220]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	# === MERCHANTS & TRADERS ===
	{
		"id": "marcus_merchant",
		"name": "Marcus",
		"role": "Merchant",
		"scene": "res://AI/scenes/seller_enhanced.tscn",
		"script": "res://AI/scripts/seller_enhanced.gd",
		"biodata": "res://resources/seller_biodata.tres",
		"position": Vector2(50, 200),
		"groq_id": "Marcus",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 1020, "pos": [50, 200]},
			{"activity": "socialize", "start": 1020, "end": 1140},
			{"activity": "work", "start": 1140, "end": 1260, "pos": [50, 200]},
			{"activity": "wander", "start": 1260, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "lydia_trader",
		"name": "Lydia",
		"role": "Traveling Trader",
		"scene": "res://AI/scenes/lydia.tscn",
		"script": "res://AI/scripts/lydia.gd",
		"biodata": "res://resources/lydia_biodata.tres",
		"position": Vector2(-50, 250),
		"groq_id": "Lydia",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "travel", "start": 360, "end": 540},
			{"activity": "trade", "start": 540, "end": 900, "pos": [-50, 250]},
			{"activity": "travel", "start": 900, "end": 1080},
			{"activity": "trade", "start": 1080, "end": 1320, "pos": [-50, 250]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "omar_exotic",
		"name": "Omar",
		"role": "Exotic Goods Dealer",
		"scene": "res://AI/scenes/omar.tscn",
		"script": "res://AI/scripts/omar.gd",
		"biodata": "res://resources/omar_biodata.tres",
		"position": Vector2(120, 280),
		"groq_id": "Omar",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 480},
			{"activity": "work", "start": 480, "end": 900, "pos": [120, 280]},
			{"activity": "socialize", "start": 900, "end": 1020},
			{"activity": "work", "start": 1020, "end": 1320, "pos": [120, 280]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	# === HEALERS & MYSTICS ===
	{
		"id": "mira_herbalist",
		"name": "Mira",
		"role": "Herbalist",
		"scene": "res://AI/scenes/mira.tscn",
		"script": "res://AI/scripts/mira.gd",
		"biodata": "res://resources/mira_biodata.tres",
		"position": Vector2(120, -80),
		"groq_id": "Mira",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 600, "pos": [120, -80]},
			{"activity": "wander", "start": 600, "end": 720},
			{"activity": "work", "start": 720, "end": 960, "pos": [200, 150]},
			{"activity": "socialize", "start": 960, "end": 1080},
			{"activity": "work", "start": 1080, "end": 1320, "pos": [120, -80]},
			{"activity": "wander", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "brother_thomas",
		"name": "Brother Thomas",
		"role": "Healer Monk",
		"scene": "res://AI/scenes/brother_thomas.tscn",
		"script": "res://AI/scripts/brother_thomas.gd",
		"biodata": "res://resources/brother_thomas_biodata.tres",
		"position": Vector2(-80, -120),
		"groq_id": "BrotherThomas",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 660, "pos": [-80, -120]},
			{"activity": "prayer", "start": 660, "end": 720},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-80, -120]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "zara_mystic",
		"name": "Zara",
		"role": "Fortune Teller",
		"scene": "res://AI/scenes/zara.tscn",
		"script": "res://AI/scripts/zara.gd",
		"biodata": "res://resources/zara_biodata.tres",
		"position": Vector2(0, -250),
		"groq_id": "Zara",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 480},
			{"activity": "meditate", "start": 480, "end": 600},
			{"activity": "work", "start": 600, "end": 1020, "pos": [0, -250]},
			{"activity": "socialize", "start": 1020, "end": 1140},
			{"activity": "work", "start": 1140, "end": 1320, "pos": [0, -250]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	# === FISHERS & HUNTERS ===
	{
		"id": "orin_fisherman",
		"name": "Orin",
		"role": "Fisherman",
		"scene": "res://AI/scenes/orin.tscn",
		"script": "res://AI/scripts/orin.gd",
		"biodata": "res://resources/orin_biodata.tres",
		"position": Vector2(-200, 300),
		"groq_id": "Orin",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 660, "pos": [-200, 300]},
			{"activity": "eat", "start": 660, "end": 720},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-200, 300]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "marina_fisher",
		"name": "Marina",
		"role": "Net Fisher",
		"scene": "res://AI/scenes/marina.tscn",
		"script": "res://AI/scripts/marina.gd",
		"biodata": "res://resources/marina_biodata.tres",
		"position": Vector2(-250, 350),
		"groq_id": "Marina",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [-250, 350]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-250, 350]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "henrik_hunter",
		"name": "Henrik",
		"role": "Hunter/Trapper",
		"scene": "res://AI/scenes/henrik.tscn",
		"script": "res://AI/scripts/henrik.gd",
		"biodata": "res://resources/henrik_biodata.tres",
		"position": Vector2(-300, 100),
		"groq_id": "Henrik",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 660, "pos": [-300, 100]},
			{"activity": "work", "start": 660, "end": 1020, "pos": [-300, 100]},
			{"activity": "socialize", "start": 1020, "end": 1140},
			{"activity": "wander", "start": 1140, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "elsa_gatherer",
		"name": "Elsa",
		"role": "Forager",
		"scene": "res://AI/scenes/elsa.tscn",
		"script": "res://AI/scripts/elsa.gd",
		"biodata": "res://resources/elsa_biodata.tres",
		"position": Vector2(-200, -200),
		"groq_id": "Elsa",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-200, -200]},
			{"activity": "wander", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1200, "pos": [-200, -200]},
			{"activity": "socialize", "start": 1200, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	# === GUARDS & PROTECTORS ===
	{
		"id": "vex_guard",
		"name": "Captain Vex",
		"role": "Island Guard Captain",
		"scene": "res://AI/scenes/guard.tscn",
		"script": "res://AI/scripts/guard.gd",
		"biodata": "res://resources/guard_biodata.tres",
		"position": Vector2(0, -200),
		"groq_id": "Vex",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 540, "pos": [0, -200]},
			{"activity": "work", "start": 540, "end": 780, "pos": [-100, -250]},
			{"activity": "eat", "start": 780, "end": 840},
			{"activity": "work", "start": 840, "end": 1140, "pos": [100, -250]},
			{"activity": "work", "start": 1140, "end": 1320, "pos": [0, -200]},
			{"activity": "socialize", "start": 1320, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "sergeant_briga",
		"name": "Sergeant Briga",
		"role": "Guard Sergeant",
		"scene": "res://AI/scenes/briga.tscn",
		"script": "res://AI/scripts/briga.gd",
		"biodata": "res://resources/briga_biodata.tres",
		"position": Vector2(-50, -220),
		"groq_id": "Briga",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [-50, -220]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [50, -220]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "corporal_tonn",
		"name": "Corporal Tonn",
		"role": "Guard Scout",
		"scene": "res://AI/scenes/tonn.tscn",
		"script": "res://AI/scripts/tonn.gd",
		"biodata": "res://resources/tonn_biodata.tres",
		"position": Vector2(50, -220),
		"groq_id": "Tonn",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [50, -220]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-50, -220]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	# === SCHOLARS & LOREKEEPERS ===
	{
		"id": "thom_elder",
		"name": "Elder Thom",
		"role": "Island Historian",
		"scene": "res://AI/scenes/elder.tscn",
		"script": "res://AI/scripts/elder.gd",
		"biodata": "res://resources/elder_biodata.tres",
		"position": Vector2(-50, -50),
		"groq_id": "Thom",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 660, "pos": [-50, -50]},
			{"activity": "socialize", "start": 660, "end": 900},
			{"activity": "work", "start": 900, "end": 1140, "pos": [-50, -50]},
			{"activity": "wander", "start": 1140, "end": 1260},
			{"activity": "socialize", "start": 1260, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "professor_arwyn",
		"name": "Professor Arwyn",
		"role": "Scholar",
		"scene": "res://AI/scenes/arwyn.tscn",
		"script": "res://AI/scripts/arwyn.gd",
		"biodata": "res://resources/arwyn_biodata.tres",
		"position": Vector2(-120, 50),
		"groq_id": "Arwyn",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-120, 50]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1140, "pos": [-120, 50]},
			{"activity": "wander", "start": 1140, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "scribe_elin",
		"name": "Scribe Elin",
		"role": "Record Keeper",
		"scene": "res://AI/scenes/elin.tscn",
		"script": "res://AI/scripts/elin.gd",
		"biodata": "res://resources/elin_biodata.tres",
		"position": Vector2(-100, 0),
		"groq_id": "Elin",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [-100, 0]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-100, 0]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	# === CHILDREN & YOUTH ===
	{
		"id": "pip_child",
		"name": "Pip",
		"role": "Curious Child",
		"scene": "res://AI/scenes/child.tscn",
		"script": "res://AI/scripts/child.gd",
		"biodata": "res://resources/child_biodata.tres",
		"position": Vector2(0, 50),
		"groq_id": "Pip",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 480},
			{"activity": "wander", "start": 480, "end": 660},
			{"activity": "socialize", "start": 660, "end": 780},
			{"activity": "wander", "start": 780, "end": 1020},
			{"activity": "eat", "start": 1020, "end": 1080},
			{"activity": "wander", "start": 1080, "end": 1260},
			{"activity": "socialize", "start": 1260, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "tiko_child",
		"name": "Tiko",
		"role": "Apprentice",
		"scene": "res://AI/scenes/tiko.tscn",
		"script": "res://AI/scripts/tiko.gd",
		"biodata": "res://resources/tiko_biodata.tres",
		"position": Vector2(30, 80),
		"groq_id": "Tiko",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [300, -100]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1140, "pos": [300, -100]},
			{"activity": "wander", "start": 1140, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "mara_youth",
		"name": "Mara",
		"role": "Fisher's Daughter",
		"scene": "res://AI/scenes/mara.tscn",
		"script": "res://AI/scripts/mara.gd",
		"biodata": "res://resources/mara_biodata.tres",
		"position": Vector2(-180, 320),
		"groq_id": "Mara",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [-200, 300]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1140, "pos": [-200, 300]},
			{"activity": "wander", "start": 1140, "end": 1320},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	# === RIVALS & ANTAGONISTS ===
	{
		"id": "rook_rival",
		"name": "Rook",
		"role": "Competitive Farmer",
		"scene": "res://AI/scenes/rival.tscn",
		"script": "res://AI/scripts/rival.gd",
		"biodata": "res://resources/rival_biodata.tres",
		"position": Vector2(200, 200),
		"groq_id": "Rook",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [200, 200]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [200, 200]},
			{"activity": "socialize", "start": 1080, "end": 1140},
			{"activity": "work", "start": 1140, "end": 1320, "pos": [200, 200]},
			{"activity": "wander", "start": 1320, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "viktor_rival",
		"name": "Viktor",
		"role": "Rival Merchant",
		"scene": "res://AI/scenes/viktor.tscn",
		"script": "res://AI/scripts/viktor.gd",
		"biodata": "res://resources/viktor_biodata.tres",
		"position": Vector2(80, 180),
		"groq_id": "Viktor",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 900, "pos": [80, 180]},
			{"activity": "socialize", "start": 900, "end": 1020},
			{"activity": "work", "start": 1020, "end": 1320, "pos": [80, 180]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "serafina_rival",
		"name": "Serafina",
		"role": "Rival Artisan",
		"scene": "res://AI/scenes/serafina.tscn",
		"script": "res://AI/scripts/serafina.gd",
		"biodata": "res://resources/serafina_biodata.tres",
		"position": Vector2(-150, 80),
		"groq_id": "Serafina",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [-150, 80]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-150, 80]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	# === UNIQUE ROLES ===
	{
		"id": "captain_reef",
		"name": "Captain Reef",
		"role": "Harbor Master",
		"scene": "res://AI/scenes/captain_reef.tscn",
		"script": "res://AI/scripts/captain_reef.gd",
		"biodata": "res://resources/captain_reef_biodata.tres",
		"position": Vector2(-150, 400),
		"groq_id": "CaptainReef",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 360},
			{"activity": "work", "start": 360, "end": 720, "pos": [-150, 400]},
			{"activity": "work", "start": 720, "end": 1080, "pos": [-150, 400]},
			{"activity": "socialize", "start": 1080, "end": 1200},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
	
	{
		"id": "chef_bonnie",
		"name": "Chef Bonnie",
		"role": "Cook/Restaurateur",
		"scene": "res://AI/scenes/bonnie.tscn",
		"script": "res://AI/scripts/bonnie.gd",
		"biodata": "res://resources/bonnie_biodata.tres",
		"position": Vector2(20, 100),
		"groq_id": "Bonnie",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 660, "pos": [20, 100]},
			{"activity": "work", "start": 660, "end": 900, "pos": [20, 100]},
			{"activity": "socialize", "start": 900, "end": 1140},
			{"activity": "work", "start": 1140, "end": 1320, "pos": [20, 100]},
			{"activity": "sleep", "start": 1320, "end": 1440},
		],
	},
	
	{
		"id": "miner_grundy",
		"name": "Grundy",
		"role": "Deep Miner",
		"scene": "res://AI/scenes/grundy.tscn",
		"script": "res://AI/scripts/grundy.gd",
		"biodata": "res://resources/grundy_biodata.tres",
		"position": Vector2(400, -200),
		"groq_id": "Grundy",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 300},
			{"activity": "work", "start": 300, "end": 720, "pos": [400, -200]},
			{"activity": "work", "start": 720, "end": 1140, "pos": [400, -200]},
			{"activity": "socialize", "start": 1140, "end": 1260},
			{"activity": "sleep", "start": 1260, "end": 1440},
		],
	},
	
	{
		"id": "engineer_plex",
		"name": "Plex",
		"role": "Tinkerer/Engineer",
		"scene": "res://AI/scenes/plex.tscn",
		"script": "res://AI/scripts/plex.gd",
		"biodata": "res://resources/plex_biodata.tres",
		"position": Vector2(250, -180),
		"groq_id": "Plex",
		"schedule": [
			{"activity": "sleep", "start": 0, "end": 420},
			{"activity": "work", "start": 420, "end": 780, "pos": [250, -180]},
			{"activity": "socialize", "start": 780, "end": 900},
			{"activity": "work", "start": 900, "end": 1200, "pos": [250, -180]},
			{"activity": "wander", "start": 1200, "end": 1380},
			{"activity": "sleep", "start": 1380, "end": 1440},
		],
	},
]

static func get_all_definitions() -> Array[Dictionary]:
	return NPC_DEFINITIONS

static func get_definition(id: String) -> Dictionary:
	for def in NPC_DEFINITIONS:
		if def["id"] == id:
			return def
	return {}

static func get_definitions_by_role(role: String) -> Array[Dictionary]:
	var results := []
	for def in NPC_DEFINITIONS:
		if def["role"] == role:
			results.append(def)
	return results

static func get_spawn_positions() -> Array[Vector2]:
	var positions := []
	for def in NPC_DEFINITIONS:
		positions.append(def["position"])
	return positions