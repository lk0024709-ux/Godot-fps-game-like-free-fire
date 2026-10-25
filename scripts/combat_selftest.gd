extends Node3D
## Focused live-physics regression test for TPV, balanced HP, hitscan and VFX pools.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const CHARACTERS := preload("res://scripts/character_data.gd")

var _player = null
var _enemy = null
var _frame: int = 0
var _done: bool = false
var _checks: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	_make_box("Ground", Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	# A real wall behind the player verifies SpringArm3D collision shortening.
	_make_box("CameraWall", Vector3(0.0, 1.5, 2.0), Vector3(5.0, 4.0, 0.25))

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.set_physics_process(false)

	_enemy = ENEMY_SCENE.instantiate()
	add_child(_enemy)
	# Align the target with the offset camera's center ray (local/world X = 0.6).
	_enemy.global_position = Vector3(0.6, 0.0, -8.0)
	_enemy.set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame < 6:
		return
	_done = true
	_run_checks()


func _make_box(node_name: String, at_position: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at_position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _run_checks() -> void:
	var arm: SpringArm3D = _player.spring_arm as SpringArm3D
	var camera: Camera3D = _player.camera as Camera3D
	_check(arm != null and camera != null and camera.get_parent() == arm,
		"TPV: Head -> SpringArm3D -> Camera3D hierarchy")
	_check(arm.position.is_equal_approx(Vector3(0.6, 0.0, 0.0)) and is_zero_approx(camera.position.x),
		"TPV: SpringArm pivot is offset 0.6m right; Camera stays centered on arm")
	_check(is_equal_approx(arm.spring_length, 3.5), "TPV: hip-fire spring length is 3.5m")
	_check(arm.get_hit_length() > 0.1 and arm.get_hit_length() < 3.5,
		"TPV: wall behind player automatically shortens SpringArm3D (hit=%.2fm)" % arm.get_hit_length())
	_check((camera.cull_mask & (1 << (CHARACTERS.PLAYER_BODY_LAYER - 1))) != 0,
		"TPV: Camera cull_mask includes visible player body")
	var screen_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var body_screen: Vector2 = camera.unproject_position((_player.head as Node3D).global_position)
	_check(not camera.is_position_behind((_player.head as Node3D).global_position)
		and body_screen.x < screen_center.x,
		"TPV: player body projects left of center, leaving the crosshair clear")

	_player.set_aiming(true)
	_player._apply_look_and_stance(1.0)
	_check(is_equal_approx(arm.spring_length, 1.5), "TPV: ADS spring length lerps to 1.5m")
	_check(arm.position.is_equal_approx(Vector3(0.6, 0.0, 0.0)),
		"TPV: right-shoulder offset remains intact during ADS")
	_check(is_equal_approx(camera.fov, 60.0) and camera.fov < float(_player.base_fov),
		"TPV: ADS applies moderate zoom-in FOV (75 -> 60)")
	_player.set_aiming(false)
	_player._apply_look_and_stance(1.0)
	_check(is_equal_approx(arm.spring_length, 3.5), "TPV: hip-fire spring length returns to 3.5m")
	_check(is_equal_approx(camera.fov, float(_player.base_fov)), "TPV: hip-fire FOV is restored")

	# Shared boneless VisualHolder animation: exercise each state deterministically.
	var player_visual = _player.visual_holder
	var enemy_visual = _enemy.visual_holder
	_check(player_visual != null and enemy_visual != null
		and player_visual.get_script() == enemy_visual.get_script(),
		"Animation: Player and Enemy share the same procedural VisualHolder animator")
	_check(player_visual.get_node_or_null("Body") != null
		and _player.collision_shape.get_parent() == _player and _player.head.get_parent() == _player,
		"Animation: visual mesh is isolated from collision and camera hierarchy")

	player_visual.set_motion(0.0, 0.0, true, 10.0)
	player_visual._idle_phase = 0.0
	player_visual._walk_phase = 0.0
	player_visual._was_grounded = true
	player_visual._landing_weight = 0.0
	player_visual.position = Vector3.ZERO
	player_visual.rotation = Vector3.ZERO
	player_visual.scale = Vector3.ONE
	for _i in 12:
		player_visual._process(1.0 / 60.0)
	_check(absf(player_visual.position.y) > 0.003 and absf(player_visual.scale.y - 1.0) > 0.001,
		"Animation: idle breathing moves and gently scales the character")

	player_visual.set_motion(6.0, 0.0, true, 10.0)
	player_visual._walk_phase = 0.0
	for _i in 12:
		player_visual._process(1.0 / 60.0)
	_check(absf(player_visual.position.y) > 0.01 and player_visual.rotation.x < deg_to_rad(-3.0)
		and absf(player_visual.rotation.z) > deg_to_rad(0.5),
		"Animation: walking adds vertical bob, forward lean and side sway")

	player_visual.set_motion(0.0, 5.0, false, 10.0)
	for _i in 12:
		player_visual._process(1.0 / 60.0)
	_check(player_visual.scale.y > 1.05, "Animation: jumping stretches visual Y scale")
	player_visual.set_motion(0.0, -5.0, false, 10.0)
	for _i in 12:
		player_visual._process(1.0 / 60.0)
	_check(player_visual.rotation.x > deg_to_rad(3.0), "Animation: falling tilts the character backward")
	player_visual.set_motion(0.0, 0.0, true, 10.0)
	player_visual._process(1.0 / 60.0)
	_check(player_visual.scale.y < 0.93, "Animation: landing applies an immediate squash pose")

	enemy_visual.set_motion(2.6, 0.0, true, 2.6)
	enemy_visual._walk_phase = 0.0
	enemy_visual._was_grounded = true
	enemy_visual._landing_weight = 0.0
	for _i in 12:
		enemy_visual._process(1.0 / 60.0)
	_check(absf(enemy_visual.position.y) > 0.01 and enemy_visual.rotation.x < deg_to_rad(-4.0),
		"Animation: enemy uses the same movement bob and forward lean")

	_check(int(_player.max_health) == 200 and int(_player.health) == 200,
		"Balance: Player starts at 200/200 HP")
	_check(is_equal_approx(float(_enemy.max_health), 200.0) and is_equal_approx(float(_enemy.health), 200.0),
		"Balance: Enemy starts at 200/200 HP")

	var pool_before: Dictionary = _player.effects_pool.get_pool_stats()
	_check(int(pool_before.get("muzzle_flashes", 0)) == 20,
		"Pool: exactly 20 muzzle flashes allocated at match start")
	_check(int(pool_before.get("bullet_holes", 0)) == 50,
		"Pool: exactly 50 bullet holes allocated at match start")
	_check(int(pool_before.get("tracers", 0)) == 32,
		"Pool: visual tracers are also preallocated")

	_check(_player.shoot_audio != null and _player.shoot_audio.name == "ShootAudio"
		and _player.shoot_audio.stream != null and _player.shoot_audio.max_polyphony == 5,
		"Audio: ShootAudio has the generated gunshot stream and 5-shot polyphony")
	_check(_player.footstep_audio != null and _player.footstep_audio.name == "FootstepAudio"
		and _player.footstep_audio.stream != null and _enemy.footstep_audio != null
		and _enemy.footstep_audio.stream != null,
		"Audio: Player and Enemy have generated positional footstep streams")

	# Remove random spread so this test measures raycast/damage behavior only.
	var weapon: Dictionary = _player.weapon_manager.get_current()
	weapon["spread"] = 0.0
	var damage: float = float(weapon.get("damage", 55.0))
	var expected_shots: int = int(ceil(float(_enemy.max_health) / damage))
	_check(expected_shots == 4, "Balance: starting Desert Eagle kills 200 HP enemy in four hits")
	var ray_query: PhysicsRayQueryParameters3D = _player._camera_ray as PhysicsRayQueryParameters3D
	_check(ray_query != null and ray_query.exclude.has((_player as CharacterBody3D).get_rid()),
		"Hitscan: camera ray explicitly excludes Player CharacterBody3D RID")

	_player.set_sprinting(true)
	_check(_player.is_sprinting, "RUN toggle can be enabled through player API")
	_player.shoot()
	_check(not _player.is_sprinting, "successful hitscan fire cancels the RUN toggle")
	_check(_player.shoot_audio.playing, "Audio: successful hitscan fire starts ShootAudio playback")
	var crosshair: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var expected_origin: Vector3 = camera.project_ray_origin(crosshair)
	var expected_direction: Vector3 = camera.project_ray_normal(crosshair).normalized()
	var actual_direction: Vector3 = (ray_query.to - ray_query.from).normalized()
	_check(ray_query.from.is_equal_approx(expected_origin),
		"Hitscan: damage ray starts at Camera3D center, not gun or chest")
	_check(actual_direction.is_equal_approx(expected_direction),
		"Hitscan: damage ray follows the center-screen crosshair")
	var expected_after_one: float = maxf(0.0, 200.0 - damage)
	_check(is_equal_approx(float(_enemy.health), expected_after_one),
		"Hitscan: first shot applies %.0f damage instantly (HP=%.0f)" % [damage, float(_enemy.health)])
	var fill: MeshInstance3D = _enemy._health_fill as MeshInstance3D
	_check(fill != null and is_equal_approx(fill.scale.x, expected_after_one / 200.0),
		"Balance: Enemy overhead HP bar updates on hitscan damage")

	for i in range(1, expected_shots):
		_player.shoot()
	_check(bool(_enemy.is_dead), "Hitscan: enemy dies after the expected four direct ray hits")
	_check(int(_player.shots_fired) == expected_shots,
		"Hitscan: shot counter advances without physical bullet instances")

	var pool_after: Dictionary = _player.effects_pool.get_pool_stats()
	_check(int(pool_after.get("allocated_nodes", -1)) == int(pool_before.get("allocated_nodes", -2)),
		"Pool: firing does not allocate or free any effect nodes")
	_check(int(pool_after.get("tracer_events", 0)) == expected_shots
		and int(pool_after.get("muzzle_events", 0)) == expected_shots,
		"Pool: every shot reuses a visual tracer and muzzle flash")

	_finish()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + description)
	else:
		_failures.append(description)
		push_error("[FAIL] " + description)


func _finish() -> void:
	print("COMBAT_SELFTEST checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("COMBAT_SELFTEST_PASS")
		get_tree().quit(0)
	else:
		print("COMBAT_SELFTEST_FAIL")
		get_tree().quit(1)
