extends CharacterBody3D
## Independent Battle Royale NPC: parachute, loot, patrol, free-for-all combat,
## flee/cover, vision + hearing, and distance-culled thinking.
## VisualHolder drives the shared rigged character's Idle/Walk AnimationPlayer.

signal died(enemy: Node3D)
signal health_changed(health: float)

enum State { PARACHUTE, LOOTING, PATROLLING, COMBAT, FLEEING, DEAD }

const ASSETS := preload("res://scripts/assets.gd")
const CHARACTERS := preload("res://scripts/character_data.gd")
const ANIMATED_CHARACTER_PATH := "res://assets/models/characters/player_animated.glb"

@export_group("Stats")
@export var max_health: float = 200.0
@export var move_speed: float = 2.6
@export var flee_speed: float = 4.0
@export var gravity: float = 18.0
@export var parachute_fall_speed: float = 7.0

@export_group("Independent Mind")
@export var vision_range: float = 40.0
@export var vision_half_angle_deg: float = 75.0
@export var hearing_range: float = 50.0
@export var full_ai_distance: float = 150.0
@export var think_interval: float = 0.4
@export var loot_search_seconds: float = 10.0
@export var loot_grace_seconds: float = 30.0

@export_group("Combat")
@export var npc_damage: float = 25.0
@export var shoot_range: float = 36.0
@export var fire_interval: float = 0.75
@export var aim_error: float = 0.18

@export_group("Body")
@export var show_name: bool = true
@export var show_health_bar: bool = true
@export var flash_time: float = 0.12
@export var animation_speed: float = 7.0

@onready var wall_check: RayCast3D = $WallCheck
@onready var visual_holder = $VisualHolder

var npc_id: int = 0
var health: float = 200.0
var is_dead: bool = false
var state: int = State.PARACHUTE
var armed: bool = false
var weapon_name: String = "Unarmed"
var target: Node3D = null
var last_attacker: Node = null
var shots_fired: int = 0
var shots_hit: int = 0
var brain_ticks: int = 0
var vision_checks: int = 0
var full_ai_ticks: int = 0
var culled_ticks: int = 0
var full_ai_active: bool = false
var is_suspicious: bool = false
var footstep_audio: AudioStreamPlayer3D = null
var shoot_audio: AudioStreamPlayer3D = null

var _player = null
var _rng := RandomNumberGenerator.new()
var _landing_elapsed: float = 0.0
var _search_elapsed: float = 0.0
var _state_time: float = 0.0
var _think_timer: float = 0.0
var _attack_timer: float = 0.0
var _target_lost_time: float = 0.0
var _patrol_timer: float = 0.0
var _suspicion_timer: float = 0.0
var _step_timer: float = 0.0
var _flash_timer: float = 0.0
var _tracer_life: float = 0.0
var _avoid_side: float = 1.0
var _patrol_target: Vector3 = Vector3.ZERO
var _sound_target: Vector3 = Vector3.ZERO
var _flee_target: Vector3 = Vector3.ZERO
var _has_patrol_target: bool = false
var _has_flee_target: bool = false
var _loot_target = null
var _loot_retarget_timer: float = 0.0
var _drop_drift: Vector3 = Vector3.ZERO

var _vision_query: PhysicsRayQueryParameters3D = null
var _shot_query: PhysicsRayQueryParameters3D = null
var _gun_visual: MeshInstance3D = null
var _tracer: MeshInstance3D = null
var _parachute_visual: MeshInstance3D = null

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _body: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _walk_phase: float = 0.0
var _moving: bool = false
var _has_limbs: bool = false
var _character_name: String = ""
var _health_bar_root: Node3D = null
var _health_fill: MeshInstance3D = null


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("br_combatant")
	health = max_health
	_rng.seed = 9173 + npc_id * 7919
	_avoid_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_drop_drift = Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
	_think_timer = _rng.randf_range(0.02, think_interval)
	_vision_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD)
	_vision_query.collision_mask = 1 | 2 | 4
	_vision_query.exclude = [get_rid()]
	_shot_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD)
	_shot_query.collision_mask = 1 | 2 | 4
	_shot_query.exclude = [get_rid()]
	wall_check.enabled = false

	_setup_audio()
	_setup_combat_visuals()
	_build_body()
	_build_health_bar()
	_find_player()


