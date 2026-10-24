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
	_enemy.global_position = Vector3(0.0, 0.0, -8.0)
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
	_check(is_equal_approx(arm.spring_length, 3.5), "TPV: hip-fire spring length is 3.5m")
	_check(arm.get_hit_length() > 0.1 and arm.get_hit_length() < 3.5,
		"TPV: wall behind player automatically shortens SpringArm3D (hit=%.2fm)" % arm.get_hit_length())
	_check((camera.cull_mask & (1 << (CHARACTERS.PLAYER_BODY_LAYER - 1))) != 0,
		"TPV: Camera cull_mask includes visible player body")

	_player.set_aiming(true)
	_player._apply_look_and_stance(1.0)
	_check(is_equal_approx(arm.spring_length, 1.5), "TPV: ADS spring length lerps to 1.5m")
	_player.set_aiming(false)
	_player._apply_look_and_stance(1.0)
	_check(is_equal_approx(arm.spring_length, 3.5), "TPV: hip-fire spring length returns to 3.5m")

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

	# Remove random spread so this test measures raycast/damage behavior only.
	var weapon: Dictionary = _player.weapon_manager.get_current()
	weapon["spread"] = 0.0
	var damage: float = float(weapon.get("damage", 55.0))
	var expected_shots: int = int(ceil(float(_enemy.max_health) / damage))
	_check(expected_shots == 4, "Balance: starting Desert Eagle kills 200 HP enemy in four hits")

	_player.shoot()
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
