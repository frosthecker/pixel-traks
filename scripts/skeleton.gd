extends CharacterBody2D

enum Mode { WANDER, CHASE }

@export var chase_speed := 40.0
@export var wander_speed := 16.0
@export var chase_radius := 220.0
@export var attack_range := 18.0
@export var attack_damage := 1
@export var attack_cooldown := 1.2
@export var attack_windup := 0.4
@export var flank_radius := 100.0
@export var flank_orbit := 55.0
@export var despawn_distance := 640.0

var direction: Vector2
var speed := 20.0
var push_speed := 300.0  # Speed at which enemy is knocked back (pixels/sec)
var knockback_velocity: Vector2 = Vector2.ZERO
@onready var player = get_tree().get_first_node_in_group('Player')
@onready var level = get_tree().get_first_node_in_group('Level')
@onready var sprite_2d: AnimatedSprite2D = $Sprite2D
var health := 4:
	set(value):
		health = value
		if health <= 0:
			death()

var mode := Mode.WANDER
var dead := false
var attacking := false
var attack_id := 0
var attack_ready_at := 0.0
var think_elapsed := 0.0
var wander_elapsed := 0.0
var wander_direction := Vector2.ZERO


func _ready() -> void:
	add_to_group("Objects")
	add_to_group("Skeletons")
	think_elapsed = randf() * 0.25


func _physics_process(delta: float) -> void:
	if dead:
		velocity = knockback_velocity
		move_and_slide()
		return
	if player == null:
		player = get_tree().get_first_node_in_group('Player')
		if player == null:
			return

	think_elapsed -= delta
	if think_elapsed <= 0.0:
		think_elapsed = 0.25
		_think()
		if is_queued_for_deletion():
			return

	var to_player: Vector2 = player.global_position - global_position
	var now := Time.get_ticks_msec() / 1000.0
	if not attacking and now >= attack_ready_at and to_player.length() <= attack_range:
		_attack()

	direction = _desired_direction(delta, to_player)

	# Flip sprite depending on moving left or right
	if direction.x != 0:
		sprite_2d.flip_h = direction.x < 0

	# Standard movement velocity (zero out if hurt or dead)
	var move_velocity := Vector2.ZERO
	if not (sprite_2d.animation in ["hurt", "death"] and sprite_2d.is_playing()):
		if attacking:
			if sprite_2d.sprite_frames.has_animation("attack"):
				sprite_2d.play("attack")
			else:
				sprite_2d.play('idle')
		elif direction:
			sprite_2d.play('walk')
		else:
			sprite_2d.play('idle')
		move_velocity = direction * speed

	# Combine normal walk velocity with knockback force
	velocity = move_velocity + knockback_velocity
	move_and_slide()


func _think() -> void:
	var distance: float = global_position.distance_to(player.global_position)
	if distance > despawn_distance:
		queue_free()
		return
	mode = Mode.CHASE if distance <= chase_radius else Mode.WANDER


func _desired_direction(delta: float, to_player: Vector2) -> Vector2:
	if attacking:
		speed = 0.0
		return Vector2.ZERO
	if mode == Mode.CHASE:
		var distance := to_player.length()
		if distance <= attack_range * 0.7:
			speed = 0.0
			return Vector2.ZERO
		speed = chase_speed
		var facing_value: Variant = player.get("last_direction")
		var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
		facing = facing.normalized() if facing != Vector2.ZERO else Vector2.DOWN
		var from_player := -to_player / maxf(distance, 0.001)
		if from_player.dot(facing) > 0.35 and distance < flank_radius:
			var side := signf(facing.cross(from_player))
			if side == 0.0:
				side = 1.0
			var tangent := from_player.rotated(side * PI / 2.0)
			var radial := (flank_orbit - distance) / flank_orbit
			return (tangent + from_player * radial * 0.8).normalized()
		return to_player.normalized()
	wander_elapsed -= delta
	if wander_elapsed <= 0.0:
		wander_elapsed = randf_range(1.2, 3.0)
		wander_direction = Vector2.from_angle(randf() * TAU) if randf() < 0.85 else Vector2.ZERO
	speed = wander_speed
	return wander_direction


func _attack() -> void:
	attacking = true
	attack_id += 1
	var this_attack := attack_id
	sprite_2d.flip_h = player.global_position.x < global_position.x
	await get_tree().create_timer(attack_windup).timeout
	if dead or this_attack != attack_id:
		return
	if level == null:
		level = get_tree().get_first_node_in_group('Level')
	var in_reach: bool = global_position.distance_to(player.global_position) <= attack_range * 1.5
	if in_reach and level != null:
		level.damage_player(attack_damage, global_position)
		_lunge((player.global_position - global_position).normalized() * 110.0)
	attack_ready_at = Time.get_ticks_msec() / 1000.0 + attack_cooldown
	await get_tree().create_timer(0.2).timeout
	if not dead and this_attack == attack_id:
		attacking = false


func _lunge(vector: Vector2) -> void:
	knockback_velocity = vector
	create_tween().tween_property(self, "knockback_velocity", Vector2.ZERO, 0.15)


func push() -> void:
	var target_knockback = (global_position - player.global_position).normalized() * push_speed
	var tween = get_tree().create_tween()
	# Instantly apply knockback force, then smoothly decay back to Vector2.ZERO over 0.2 seconds
	knockback_velocity = target_knockback
	tween.tween_property(self, "knockback_velocity", Vector2.ZERO, 0.2)

func death():
	if dead:
		return
	dead = true
	speed = 0
	attacking = false
	collision_layer = 0
	remove_from_group("Skeletons")
	remove_from_group("Objects")
	sprite_2d.play("death")
	# Connect to animation_finished and check if the finished animation is "death"
	if not sprite_2d.animation_finished.is_connected(_on_animation_finished):
		sprite_2d.animation_finished.connect(_on_animation_finished)
	
	
func hit(tool: Enum.Tool) -> void:
	if dead:
		return
	if tool == Enum.Tool.SWORD:
		attacking = false
		attack_id += 1
		attack_ready_at = Time.get_ticks_msec() / 1000.0 + 0.6
		sprite_2d.play("hurt")
		push()
		health -= 1

func _on_animation_finished() -> void:
	if sprite_2d.animation == "death":
		queue_free()