func _setup_audio() -> void:
	footstep_audio = AudioStreamPlayer3D.new()
	footstep_audio.name = "FootstepAudio"
	footstep_audio.stream = preload("res://assets/sounds/footstep.wav")
	footstep_audio.max_polyphony = 2
	footstep_audio.volume_db = -7.0
	footstep_audio.unit_size = 5.0
	footstep_audio.max_distance = 35.0
	add_child(footstep_audio)

	shoot_audio = AudioStreamPlayer3D.new()
	shoot_audio.name = "ShootAudio"
	shoot_audio.stream = preload("res://assets/sounds/shoot.wav")
	shoot_audio.max_polyphony = 3
	shoot_audio.volume_db = -10.0
	shoot_audio.unit_size = 8.0
	shoot_audio.max_distance = 65.0
	add_child(shoot_audio)


func _setup_combat_visuals() -> void:
	var gun_material := StandardMaterial3D.new()
	gun_material.albedo_color = Color(0.12, 0.14, 0.16)
	gun_material.metallic = 0.55
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.13, 0.13, 0.68)
	gun_mesh.material = gun_material
	_gun_visual = MeshInstance3D.new()
	_gun_visual.name = "GenericGun"
	_gun_visual.mesh = gun_mesh
	_gun_visual.position = Vector3(0.32, 1.25, -0.32)
	_gun_visual.visible = false
	visual_holder.add_child(_gun_visual)

	var tracer_material := StandardMaterial3D.new()
	tracer_material.albedo_color = Color(1.0, 0.76, 0.18)
	tracer_material.emission_enabled = true
	tracer_material.emission = Color(1.0, 0.48, 0.08)
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.025, 0.025, 1.0)
	tracer_mesh.material = tracer_material
	_tracer = MeshInstance3D.new()
	_tracer.name = "ReusableTracer"
	_tracer.mesh = tracer_mesh
	_tracer.visible = false
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer.set_as_top_level(true)
	add_child(_tracer)

	var chute_material := StandardMaterial3D.new()
	chute_material.albedo_color = Color(0.85, 0.28, 0.16)
	var chute_mesh := CylinderMesh.new()
	chute_mesh.top_radius = 1.4
	chute_mesh.bottom_radius = 0.35
	chute_mesh.height = 0.45
	chute_mesh.radial_segments = 8
	chute_mesh.material = chute_material
	_parachute_visual = MeshInstance3D.new()
	_parachute_visual.name = "ParachuteCanopy"
	_parachute_visual.mesh = chute_mesh
	_parachute_visual.position.y = 2.65
	add_child(_parachute_visual)


func _process(_delta: float) -> void:
	if visual_holder == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	visual_holder.set_motion(horizontal_speed, velocity.y, is_on_floor(), move_speed)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_timed_visuals(delta)
	if state == State.PARACHUTE:
		_update_parachute(delta)
		return

	if _player == null or not is_instance_valid(_player):
		_find_player()
	# Only distance checks run every tick for distant NPCs. Their target scans,
	# vision rays, wall avoidance, loot searches, and combat are fully culled.
	full_ai_active = _player == null or global_position.distance_to(_player.global_position) <= full_ai_distance
	wall_check.enabled = full_ai_active
	if not full_ai_active:
		culled_ticks += 1
		if state == State.COMBAT:
			_set_state(State.PATROLLING)
		target = null
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	full_ai_ticks += 1
	_landing_elapsed += delta
	_state_time += delta
	_patrol_timer -= delta
	_attack_timer -= delta
	_loot_retarget_timer -= delta
	if is_suspicious:
		_suspicion_timer -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = think_interval + _rng.randf_range(0.0, 0.08)
		_think()

	var move_dir := Vector3.ZERO
	var speed := move_speed
	match state:
		State.LOOTING:
			move_dir = _update_looting(delta)
		State.PATROLLING:
			move_dir = _update_patrolling()
		State.COMBAT:
			move_dir = _update_combat()
		State.FLEEING:
			move_dir = _update_fleeing()
			speed = flee_speed

	_move_character(move_dir, speed, delta)
	_update_footsteps(delta)


