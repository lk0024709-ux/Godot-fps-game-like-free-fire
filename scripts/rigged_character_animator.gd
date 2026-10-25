extends Node3D
## Shared skeletal animation controller for the Player and Enemy VisualHolder.
## The imported GLB owns its Skeleton3D and AnimationPlayer; this node only
## selects looping Idle/Walk clips from real CharacterBody3D movement. Camera,
## collision, weapon transforms, and hitscan logic remain independent.

const IDLE_CLIP: StringName = &"Idle"
const WALK_CLIP: StringName = &"Walk"
const MOVE_THRESHOLD: float = 0.12

@export var crossfade_seconds: float = 0.15
@export var minimum_walk_playback_speed: float = 0.70
@export var maximum_walk_playback_speed: float = 1.60

var _horizontal_speed: float = 0.0
var _vertical_speed: float = 0.0
var _grounded: bool = true
var _reference_speed: float = 6.0
var _animation_player: AnimationPlayer = null
var _active_clip: StringName = &""


## Called by Player/Enemy immediately after instancing player_animated.glb.
func register_character(character_root: Node) -> AnimationPlayer:
	_animation_player = _find_animation_player(character_root)
	_active_clip = &""
	if _animation_player == null:
		push_warning("Rigged character has no AnimationPlayer; expected Idle and Walk clips")
		return null

	for clip_name in [IDLE_CLIP, WALK_CLIP]:
		if not _animation_player.has_animation(clip_name):
			push_warning("Rigged character is missing animation clip: %s" % clip_name)
			continue
		var clip := _animation_player.get_animation(clip_name)
		if clip != null:
			clip.loop_mode = Animation.LOOP_LINEAR

	_animation_player.autoplay = IDLE_CLIP
	_play_clip(IDLE_CLIP)
	return _animation_player


## Parent controllers feed actual velocity after each physics tick.
func set_motion(
	horizontal_speed: float,
	vertical_speed: float,
	on_ground: bool,
	reference_speed: float
) -> void:
	_horizontal_speed = maxf(0.0, horizontal_speed)
	_vertical_speed = vertical_speed
	_grounded = on_ground
	_reference_speed = maxf(0.01, reference_speed)


func get_animation_player() -> AnimationPlayer:
	return _animation_player


func get_active_clip() -> StringName:
	return _active_clip


func _process(_delta: float) -> void:
	if _animation_player == null:
		return
	var should_walk: bool = _grounded and _horizontal_speed > MOVE_THRESHOLD
	_play_clip(WALK_CLIP if should_walk else IDLE_CLIP)
	if should_walk:
		var speed_ratio: float = clampf(_horizontal_speed / _reference_speed, 0.0, 1.0)
		_animation_player.speed_scale = lerpf(
			minimum_walk_playback_speed,
			maximum_walk_playback_speed,
			speed_ratio
		)
	else:
		_animation_player.speed_scale = 1.0


func _play_clip(clip_name: StringName) -> void:
	if _animation_player == null or not _animation_player.has_animation(clip_name):
		return
	if _active_clip == clip_name and _animation_player.is_playing():
		return
	_active_clip = clip_name
	_animation_player.play(clip_name, crossfade_seconds)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
