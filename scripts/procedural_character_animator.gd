extends Node3D
## Shared boneless character animation for Player and Enemy VisualHolder nodes.
## Only this holder is transformed: collision, camera, weapon and fitted GLB/OBJ
## model transforms remain independent. No Tweens or allocations are created per frame.

@export var idle_bob_height: float = 0.02
@export var idle_scale_amount: float = 0.01
@export var walk_bob_height: float = 0.05
@export var max_lean_deg: float = 9.0
@export var side_sway_deg: float = 2.0
@export var air_stretch_y: float = 1.10
@export var landing_squash_y: float = 0.90

var _horizontal_speed: float = 0.0
var _vertical_speed: float = 0.0
var _grounded: bool = true
var _reference_speed: float = 6.0

var _idle_phase: float = 0.0
var _walk_phase: float = 0.0
var _was_grounded: bool = true
var _landing_weight: float = 0.0


## Parent controllers feed actual CharacterBody3D motion after each physics tick.
func set_motion(horizontal_speed: float, vertical_speed: float, on_ground: bool, reference_speed: float) -> void:
	_horizontal_speed = maxf(0.0, horizontal_speed)
	_vertical_speed = vertical_speed
	_grounded = on_ground
	_reference_speed = maxf(0.01, reference_speed)


func _process(delta: float) -> void:
	var just_landed: bool = _grounded and not _was_grounded
	if just_landed:
		# Immediate impact pose, followed by a smooth recovery below.
		_landing_weight = 1.0
		scale = Vector3(1.05, landing_squash_y, 1.05)
		position.y = -0.03
	elif not _grounded:
		_landing_weight = 0.0
	else:
		_landing_weight = move_toward(_landing_weight, 0.0, delta * 4.5)
	_was_grounded = _grounded

	var speed_ratio: float = clampf(_horizontal_speed / _reference_speed, 0.0, 1.0)
	var moving: bool = _grounded and _horizontal_speed > 0.12
	_idle_phase += delta * 2.0

	var target_position := Vector3.ZERO
	var target_rotation := Vector3.ZERO
	var target_scale := Vector3.ONE

	if not _grounded:
		# Boneless jump/fall silhouette: stretched Y and a slight backward fall tilt.
		target_scale = Vector3(0.96, air_stretch_y, 0.96)
		target_position.y = 0.02
		target_rotation.x = deg_to_rad(7.0) if _vertical_speed < -0.2 else deg_to_rad(-3.0)
	elif moving:
		# Faster movement increases step frequency, bob amplitude and forward lean.
		var step_frequency: float = lerpf(7.0, 12.0, speed_ratio)
		_walk_phase += delta * step_frequency
		var bob_amplitude: float = walk_bob_height * lerpf(0.70, 1.0, speed_ratio)
		target_position.y = sin(_walk_phase) * bob_amplitude
		target_rotation.x = -deg_to_rad(lerpf(4.0, max_lean_deg, speed_ratio))
		target_rotation.z = sin(_walk_phase) * deg_to_rad(side_sway_deg)
	else:
		# Idle breathing intentionally remains subtle (about +/-2cm and +/-1% Y).
		var breath: float = sin(_idle_phase)
		target_position.y = breath * idle_bob_height
		target_scale.y = 1.0 + breath * idle_scale_amount

	if _grounded and _landing_weight > 0.0:
		target_position.y = lerpf(target_position.y, -0.03, _landing_weight)
		target_scale.x = lerpf(target_scale.x, 1.05, _landing_weight)
		target_scale.y = lerpf(target_scale.y, landing_squash_y, _landing_weight)
		target_scale.z = lerpf(target_scale.z, 1.05, _landing_weight)

	var blend: float = 1.0 - exp(-delta * 14.0)
	position = position.lerp(target_position, blend)
	rotation = Vector3(
		lerpf(rotation.x, target_rotation.x, blend),
		lerpf(rotation.y, target_rotation.y, blend),
		lerpf(rotation.z, target_rotation.z, blend)
	)
	scale = scale.lerp(target_scale, blend)