func _update_timed_visuals(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)
	if _tracer_life > 0.0:
		_tracer_life -= delta
		if _tracer_life <= 0.0 and _tracer != null:
			_tracer.visible = false


func _update_parachute(delta: float) -> void:
	full_ai_active = false
	wall_check.enabled = false
	velocity.x = _drop_drift.x
	velocity.z = _drop_drift.z
	velocity.y = maxf(velocity.y - gravity * delta, -parachute_fall_speed)
	move_and_slide()
	if is_on_floor():
		complete_landing()


func complete_landing() -> void:
	if is_dead:
		return
	velocity = Vector3.ZERO
	_parachute_visual.visible = false
	_landing_elapsed = 0.0
	_search_elapsed = 0.0
	_set_state(State.LOOTING)
	_find_nearest_loot()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	_state_time = 0.0


func _think() -> void:
	brain_ticks += 1
	if state == State.FLEEING or _landing_elapsed < loot_grace_seconds:
		return
	var visible_target := _find_visible_target()
	if visible_target != null:
		target = visible_target
		_target_lost_time = 0.0
		is_suspicious = false
		_set_state(State.COMBAT)
	elif state == State.COMBAT:
		_target_lost_time += think_interval
		if not _valid_target(target) or _target_lost_time >= 2.0:
			target = null
			_set_state(State.PATROLLING)


func _find_visible_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance := vision_range
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for candidate in get_tree().get_nodes_in_group("br_combatant"):
		if candidate == self or not (candidate is Node3D):
			continue
		if candidate.is_queued_for_deletion() or bool(candidate.get("is_dead")):
			continue
		var body := candidate as Node3D
		var offset := body.global_position - global_position
		var distance := offset.length()
		if distance > best_distance or distance < 0.01:
			continue
		if candidate != target or state != State.COMBAT:
			var flat_offset := Vector3(offset.x, 0.0, offset.z).normalized()
			if forward.dot(flat_offset) < cos(deg_to_rad(vision_half_angle_deg)):
				continue
		if not _has_line_of_sight(body):
			continue
		best_target = body
		best_distance = distance
	return best_target


func _has_line_of_sight(candidate: Node3D) -> bool:
	if candidate == null:
		return false
	var origin := _head_position()
	var target_point := _target_head_position(candidate)
	_vision_query.from = origin
	# Extend through the capsule instead of stopping exactly inside it; this
	# matches the shot query and avoids endpoint-dependent empty LOS results.
	_vision_query.to = target_point + (target_point - origin).normalized() * 0.75
	_vision_query.collide_with_bodies = true
	vision_checks += 1
	var hit := get_world_3d().direct_space_state.intersect_ray(_vision_query)
	return not hit.is_empty() and hit.get("collider") == candidate


func _head_position() -> Vector3:
	return global_position + Vector3(0.0, 1.45, 0.0)


func _target_head_position(candidate: Node3D) -> Vector3:
	var head := candidate.get_node_or_null("Head") as Node3D
	if head != null:
		return head.global_position
	return candidate.global_position + Vector3(0.0, 1.25, 0.0)


func _valid_target(candidate: Node3D) -> bool:
	return candidate != null and is_instance_valid(candidate) \
		and not candidate.is_queued_for_deletion() and not bool(candidate.get("is_dead"))


func _update_looting(delta: float) -> Vector3:
	_search_elapsed += delta
	if armed:
		_set_state(State.PATROLLING)
		return Vector3.ZERO
	if _search_elapsed >= loot_search_seconds:
		_arm("Generic Rifle")
		return Vector3.ZERO

	if _loot_target != null and (not is_instance_valid(_loot_target) or bool(_loot_target.get("consumed"))):
		_loot_target = null
	if _loot_target == null or _loot_retarget_timer <= 0.0:
		_find_nearest_loot()
	if _loot_target != null and is_instance_valid(_loot_target):
		var offset: Vector3 = _loot_target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= 1.7:
			if _loot_target.has_method("consume") and _loot_target.consume():
				_arm(String(_loot_target.get("weapon_name")))
			_loot_target = null
			return Vector3.ZERO
		return offset.normalized()

	# No reachable loot found yet: search locally until the 10 s fallback.
	if not _has_patrol_target or _patrol_timer <= 0.0:
		_choose_patrol_target()
	return _direction_to(_patrol_target)


