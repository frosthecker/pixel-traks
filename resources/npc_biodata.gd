class_name NPCBiodata extends Resource

@export var display_name: String = ""
@export_multiline var personality: String = ""
@export var movement_speed: float = 25.0
@export var daily_schedule: Array[Dictionary] = []
@export var favorite_locations: Array[Vector2] = []
@export var relationship_values: Dictionary = {}
@export var current_mood: StringName = &"neutral"

## Social behavior traits
@export var social_traits: Dictionary = {
	"friendliness": 50,      # 0-100: base friendliness to strangers
	"trustfulness": 50,      # 0-100: how easily they trust
	"generosity": 50,        # 0-100: willingness to give gifts/trade fairly
	"loyalty": 50,           # 0-100: commitment to friends
	"competitiveness": 50,   # 0-100: drive to compete
	"aggressiveness": 20,    # 0-100: tendency toward conflict
	"curiosity": 50,         # 0-100: interest in rumors/secrets
	"extraversion": 50,      # 0-100: social energy level
}

## Skill affinities (affect work efficiency)
@export var skill_affinities: Dictionary = {
	"farming": 1.0,
	"mining": 1.0,
	"fishing": 1.0,
	"combat": 1.0,
	"social": 1.0,
	"crafting": 1.0,
}

## Memory and learning
@export var memory_retention: float = 1.0      # Multiplier for memory decay
@export var learning_rate: float = 1.0         # How fast they learn facts/skills
@export var grudge_holding: float = 0.5        # How long they hold grudges (0-1)
@export var forgiveness: float = 0.5            # How easily they forgive (0-1)

## Home and territory
@export var home_location: Vector2 = Vector2.ZERO
@export var territory_radius: float = 200.0
@export var preferred_work_locations: Array[Vector2] = []

## Dialogue style
@export var speech_patterns: Array[String] = []  # Custom phrases, accents, etc.
@export var preferred_topics: Array[String] = []  # Topics they like discussing
@export var avoided_topics: Array[String] = []    # Topics they dislike
