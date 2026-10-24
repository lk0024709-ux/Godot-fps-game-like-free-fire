extends Node3D
##
## Fixed-size combat VFX pools. Every mesh is allocated once when the player
## enters the match; firing only repositions existing nodes and resets timers.
## No instantiate(), queue_free(), or per-shot mesh/material creation happens here.
##
## Pools required by gameplay:
##   20 muzzle flashes + 50 bullet-hole meshes + 32 fast visual tracers.
## Damage is NOT handled by this script; player.gd applies hitscan damage instantly.
##

const MUZZLE_FLASH_POOL_SIZE: int = 20
const BULLET_HOLE_POOL_SIZE: int = 50
const TRACER_POOL_SIZE: int = 32

const FLASH_LIFETIME: float = 0.05
const BULLET_HOLE_LIFETIME: float = 25.0
const TRACER_SPEED: float = 240.0
const TRACER_MAX_TRAVEL_TIME: float = 0.12
const TRACER_LENGTH: float = 0.85

var tracer_events: int = 0
var muzzle_events: int = 0
var bullet_hole_events: int = 0

var _muzzle_flashes: Array[MeshInstance3D] = []
var _bullet_holes: Array[MeshInstance3D] = []
var _tracers: Array[MeshInstance3D] = []

var _muzzle_life: Array[float] = []
var _bullet_hole_life: Array[float] = []
var _tracer_age: Array[float] = []
var _tracer_duration: Array[float] = []
var _tracer_starts: Array[Vector3] = []
var _tracer_deltas: Array[Vector3] = []

var _next_muzzle: int = 0
var _next_bullet_hole: int = 0
var _next_tracer: int = 0


func _ready() -> void:
	# Effects keep world-space transforms even though this pool belongs to Player.
	set_as_top_level(true)
	_build_muzzle_pool()
	_build_bullet_hole_pool()
	_build_tracer_pool()


func _build_muzzle_pool() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.82, 0.24)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.10)
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := SphereMesh.new()
	mesh.radius = 0.085
	mesh.height = 0.17
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material

	for i in MUZZLE_FLASH_POOL_SIZE:
		var flash := MeshInstance3D.new()
		flash.name = "MuzzleFlash_%02d" % i
		flash.mesh = mesh
		_prepare_effect_mesh(flash)
		add_child(flash)
		_muzzle_flashes.append(flash)
		_muzzle_life.append(0.0)


func _build_bullet_hole_pool() -> void:
	# Quad meshes work in the mobile Compatibility renderer (unlike Decal nodes).
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.028, 0.022)
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.105, 0.105)
	mesh.material = material

	for i in BULLET_HOLE_POOL_SIZE:
		var hole := MeshInstance3D.new()
		hole.name = "BulletHole_%02d" % i
		hole.mesh = mesh
		_prepare_effect_mesh(hole)
		add_child(hole)
		_bullet_holes.append(hole)
		_bullet_hole_life.append(0.0)


func _build_tracer_pool() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.88, 0.26)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.72, 0.12)
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Shared unit-length mesh; only each pooled node's Z scale changes on reuse.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.022, 0.022, 1.0)
	mesh.material = material

	for i in TRACER_POOL_SIZE:
		var tracer := MeshInstance3D.new()
		tracer.name = "HitscanTracer_%02d" % i
		tracer.mesh = mesh
		_prepare_effect_mesh(tracer)
		add_child(tracer)
		_tracers.append(tracer)
		_tracer_age.append(0.0)
		_tracer_duration.append(0.0)
		_tracer_starts.append(Vector3.ZERO)
		_tracer_deltas.append(Vector3.ZERO)