func _find_nearest_loot() -> void:
	_loot_retarget_timer = 1.0
	var best_distance := INF
	_loot_target = null
	for loot in get_tree().get_nodes_in_group("loot_weapon"):
		if not (loot is Node3D) or bool(loot.get("consumed")):
			continue
		var distance := global_position.distance_squared_to(loot.global_position)
		if distance < best_distance:
			best_distance = distance
			_loot_target = loot


func _arm(new_weapon_name: String) -> void:
	armed = true
	weapon_name = new_weapon_name
	_gun_visual.visible = true
	_loot_target = null
	_choose_patrol_target()
	_set_state(State.PATROLLING)


func _update_patrolling() -> Vector3:
	if is_suspicious and _suspicion_timer > 0.0:
		if _flat_distance_to(_sound_target) > 2.0:
			return _direction_to(_sound_target)
		is_suspicious = false
	if not _has_patrol_target or _patrol_timer <= 0.0 or _flat_distance_to(_patrol_target) < 2.0:
		_choose_patrol_target()
	return _direction_to(_patrol_target)


func _choose_patrol_target() -> void:
	if _rng.randf() < 0.25:
		_patrol_target = Vector3(0.0, global_position.y, 0.0)
	else:
		_patrol_target = Vector3(
			clampf(global_position.x + _rng.randf_range(-24.0, 24.0), -900.0, 900.0),
			global_position.y,
			clampf(global_position.z + _rng.randf_range(-24.0, 24.0), -900.0, 900.0)
		)
	_has_patrol_target = true
	_patrol_timer = _rng.randf_range(5.0, 9.0)


func _update_combat() -> Vector3:
	if not _valid_target(target):
		target = null
		_set_state(State.PATROLLING)
		return Vector3.ZERO
	_face_position(target.global_position)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if _attack_timer <= 0.0 and distance <= shoot_range and _has_line_of_sight(target):
		_shoot_at_target()
		_attack_timer = fire_interval
	if distance > shoot_range * 0.75:
		return offset.normalized()
	if distance < 5.0:
		return -offset.normalized()
	return Vector3.ZERO


func _shoot_at_target() -> void:
	if not armed or not _valid_target(target):
		return
	var origin := _head_position()
	var aim_point := _target_head_position(target)
	aim_point += Vector3(
		_rng.randf_range(-aim_error, aim_error),
		_rng.randf_range(-aim_error, aim_error),
		_rng.randf_range(-aim_error, aim_error)
	)
	var direction := (aim_point - origin).normalized()
	_shot_query.from = origin
	_shot_query.to = origin + direction * shoot_range
	var hit := get_world_3d().direct_space_state.intersect_ray(_shot_query)
	var end_point: Vector3 = _shot_query.to
	if not hit.is_empty():
		end_point = hit["position"]
		var collider = hit.get("collider")
		if collider is Node and collider.is_in_group("br_combatant"):
			if collider.is_in_group("enemy"):
				collider.take_damage(npc_damage, self)
			elif collider.is_in_group("player"):
				collider.take_damage(int(npc_damage))
			shots_hit += 1

	shots_fired += 1
	_show_tracer(origin, end_point)
	shoot_audio.play()
	# Gunshots are perception events, not physical bullet nodes.
	get_tree().call_group("enemy", "hear_gunshot", global_position, self)


func _show_tracer(origin: Vector3, end_point: Vector3) -> void:
	var length := origin.distance_to(end_point)
	if length <= 0.01:
		return
	_tracer.global_position = (origin + end_point) * 0.5
	_tracer.look_at(end_point, Vector3.UP)
	_tracer.scale = Vector3(1.0, 1.0, length)
	_tracer.visible = true
	_tracer_life = 0.07


