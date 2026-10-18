extends Node3D
## Headless terrain-only ray and CharacterBody3D walk validation. No gameplay actors/assets.

const MAP_SCENE := preload("res://scenes/map.tscn")
const WALK_SPEED := 18.0
const MAX_TEST_SECONDS := 36.0

var _island: Node3D
var _walker: CharacterBody3D
var _waypoints: Array[Vector2] = [
	Vector2(0.0, -390.0),  # beach start
	Vector2(0.0, -340.0),  # climb onto the north mountain ring
	Vector2(0.0, -300.0),
	Vector2(0.0, -260.0),
	Vector2(0.0, -220.0),  # north ramp approach
	Vector2(0.0, -180.0),
	Vector2(0.0, -140.0),
	Vector2(0.0, -120.0),  # plateau edge
	Vector2(0.0, -80.0),
	Vector2(0.0, 0.0),  # central plateau
]
var _waypoint_index := 1
var _elapsed := 0.0
var _walking := false


func _ready() -> void:
	_island = MAP_SCENE.instantiate() as Node3D
	_island.name = "IslandUnderTest"
	add_child(_island)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not _check_ground_rays():
		return
	_create_probe_walker()
	_walking = true
	print("TERRAIN_SELFTEST: walking beach -> north hills -> plateau")


func _physics_process(delta: float) -> void:
	if not _walking or _walker == null:
		return
	_elapsed += delta
	if _elapsed > MAX_TEST_SECONDS:
		_fail("CharacterBody3D did not finish the walk before timeout")
		return

	var current := Vector2(_walker.global_position.x, _walker.global_position.z)
	var target: Vector2 = _waypoints[_waypoint_index]
	var to_target := target - current
	if to_target.length() <= 1.4 and _walker.is_on_floor():
		_waypoint_index += 1
		if _waypoint_index >= _waypoints.size():
			if _walker.is_on_floor() and _walker.global_position.y >= 14.0:
				print("TERRAIN_SELFTEST_PASS: beach, hills, ramp, and 15m plateau are walkable")
				get_tree().quit(0)
			else:
				_fail("walker reached center without standing on the plateau")
			return
		to_target = _waypoints[_waypoint_index] - current

	if to_target.length() > 0.01:
		var direction := to_target.normalized()
		_walker.velocity.x = direction.x * WALK_SPEED
		_walker.velocity.z = direction.y * WALK_SPEED

	if _walker.is_on_floor():
		_walker.velocity.y = -0.2
	else:
		_walker.velocity.y -= 24.0 * delta
	_walker.move_and_slide()

	var surface_y: float = float(
		_island.call("sample_height", _walker.global_position.x, _walker.global_position.z)
	)
	if _walker.global_position.y < surface_y - 2.0:
		_fail("walker fell through terrain at %s" % str(_walker.global_position))


func _check_ground_rays() -> bool:
	var checks: Array[Dictionary] = [
		{"label": "beach", "x": 0.0, "z": -390.0},
		{"label": "north hill", "x": 0.0, "z": -315.0},
		{"label": "north ramp", "x": 0.0, "z": -180.0},
		{"label": "south ramp", "x": 0.0, "z": 180.0},
		{"label": "east ramp", "x": 180.0, "z": 0.0},
		{"label": "west ramp", "x": -180.0, "z": 0.0},
		{"label": "plateau", "x": 0.0, "z": 0.0},
		{"label": "industrial apron", "x": 245.0, "z": -70.0},
	]
	var space := get_world_3d().direct_space_state
	for item in checks:
		var x := float(item["x"])
		var z := float(item["z"])
		var expected_y := float(_island.call("sample_height", x, z))
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, expected_y + 30.0, z), Vector3(x, expected_y - 30.0, z)
		)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_fail("no ground collision ray hit at %s" % String(item["label"]))
			return false
		var hit_position: Vector3 = hit["position"]
		var hit_y := hit_position.y
		if absf(hit_y - expected_y) > 2.5:
			_fail(
				(
					"collision height mismatch at %s (%.2f vs %.2f)"
					% [item["label"], hit_y, expected_y]
				)
			)
			return false
		print("TERRAIN_SELFTEST: collision OK at %s y=%.2f" % [item["label"], hit_y])
	return true


func _create_probe_walker() -> void:
	_walker = CharacterBody3D.new()
	_walker.name = "TerrainProbe_NoGameplay"
	_walker.floor_max_angle = deg_to_rad(55.0)
	_walker.floor_snap_length = 2.0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	var shape_node := CollisionShape3D.new()
	shape_node.shape = capsule
	_walker.add_child(shape_node)
	var start_z: float = _waypoints[0].y
	_walker.global_position = Vector3(
		0.0, float(_island.call("sample_height", 0.0, start_z)) + 1.0, start_z
	)
	add_child(_walker)


func _fail(message: String) -> void:
	_walking = false
	push_error("TERRAIN_SELFTEST_FAIL: " + message)
	print("TERRAIN_SELFTEST_FAIL: " + message)
	get_tree().quit(1)