func _prepare_effect_mesh(node: MeshInstance3D) -> void:
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Reuse one of the 20 flashes. Ring-buffer reuse also bounds automatic fire cost.
func spawn_muzzle_flash(at_position: Vector3, lifetime: float = FLASH_LIFETIME) -> void:
	if _muzzle_flashes.is_empty():
		return
	var index: int = _next_muzzle
	_next_muzzle = (_next_muzzle + 1) % MUZZLE_FLASH_POOL_SIZE
	var flash: MeshInstance3D = _muzzle_flashes[index]
	flash.global_position = at_position
	flash.scale = Vector3.ONE
	flash.visible = true
	_muzzle_life[index] = maxf(0.01, lifetime)
	muzzle_events += 1


## Reuse one of the 50 impact meshes and orient its front face along the hit normal.
func spawn_bullet_hole(at_position: Vector3, normal: Vector3) -> void:
	if _bullet_holes.is_empty() or normal.length_squared() < 0.001:
		return
	var index: int = _next_bullet_hole
	_next_bullet_hole = (_next_bullet_hole + 1) % BULLET_HOLE_POOL_SIZE
	var hole: MeshInstance3D = _bullet_holes[index]
	var unit_normal: Vector3 = normal.normalized()
	hole.global_position = at_position + unit_normal * 0.012
	var up: Vector3 = Vector3.RIGHT if absf(unit_normal.dot(Vector3.UP)) > 0.98 else Vector3.UP
	# Node3D looks along -Z; looking opposite the normal puts QuadMesh +Z outward.
	hole.look_at(at_position - unit_normal, up)
	hole.scale = Vector3.ONE
	hole.visible = true
	_bullet_hole_life[index] = BULLET_HOLE_LIFETIME
	bullet_hole_events += 1


## Purely visual fast tracer. The hitscan ray has already applied its damage.
func spawn_tracer(from_position: Vector3, to_position: Vector3) -> void:
	if _tracers.is_empty():
		return
	var delta: Vector3 = to_position - from_position
	var distance: float = delta.length()
	if distance < 0.025:
		return

	var index: int = _next_tracer
	_next_tracer = (_next_tracer + 1) % TRACER_POOL_SIZE
	var tracer: MeshInstance3D = _tracers[index]
	tracer.global_position = from_position
	var direction: Vector3 = delta / distance
	var up: Vector3 = Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	tracer.look_at(to_position, up)
	tracer.scale = Vector3(1.0, 1.0, minf(TRACER_LENGTH, distance))
	tracer.visible = true

	_tracer_starts[index] = from_position
	_tracer_deltas[index] = delta
	_tracer_age[index] = 0.0
	_tracer_duration[index] = maxf(0.02, minf(TRACER_MAX_TRAVEL_TIME, distance / TRACER_SPEED))
	tracer_events += 1


func _process(delta: float) -> void:
	for i in _muzzle_flashes.size():
		if _muzzle_life[i] <= 0.0:
			continue
		_muzzle_life[i] -= delta
		if _muzzle_life[i] <= 0.0:
			_muzzle_flashes[i].visible = false

	for i in _bullet_holes.size():
		if _bullet_hole_life[i] <= 0.0:
			continue
		_bullet_hole_life[i] -= delta
		if _bullet_hole_life[i] <= 0.0:
			_bullet_holes[i].visible = false

	for i in _tracers.size():
		if _tracer_duration[i] <= 0.0:
			continue
		_tracer_age[i] += delta
		var progress: float = clampf(_tracer_age[i] / _tracer_duration[i], 0.0, 1.0)
		_tracers[i].global_position = _tracer_starts[i] + _tracer_deltas[i] * progress
		if progress >= 1.0:
			_tracer_duration[i] = 0.0
			_tracers[i].visible = false


## Diagnostic snapshot for the headless combat self-test; never called per shot.
func get_pool_stats() -> Dictionary:
	return {
		"muzzle_flashes": _muzzle_flashes.size(),
		"bullet_holes": _bullet_holes.size(),
		"tracers": _tracers.size(),
		"allocated_nodes": get_child_count(),
		"tracer_events": tracer_events,
		"muzzle_events": muzzle_events,
		"bullet_hole_events": bullet_hole_events,
	}