func hear_gunshot(source_position: Vector3, source: Node) -> void:
	if is_dead or source == self or state == State.PARACHUTE:
		return
	if global_position.distance_to(source_position) > hearing_range:
		return
	if state == State.COMBAT or state == State.FLEEING or _landing_elapsed < loot_grace_seconds:
		return
	# Suspicious is a PATROLLING sub-state, preserving the required six-state enum.
	is_suspicious = true
	_suspicion_timer = 5.0
	_sound_target = source_position
	_face_position(source_position)
	_set_state(State.PATROLLING)


func _update_fleeing() -> Vector3:
	if not _has_flee_target:
		_choose_cover_point()
	var attacker_body := last_attacker as Node3D
	if _state_time >= 4.0 and (attacker_body == null \
		or global_position.distance_to(attacker_body.global_position) > 35.0):
		_set_state(State.PATROLLING)
		return Vector3.ZERO
	if _flat_distance_to(_flee_target) < 1.5:
		_choose_cover_point()
	return _direction_to(_flee_target)


func _choose_cover_point() -> void:
	var away := Vector3(1.0, 0.0, 0.0)
	if last_attacker != null and is_instance_valid(last_attacker):
		away = global_position - last_attacker.global_position
		away.y = 0.0
		away = away.normalized()
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	_flee_target = global_position + away * 18.0
	if last_attacker is Node3D:
		var attacker_head := _target_head_position(last_attacker as Node3D)
		for i in range(-3, 4):
			var candidate := global_position + away.rotated(Vector3.UP, float(i) * 0.28) * 14.0
			var query := PhysicsRayQueryParameters3D.create(
				attacker_head, candidate + Vector3(0.0, 1.2, 0.0)
			)
			query.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				_flee_target = candidate
				break
	_has_flee_target = true


func _move_character(move_dir: Vector3, speed: float, delta: float) -> void:
	_apply_gravity(delta)
	_moving = move_dir.length_squared() > 0.01
	if _moving:
		_face_position(global_position + move_dir)
		if wall_check.is_colliding():
			move_dir = move_dir.rotated(Vector3.UP, deg_to_rad(55.0) * _avoid_side)
	_animate_limbs(delta)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _face_position(point: Vector3) -> void:
	var look_target := Vector3(point.x, global_position.y, point.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)


func _direction_to(point: Vector3) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	return offset.normalized()


func _flat_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _update_footsteps(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or ground_speed <= 0.1:
		_step_timer = 0.0
		return
	_step_timer += delta
	if _step_timer >= 0.5:
		_step_timer = fmod(_step_timer, 0.5)
		footstep_audio.play()


func _find_player() -> void:
	var list := get_tree().get_nodes_in_group("player")
	_player = list[0] if list.size() > 0 else null
	if _player != null and not _player.is_in_group("br_combatant"):
		_player.add_to_group("br_combatant")
	if wall_check != null and _player is CollisionObject3D:
		wall_check.add_exception(_player)


func _build_body() -> void:
	# Every NPC uses the same real rigged character as the human; independent
	# AI/state remains in this controller while VisualHolder plays Idle/Walk.
	var model := _load_animated_character()
	if model == null:
		var pick: String = CHARACTERS.ENEMY_POOL[_rng.randi() % CHARACTERS.ENEMY_POOL.size()]
		model = ASSETS.build_character_model(
			pick, Color(0.60, 0.20, 0.18), Color(0.30, 0.12, 0.12), CHARACTERS.ENEMY_TINT
		)
		if model == null:
			model = ASSETS.fallback_character(
				Color(0.60, 0.20, 0.18), Color(0.30, 0.12, 0.12), CHARACTERS.ENEMY_TINT
			)
		_character_name = pick.capitalize().replace("_", " ")
	model.name = "Body"
	ASSETS.fit_to_height(model, CHARACTERS.ENEMY_HEIGHT)
	visual_holder.add_child(model)
	visual_holder.register_character(model)
	_body = model
	if _character_name.is_empty():
		_character_name = "Dushman"
	if show_name:
		_add_name_tag(model)
	_collect_flash_materials(model)


func _load_animated_character() -> Node3D:
	if not ResourceLoader.exists(ANIMATED_CHARACTER_PATH):
		return null
	var resource := ResourceLoader.load(ANIMATED_CHARACTER_PATH)
	if not (resource is PackedScene):
		return null
	var instance := (resource as PackedScene).instantiate()
	if not (instance is Node3D):
		instance.free()
		return null
	var model := instance as Node3D
	model.set_meta("real_glb", true)
	model.set_meta("asset_path", ANIMATED_CHARACTER_PATH)
	return model


func _add_name_tag(parent: Node3D) -> void:
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = _character_name
	label.font_size = 40
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.55, 0.50)
	label.outline_size = 8
	label.outline_modulate = Color(0.10, 0.02, 0.02, 0.9)
	label.position = Vector3(0.0, CHARACTERS.ENEMY_HEIGHT + 0.30, 0.0)
	parent.add_child(label)


func _collect_flash_materials(node: Node3D) -> void:
	for mesh_node in ASSETS.collect_meshes(node):
		var override: Material = mesh_node.material_override
		if override is StandardMaterial3D:
			_materials.append(override as StandardMaterial3D)
			_base_colors.append((override as StandardMaterial3D).albedo_color)
			continue
		var surfaces := 1
		if mesh_node.mesh != null:
			surfaces = maxi(1, mesh_node.mesh.get_surface_count())
		for i in surfaces:
			var mat: Material = mesh_node.get_active_material(i)
			if mat is StandardMaterial3D:
				_materials.append(mat as StandardMaterial3D)
				_base_colors.append((mat as StandardMaterial3D).albedo_color)


func _build_health_bar() -> void:
	_health_bar_root = Node3D.new()
	_health_bar_root.name = "HealthBar"
	_health_bar_root.position = Vector3(0.0, CHARACTERS.ENEMY_HEIGHT + 0.12, 0.0)
	add_child(_health_bar_root)
	_make_health_quad("Background", Vector2(0.88, 0.095), Color(0.08, 0.025, 0.025))
	_health_fill = _make_health_quad("Fill", Vector2(0.82, 0.060), Color(0.20, 0.90, 0.32))
	_health_fill.position.z = 0.002
	_update_health_bar()


func _make_health_quad(node_name: String, quad_size: Vector2, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	mesh.material = material
	var quad := MeshInstance3D.new()
	quad.name = node_name
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_health_bar_root.add_child(quad)
	return quad


func _update_health_bar() -> void:
	if _health_bar_root == null or _health_fill == null:
		return
	var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	_health_fill.scale.x = ratio
	_health_fill.visible = ratio > 0.0
	_health_bar_root.visible = show_health_bar and not is_dead


func _animate_limbs(delta: float) -> void:
	if _body == null or not _has_limbs:
		return
	var speed := animation_speed if _moving else 1.6
	_walk_phase += delta * speed
	var leg_swing := sin(_walk_phase) * (0.55 if _moving else 0.05)
	var arm_swing := -leg_swing * 0.7
	_leg_l.rotation.x = leg_swing
	_leg_r.rotation.x = -leg_swing
	_arm_l.rotation.x = arm_swing
	_arm_r.rotation.x = -arm_swing


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_dead:
		return
	if attacker != null and attacker != self:
		last_attacker = attacker
	health = maxf(0.0, health - amount)
	_update_health_bar()
	health_changed.emit(health)
	_set_flash(true)
	_flash_timer = flash_time
	if health <= 0.0:
		die()
	elif health <= max_health * 0.20 and state != State.PARACHUTE:
		if not armed:
			_arm("Scavenged Rifle")
		_has_flee_target = false
		_choose_cover_point()
		_set_state(State.FLEEING)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	_set_state(State.DEAD)
	target = null
	velocity = Vector3.ZERO
	_gun_visual.visible = false
	_parachute_visual.visible = false
	_tracer.visible = false
	_update_health_bar()
	died.emit(self)
	queue_free()


func _set_flash(on: bool) -> void:
	for i in _materials.size():
		var mat: StandardMaterial3D = _materials[i]
		mat.albedo_color = Color(1.0, 0.3, 0.25) if on else _base_colors[i]
		mat.emission_enabled = on
		if on:
			mat.emission = Color(1.0, 0.25, 0.2)
