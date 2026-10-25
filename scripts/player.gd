extends CharacterBody3D
##
## Player (Third-Person + Battle Royale Sky Drop + Tactical Controls)
##
## States:
##   DropState.IN_PLANE  -> locked inside Elite Cargo Dropship at Y=300m (50 m/s)
##   DropState.FREEFALL  -> ejected skydiving free-fall with air steering
##   DropState.PARACHUTE -> auto-deployed at Y<=50m, 5.0 m/s descent + 3D canopy
##   DropState.LANDED    -> parachute removed, full TPV movement + ADS + crouch + sprint + combat
##

signal health_changed(health: int)
signal ep_changed(ep: int)
signal medkits_changed(count: int)
signal drop_state_changed(state: int)
signal aim_changed(is_aiming: bool)
signal crouch_changed(is_crouching: bool)
signal sprint_changed(is_sprinting: bool)
signal died

enum DropState {
	IN_PLANE = 0,
	FREEFALL = 1,
	PARACHUTE = 2,
	LANDED = 3,
}

const WEAPON_MANAGER := preload("res://scripts/weapon_manager.gd")
const ASSETS := preload("res://scripts/assets.gd")
const CHARACTERS := preload("res://scripts/character_data.gd")
const ANIMATED_CHARACTER_PATH := "res://assets/models/characters/player_animated.glb"

@export_group("Movement")
@export var move_speed: float = 6.0
@export var run_speed: float = 9.0
@export var sprint_ep_drain: float = 12.0
@export var sprint_restart_ep: float = 20.0
@export var crouch_speed: float = 3.6
@export var jump_velocity: float = 5.2
@export var gravity: float = 18.0

@export_group("Plane Drop & Parachute")
@export var freefall_gravity: float = 25.0
@export var max_freefall_speed: float = 54.0
@export var air_steer_speed: float = 16.0
@export var parachute_deploy_height: float = 50.0
@export var parachute_fall_speed: float = 5.0
@export var parachute_steer_speed: float = 12.0

@export_group("Tactical Stances")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 84.0
@export var ads_fov: float = 60.0 ## Lower than base_fov = comfortable ADS zoom-in
@export var stand_head_y: float = 1.55
@export var crouch_head_y: float = 0.96

@export_group("Third-Person Camera")
@export var shoulder_offset: Vector3 = Vector3(0.6, 0.0, 0.0)
@export var hip_spring_length: float = 3.5
@export var ads_spring_length: float = 1.5
@export var camera_lerp_speed: float = 12.0

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var touch_sensitivity: float = 0.005
@export var pitch_limit_deg: float = 85.0
@export var camera_far: float = 3200.0

@export_group("Body")
@export var character_index: int = 0
@export var show_body: bool = true
@export var name_tag: bool = true

@export_group("Combat & Survival")
@export var max_health: int = 200
@export var max_ep: int = 100
@export var starting_medkits: int = 5
@export var medkit_heal_hp: int = 40
@export var medkit_heal_ep: int = 25
@export var ep_regen_rate: float = 3.5        ## EP -> HP passive conversion per second
@export var gun_kick: float = 0.05
@export var muzzle_flash_time: float = 0.05
@export var hitscan_range: float = 1200.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_holder = $VisualHolder
@onready var head: Node3D = $Head
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D
@onready var weapon_holder: Node3D = $Head/WeaponHolder
@onready var effects_pool = $CombatEffectsPool

var weapon_manager: Node = null
var shoot_audio: AudioStreamPlayer3D = null
var footstep_audio: AudioStreamPlayer3D = null
var drop_state: int = DropState.LANDED
var health: int = 200
var ep: float = 100.0
var medkits: int = 5
var is_dead: bool = false
var is_firing: bool = false
var is_aiming: bool = false
var is_crouching: bool = false
var is_sprinting: bool = false
var shots_fired: int = 0

var _sprinting_now: bool = false
var _sprint_exhausted: bool = false

var hud = null

var _pitch: float = 0.0
var _recoil: float = 0.0
var _kick: float = 0.0
var _bob_time: float = 0.0
var _ep_accum: float = 0.0
var _holder_base: Vector3 = Vector3.ZERO
var _fire_timer: float = 0.0
var _step_timer: float = 0.0
var _trigger_ready: bool = true
var _jump_requested: bool = false
var _camera_ray: PhysicsRayQueryParameters3D = null
var _eject_requested: bool = false
var _look_touch: int = -1
var _is_mobile: bool = false

# Plane chase camera + 3D parachute canopy state
var _plane_ref: Node3D = null
var _plane_chase_cam: Camera3D = null
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -0.34
var _parachute_rig: Node3D = null
var _chute_tween: Tween = null
var _chute_sway_time: float = 0.0
var _drop_stall_timer: float = 0.0
var _last_drop_y: float = 300.0


func _ready() -> void:
	add_to_group("player")
	_setup_input()
	floor_max_angle = deg_to_rad(56.0)
	floor_snap_length = 0.35
	camera.far = camera_far
	# Offset the arm/pivot, not the Camera child, so wall collision follows it.
	spring_arm.position = shoulder_offset
	spring_arm.spring_length = hip_spring_length
	spring_arm.collision_mask = 1
	spring_arm.add_excluded_object(get_rid())
	# TPV must render the layer used by the player's visible character model.
	camera.cull_mask = camera.cull_mask | (1 << (CHARACTERS.PLAYER_BODY_LAYER - 1))
	health = max_health
	ep = float(max_ep)
	medkits = starting_medkits
	_is_mobile = OS.has_feature("mobile")
	_holder_base = weapon_holder.position

	# Reused ray queries avoid per-shot query/exclude-array allocation.
	_camera_ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD)
	_camera_ray.collision_mask = 1 | 4
	_camera_ray.collide_with_areas = false
	_camera_ray.collide_with_bodies = true
	# Explicit self-exclusion is required even though Player is on collision layer 2.
	_camera_ray.exclude = [get_rid()]

	_build_body()
	_setup_audio()

	weapon_manager = WEAPON_MANAGER.new()
	weapon_manager.name = "WeaponManager"
	add_child(weapon_manager)
	weapon_manager.set_holder(weapon_holder)

	if not _is_mobile and not DisplayServer.get_name().contains("headless"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _setup_audio() -> void:
	shoot_audio = AudioStreamPlayer3D.new()
	shoot_audio.name = "ShootAudio"
	shoot_audio.stream = preload("res://assets/sounds/shoot.wav")
	shoot_audio.max_polyphony = 5
	shoot_audio.volume_db = -4.0
	shoot_audio.unit_size = 8.0
	shoot_audio.max_distance = 80.0
	add_child(shoot_audio)

	footstep_audio = AudioStreamPlayer3D.new()
	footstep_audio.name = "FootstepAudio"
	footstep_audio.stream = preload("res://assets/sounds/footstep.wav")
	footstep_audio.max_polyphony = 2
	footstep_audio.volume_db = -5.0
	footstep_audio.unit_size = 4.0
	footstep_audio.max_distance = 30.0
	add_child(footstep_audio)


# ===================================================== PLANE DROP & PARACHUTE =

## Lock player inside the cargo plane at match start (Y = 300m).
func enter_plane(plane_node: Node3D, hold_offset: Vector3 = Vector3(0.0, 2.75, 11.5)) -> void:
	_plane_ref = plane_node
	drop_state = DropState.IN_PLANE
	is_firing = false
	set_sprinting(false)
	is_aiming = false
	is_crouching = false
	_eject_requested = false
	_drop_stall_timer = 0.0
	velocity = Vector3.ZERO
	weapon_holder.visible = false
	collision_shape.disabled = true

	if plane_node != null and is_instance_valid(plane_node):
		global_position = plane_node.to_global(hold_offset)
		rotation.y = plane_node.global_rotation.y
		_orbit_yaw = plane_node.global_rotation.y
	_last_drop_y = global_position.y

	_ensure_plane_chase_camera()
	_update_plane_chase_camera()
	drop_state_changed.emit(drop_state)


## Called each physics tick by main.gd while the player remains aboard the cargo plane.
func sync_with_plane(plane_node: Node3D, hold_offset: Vector3, plane_vel: Vector3) -> void:
	if drop_state != DropState.IN_PLANE:
		return
	_plane_ref = plane_node
	if plane_node != null and is_instance_valid(plane_node):
		global_position = plane_node.to_global(hold_offset)
	velocity = plane_vel
	_last_drop_y = global_position.y
	_update_plane_chase_camera()


## Eject player out of the plane cargo bay into free-fall.
func eject_from_plane(inherit_velocity: Vector3 = Vector3.ZERO) -> void:
	if drop_state != DropState.IN_PLANE:
		return
	collision_shape.disabled = false
	if _plane_ref != null and is_instance_valid(_plane_ref):
		# Clear cleanly below the rear cargo bay opening so capsule never snags on hull
		global_position = _plane_ref.global_position + Vector3(0.0, -2.5, 0.0)
	_plane_ref = null

	if _plane_chase_cam != null and is_instance_valid(_plane_chase_cam):
		_plane_chase_cam.current = false
		_plane_chase_cam.queue_free()
		_plane_chase_cam = null
	camera.current = true

	rotation.y = _orbit_yaw
	_pitch = deg_to_rad(-28.0)
	velocity = Vector3(inherit_velocity.x, -6.0, inherit_velocity.z)
	_last_drop_y = global_position.y
	_drop_stall_timer = 0.0
	drop_state = DropState.FREEFALL
	drop_state_changed.emit(drop_state)


## Deploy the 3D parachute at Y <= 50m and cap fall speed to parachute_fall_speed (5 m/s).
func deploy_parachute() -> void:
	if drop_state != DropState.FREEFALL:
		return
	drop_state = DropState.PARACHUTE
	velocity.y = -parachute_fall_speed
	_attach_parachute_mesh()
	drop_state_changed.emit(drop_state)


func has_parachute() -> bool:
	return _parachute_rig != null and is_instance_valid(_parachute_rig)


func is_in_drop() -> bool:
	return drop_state != DropState.LANDED


func is_landed() -> bool:
	return drop_state == DropState.LANDED


func consume_eject_request() -> bool:
	if not _eject_requested:
		return false
	_eject_requested = false
	return true


func request_eject() -> void:
	if drop_state == DropState.IN_PLANE and not is_dead:
		_eject_requested = true


func _complete_landing() -> void:
	if _chute_tween != null and _chute_tween.is_valid():
		_chute_tween.kill()
		_chute_tween = null
	if _parachute_rig != null and is_instance_valid(_parachute_rig):
		remove_child(_parachute_rig)
		_parachute_rig.queue_free()
		_parachute_rig = null
	collision_shape.disabled = false
	weapon_holder.visible = true
	velocity.y = 0.0
	_pitch = clampf(_pitch, deg_to_rad(-35.0), deg_to_rad(35.0))
	drop_state = DropState.LANDED
	drop_state_changed.emit(drop_state)


func _ensure_plane_chase_camera() -> void:
	if _plane_chase_cam != null and is_instance_valid(_plane_chase_cam):
		_plane_chase_cam.current = true
		return
	_plane_chase_cam = Camera3D.new()
	_plane_chase_cam.name = "DropshipChaseCamera"
	_plane_chase_cam.fov = 72.0
	_plane_chase_cam.near = 0.2
	_plane_chase_cam.far = camera_far
	_plane_chase_cam.top_level = true
	add_child(_plane_chase_cam)
	camera.current = false
	_plane_chase_cam.current = true


func _update_plane_chase_camera() -> void:
	if _plane_chase_cam == null or not is_instance_valid(_plane_chase_cam):
		return
	var target := global_position
	if _plane_ref != null and is_instance_valid(_plane_ref):
		target = _plane_ref.global_position + Vector3(0.0, 4.0, 0.0)
	var dist := 48.0
	var horiz := cos(_orbit_pitch) * dist
	var offset := Vector3(
		sin(_orbit_yaw) * horiz,
		-sin(_orbit_pitch) * dist + 8.0,
		cos(_orbit_yaw) * horiz
	)
	_plane_chase_cam.global_position = target + offset
	_plane_chase_cam.look_at(target + Vector3(0.0, -4.0, 0.0), Vector3.UP)


func _attach_parachute_mesh() -> void:
	if _parachute_rig != null and is_instance_valid(_parachute_rig):
		return
	var rig := Node3D.new()
	rig.name = "ParachuteRig"
	rig.position = Vector3(0.0, 1.45, 0.0)

	# Vibrant orange-gold parachute canopy dome
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.98, 0.46, 0.12)
	canopy_mat.roughness = 0.65
	canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.98, 0.94, 0.84)
	stripe_mat.roughness = 0.70
	stripe_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.16, 0.18, 0.22)
	rope_mat.roughness = 0.90

	var canopy := MeshInstance3D.new()
	canopy.name = "ParachuteCanopy"
	var dome := CylinderMesh.new()
	dome.top_radius = 0.55
	dome.bottom_radius = 2.85
	dome.height = 1.25
	dome.radial_segments = 12
	dome.material = canopy_mat
	canopy.mesh = dome
	canopy.position = Vector3(0.0, 3.35, 0.0)
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(canopy)

	var trim := MeshInstance3D.new()
	trim.name = "CanopyTrim"
	var trim_mesh := CylinderMesh.new()
	trim_mesh.top_radius = 2.87
	trim_mesh.bottom_radius = 2.92
	trim_mesh.height = 0.14
	trim_mesh.radial_segments = 12
	trim_mesh.material = stripe_mat
	trim.mesh = trim_mesh
	trim.position = Vector3(0.0, 2.74, 0.0)
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(trim)

	# 4 suspension risers connecting shoulders to canopy rim
	var anchors := [
		[Vector3(-0.32, 0.0, -0.20), Vector3(-2.35, 2.75, -1.65)],
		[Vector3(0.32, 0.0, -0.20), Vector3(2.35, 2.75, -1.65)],
		[Vector3(-0.32, 0.0, 0.20), Vector3(-2.35, 2.75, 1.65)],
		[Vector3(0.32, 0.0, 0.20), Vector3(2.35, 2.75, 1.65)],
	]
	for i in anchors.size():
		var a: Vector3 = anchors[i][0]
		var b: Vector3 = anchors[i][1]
		var cord := MeshInstance3D.new()
		cord.name = "Riser_%d" % i
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.035, 0.035, a.distance_to(b))
		line_mesh.material = rope_mat
		cord.mesh = line_mesh
		cord.position = (a + b) * 0.5
		cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(cord)
		cord.look_at_from_position((a + b) * 0.5, b, Vector3.UP)

	add_child(rig)
	_parachute_rig = rig

	rig.scale = Vector3.ONE * 0.2
	_chute_tween = create_tween()
	_chute_tween.tween_property(rig, "scale", Vector3.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ============================================================= CHARACTER BODY =

func _build_body() -> void:
	if not show_body:
		return

	# The canonical player is the rigged 17-joint GLB with Idle/Walk clips.
	# Keep the old character loader only as an offline-development fallback;
	# CI verifies that the real animated asset is present and playing.
	var model := _load_animated_character()
	if model == null:
		var data: Dictionary = CHARACTERS.get_character(character_index)
		if data.is_empty():
			return
		model = ASSETS.build_character_model(
			String(data.get("model", "male_1")),
			data.get("body", Color(0.25, 0.45, 0.70)),
			data.get("accent", Color(0.14, 0.16, 0.22))
		)
	if model == null:
		return

	model.name = "Body"
	ASSETS.fit_to_height(model, ASSETS.CHARACTER_HEIGHT)
	visual_holder.add_child(model)
	visual_holder.register_character(model)

	if name_tag:
		_add_name_tag(model, CHARACTERS.display_name(character_index))

	ASSETS.set_render_layer(model, CHARACTERS.PLAYER_BODY_LAYER)
	camera.cull_mask = camera.cull_mask | (1 << (CHARACTERS.PLAYER_BODY_LAYER - 1))


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


func _add_name_tag(parent: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color(0.95, 0.96, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.06, 0.10, 0.9)
	label.position = Vector3(0.0, ASSETS.CHARACTER_HEIGHT + 0.28, 0.0)
	parent.add_child(label)


func set_character(index: int) -> void:
	character_index = index
	var old := visual_holder.get_node_or_null("Body") as Node3D
	if old != null:
		visual_holder.remove_child(old)
		old.queue_free()
	_build_body()


# =============================================================== INPUT SETUP ==

func _setup_input() -> void:
	_add_key("prev_weapon", KEY_Q)
	_add_key("next_weapon", KEY_E)
	_add_key("reload", KEY_R)
	_add_key("weapon_menu", KEY_G)
	_add_key("sprint", KEY_SHIFT)
	_add_key("crouch", KEY_C)
	_add_key("crouch", KEY_CTRL)
	_add_key("heal", KEY_H)
	_add_key("toggle_map", KEY_M)
	_add_key("eject", KEY_F)
	_add_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse("aim_ads", MOUSE_BUTTON_RIGHT)
	for i in 9:
		_add_key("weapon_slot_%d" % (i + 1), KEY_1 + i)


func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _is_mobile:
		if not is_dead and not _menu_open():
			_rotate_view(event.relative * mouse_sensitivity)
		return

	if event is InputEventScreenTouch:
		var half_width: float = get_viewport().get_visible_rect().size.x * 0.5
		if event.pressed:
			if not is_dead and not _menu_open() and _look_touch == -1 and event.position.x > half_width:
				_look_touch = event.index
		elif event.index == _look_touch:
			_look_touch = -1
		return

	if event is InputEventScreenDrag:
		if not is_dead and not _menu_open() and event.index == _look_touch:
			_rotate_view(event.relative * touch_sensitivity)
		return

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and not _is_mobile:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			if not DisplayServer.get_name().contains("headless") and not _menu_open():
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _menu_open() -> bool:
	return hud != null and hud.has_method("is_menu_open") and hud.is_menu_open()


func _rotate_view(delta_vec: Vector2) -> void:
	if drop_state == DropState.IN_PLANE:
		_orbit_yaw -= delta_vec.x
		_orbit_pitch = clampf(_orbit_pitch - delta_vec.y, deg_to_rad(-68.0), deg_to_rad(12.0))
		rotation.y = _orbit_yaw
		_update_plane_chase_camera()
		return

	var sens_scale := 0.62 if is_aiming else 1.0
	rotate_y(-delta_vec.x * sens_scale)
	var limit := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(_pitch - delta_vec.y * sens_scale, -limit, limit)


# ============================================================ VISUAL MOTION ===

func _process(_delta: float) -> void:
	if visual_holder == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var vertical_speed: float = velocity.y
	var grounded: bool = is_on_floor()
	if drop_state == DropState.IN_PLANE:
		# Plane velocity must not make the passenger play a falling/running pose.
		horizontal_speed = 0.0
		vertical_speed = 0.0
		grounded = true
	visual_holder.set_motion(horizontal_speed, vertical_speed, grounded, run_speed)


# ============================================================ PHYSICS LOOP ====

func _physics_process(delta: float) -> void:
	_process_ep_regen(delta)
	_apply_look_and_stance(delta)
	_sprinting_now = false

	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# ---- Phase 1: Locked inside Elite Cargo Dropship ----
	if drop_state == DropState.IN_PLANE:
		is_firing = false
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("eject") or _jump_requested:
			_jump_requested = false
			_eject_requested = true
		_update_plane_chase_camera()
		return

	var input_dir := _read_move_input()
	var move_dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.0001:
		move_dir = move_dir.normalized()

	# ---- Phase 2: Free-Fall Skydiving ----
	if drop_state == DropState.FREEFALL:
		is_firing = false
		_jump_requested = false
		velocity.x = move_toward(velocity.x, move_dir.x * air_steer_speed, 28.0 * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * air_steer_speed, 28.0 * delta)
		velocity.y = maxf(velocity.y - freefall_gravity * delta, -max_freefall_speed)
		move_and_slide()
		if is_on_floor():
			_complete_landing()
			return
		if global_position.y <= parachute_deploy_height:
			deploy_parachute()
		return

	# ---- Phase 3: Parachute Glide (Y <= 50m -> 5.0 m/s fall speed) ----
	if drop_state == DropState.PARACHUTE:
		is_firing = false
		_jump_requested = false
		velocity.x = move_toward(velocity.x, move_dir.x * parachute_steer_speed, 22.0 * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * parachute_steer_speed, 22.0 * delta)
		velocity.y = -parachute_fall_speed
		move_and_slide()

		if _parachute_rig != null and is_instance_valid(_parachute_rig):
			_chute_sway_time += delta * 2.2
			_parachute_rig.rotation.z = sin(_chute_sway_time) * 0.06 - input_dir.x * 0.14
			_parachute_rig.rotation.x = input_dir.y * 0.12

		if is_on_floor():
			_complete_landing()
			return

		# Safety check if resting on steep rocky geometry without normal floor flag
		if absf(global_position.y - _last_drop_y) < 0.04:
			_drop_stall_timer += delta
			if _drop_stall_timer >= 0.55:
				_complete_landing()
				return
		else:
			_drop_stall_timer = 0.0
		_last_drop_y = global_position.y
		return

	# ---- Phase 4: Landed Normal FPS Combat & Movement ----
	_handle_tactical_keys()
	_handle_weapon_input()
	_handle_firing(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") or _jump_requested:
		if is_crouching:
			set_crouching(false)
		velocity.y = jump_velocity
	_jump_requested = false

	if _sprint_exhausted and ep >= sprint_restart_ep:
		_sprint_exhausted = false
	var sprint_input: bool = Input.is_action_pressed("sprint") or is_sprinting
	var wants_sprint: bool = sprint_input and move_dir.length_squared() > 0.05 \
		and is_on_floor() and not is_aiming and not is_crouching \
		and not is_firing and not Input.is_action_pressed("fire") \
		and ep > 0.0 and not _sprint_exhausted

	var target_speed := move_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_aiming:
		target_speed = move_speed * 0.65
	elif wants_sprint:
		target_speed = run_speed
		_sprinting_now = true
		_bob_time += delta * 11.0
		_drain_sprint_ep(delta)
		if _sprint_exhausted:
			target_speed = move_speed
			_sprinting_now = false

	velocity.x = move_dir.x * target_speed
	velocity.z = move_dir.z * target_speed
	move_and_slide()
	_update_footsteps(delta)


func _read_move_input() -> Vector2:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_forward", "move_backward")
	if hud != null:
		var stick: Vector2 = hud.get_move_vector()
		if stick.length_squared() > input_dir.length_squared():
			input_dir = stick
	if input_dir.length() < 0.14:
		return Vector2.ZERO
	return input_dir.limit_length(1.0)


func _update_footsteps(delta: float) -> void:
	# Horizontal speed avoids gravity/ground-snap velocity triggering idle steps.
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var moving_on_ground: bool = not is_dead and drop_state == DropState.LANDED \
		and is_on_floor() and ground_speed > 0.1
	if not moving_on_ground:
		_step_timer = 0.0
		return

	_step_timer += delta
	var step_interval: float = 0.25 if _sprinting_now else 0.4
	if _step_timer >= step_interval:
		_step_timer = fmod(_step_timer, step_interval)
		if footstep_audio != null:
			footstep_audio.play()


func _drain_sprint_ep(delta: float) -> void:
	var previous_ep: float = ep
	ep = maxf(0.0, ep - sprint_ep_drain * delta)
	if int(round(previous_ep)) != int(round(ep)):
		ep_changed.emit(int(round(ep)))
	if ep <= 0.0:
		_sprint_exhausted = true
		set_sprinting(false)


func _process_ep_regen(delta: float) -> void:
	if is_dead or _sprinting_now or ep <= 0.0 or health >= max_health:
		return
	var step := minf(ep, ep_regen_rate * delta)
	ep = maxf(0.0, ep - step)
	_ep_accum += step
	if _ep_accum >= 1.0:
		var gain := int(floor(_ep_accum))
		_ep_accum -= float(gain)
		health = mini(max_health, health + gain)
		health_changed.emit(health)
	ep_changed.emit(int(round(ep)))


func _apply_look_and_stance(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 1.8)
	var limit := deg_to_rad(pitch_limit_deg)
	head.rotation = Vector3(clampf(_pitch + _recoil, -limit, limit), 0.0, 0.0)

	# Smooth head crouch height transition
	var target_head_y := crouch_head_y if (is_crouching and drop_state == DropState.LANDED) else stand_head_y
	head.position.y = lerpf(head.position.y, target_head_y, minf(1.0, delta * 12.0))

	# SpringArm3D handles wall collision; only its desired length is smoothed here.
	var target_spring_length := ads_spring_length if (is_aiming and drop_state == DropState.LANDED) else hip_spring_length
	spring_arm.spring_length = lerpf(
		spring_arm.spring_length, target_spring_length, minf(1.0, delta * camera_lerp_speed)
	)

	# Smooth ADS / Sprint / Base FOV transition
	var target_fov := base_fov
	if drop_state == DropState.FREEFALL:
		target_fov = 88.0
	elif is_aiming and drop_state == DropState.LANDED:
		target_fov = ads_fov
	elif _sprinting_now and velocity.length() > move_speed + 0.5:
		target_fov = sprint_fov
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 11.0))

	# World-space weapon follows the chest/head in TPV (not the chase camera).
	_kick = move_toward(_kick, 0.0, delta * 6.5)
	var target_holder := Vector3(0.26, -0.16, -0.50) if is_aiming else _holder_base
	var bob := Vector3.ZERO
	if not is_aiming and velocity.length() > move_speed + 0.5 and is_on_floor():
		bob = Vector3(sin(_bob_time) * 0.018, absf(cos(_bob_time)) * 0.014, 0.0)
	weapon_holder.position = weapon_holder.position.lerp(
		target_holder + bob + Vector3(0.0, 0.012 * _kick, gun_kick * _kick),
		minf(1.0, delta * 16.0)
	)
	weapon_holder.rotation = Vector3(deg_to_rad(-4.0 * _kick), 0.0, 0.0)


# ====================================================== TACTICAL & WEAPON API =

func _handle_tactical_keys() -> void:
	if Input.is_action_just_pressed("aim_ads") and not _is_mobile:
		toggle_aim()
	if Input.is_action_just_pressed("crouch"):
		toggle_crouch()
	if Input.is_action_just_pressed("heal"):
		use_medkit()
	if Input.is_action_just_pressed("toggle_map") and hud != null and hud.has_method("toggle_full_map"):
		hud.toggle_full_map()


func _handle_weapon_input() -> void:
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return
	if Input.is_action_just_pressed("next_weapon"):
		weapon_manager.next_weapon()
	if Input.is_action_just_pressed("prev_weapon"):
		weapon_manager.prev_weapon()
	if Input.is_action_just_pressed("reload"):
		weapon_manager.start_reload()
	if Input.is_action_just_pressed("weapon_menu") and hud != null and hud.has_method("toggle_weapon_menu"):
		hud.toggle_weapon_menu()
	for i in 9:
		if Input.is_action_just_pressed("weapon_slot_%d" % (i + 1)):
			weapon_manager.switch_weapon(i)


func set_aiming(active: bool) -> void:
	if is_dead or drop_state != DropState.LANDED:
		active = false
	if is_aiming == active:
		return
	is_aiming = active
	aim_changed.emit(is_aiming)


func toggle_aim() -> void:
	set_aiming(not is_aiming)


func set_crouching(active: bool) -> void:
	if is_dead or drop_state != DropState.LANDED:
		active = false
	if is_crouching == active:
		return
	is_crouching = active
	crouch_changed.emit(is_crouching)


func toggle_crouch() -> void:
	set_crouching(not is_crouching)


func set_sprinting(state: bool) -> void:
	if state and (is_dead or drop_state != DropState.LANDED or ep <= 0.0 or _sprint_exhausted):
		state = false
	is_sprinting = state
	# Always acknowledge so HUD state cannot remain ON if activation was rejected.
	sprint_changed.emit(is_sprinting)


func use_medkit() -> bool:
	if is_dead or medkits <= 0:
		return false
	if health >= max_health and ep >= float(max_ep):
		# Even at full HP/EP, reward tactile feedback in UI tests if damaged otherwise keep medkit
		return false
	medkits -= 1
	health = mini(max_health, health + medkit_heal_hp)
	ep = minf(float(max_ep), ep + float(medkit_heal_ep))
	health_changed.emit(health)
	ep_changed.emit(int(round(ep)))
	medkits_changed.emit(medkits)
	if hud != null and hud.has_method("flash_heal"):
		hud.flash_heal()
	return true


func add_ep(amount: int) -> void:
	if is_dead:
		return
	ep = clampf(ep + float(amount), 0.0, float(max_ep))
	ep_changed.emit(int(round(ep)))


func grant_medkit(amount: int = 1) -> void:
	medkits += maxi(0, amount)
	medkits_changed.emit(medkits)


func switch_weapon_next() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.next_weapon()


func switch_weapon_prev() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.prev_weapon()


func switch_weapon_idx(index: int) -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.switch_weapon(index)


func get_weapon_index() -> int:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		return weapon_manager.current_index
	return 0


# =============================================================== SHOOTING =====

func _handle_firing(delta: float) -> void:
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return
	if drop_state != DropState.LANDED or _menu_open():
		is_firing = false
		_trigger_ready = true
		return

	var wants_fire: bool = is_firing
	if not _is_mobile:
		if Input.is_action_just_pressed("fire"):
			_trigger_ready = true
		if Input.is_action_pressed("fire"):
			wants_fire = true

	if not wants_fire:
		if not weapon_manager.is_auto():
			_fire_timer = 0.0
		return

	if not weapon_manager.is_auto() and not _trigger_ready:
		return

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		shoot()


func shoot() -> void:
	if is_dead or drop_state != DropState.LANDED:
		return
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return

	if not weapon_manager.can_shoot():
		if not weapon_manager.reloading:
			weapon_manager.start_reload()
		return

	if shoot_audio != null:
		shoot_audio.play()
	if is_sprinting:
		set_sprinting(false)
	var weapon: Dictionary = weapon_manager.get_current()
	var pellets: int = maxi(1, int(weapon.get("pellets", 1)))
	var damage: float = float(weapon.get("damage", 10.0))
	var spread: float = float(weapon.get("spread", 0.6))
	if is_aiming:
		spread *= 0.35
	if is_crouching:
		spread *= 0.70

	# The center-screen crosshair defines the camera ray in third-person view.
	var crosshair: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var aim: Vector3 = camera.project_ray_normal(crosshair).normalized()
	# Gun position is visual-only; it is never an input to the damage ray.
	var muzzle_position: Vector3 = _get_muzzle_position()
	for i in pellets:
		var end_point: Vector3 = _fire_hitscan(aim, spread, damage)
		if effects_pool != null and is_instance_valid(effects_pool):
			effects_pool.spawn_tracer(muzzle_position, end_point)

	weapon_manager.consume_ammo()
	shots_fired += 1
	get_tree().call_group("enemy", "hear_gunshot", global_position, self)
	_fire_timer = weapon_manager.get_fire_delay()
	_trigger_ready = false

	var recoil_deg: float = float(weapon.get("recoil", 1.0))
	if is_aiming:
		recoil_deg *= 0.55
	if is_crouching:
		recoil_deg *= 0.75
	_recoil += deg_to_rad(recoil_deg)
	_kick = minf(1.5, recoil_deg)
	if effects_pool != null and is_instance_valid(effects_pool):
		effects_pool.spawn_muzzle_flash(muzzle_position, muzzle_flash_time)
	Input.vibrate_handheld(25)


## Immediate hitscan from Camera3D's center-screen crosshair. The Player RID is
## excluded in _ready(), and no gun/chest position participates in this query.
## Returns only the visual tracer endpoint; damage has already been applied.
func _fire_hitscan(aim: Vector3, spread_deg: float, damage: float) -> Vector3:
	var dir: Vector3 = aim
	if spread_deg > 0.0:
		var spread: float = deg_to_rad(spread_deg)
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
		dir = dir.rotated(camera.global_transform.basis.x, randf_range(-spread, spread))
		dir = dir.normalized()

	var crosshair: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var camera_origin: Vector3 = camera.project_ray_origin(crosshair)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_camera_ray.from = camera_origin
	_camera_ray.to = camera_origin + dir * hitscan_range
	var hit: Dictionary = space.intersect_ray(_camera_ray)
	var end_point: Vector3 = _camera_ray.to
	if hit.is_empty():
		return end_point

	end_point = hit.get("position", end_point)
	var collider = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group("enemy"):
		if collider.has_method("take_damage"):
			collider.take_damage(damage, self)
		elif collider.has_method("die"):
			collider.die()
	if collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & 1) != 0:
		if effects_pool != null and is_instance_valid(effects_pool):
			var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
			effects_pool.spawn_bullet_hole(end_point, hit_normal)
	return end_point


func _get_muzzle_position() -> Vector3:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		var muzzle = weapon_manager.muzzle
		if muzzle is Node3D and is_instance_valid(muzzle):
			return (muzzle as Node3D).global_position
	return weapon_holder.to_global(Vector3(0.0, 0.0, -0.6))


func start_firing() -> void:
	if is_dead or drop_state != DropState.LANDED or _menu_open():
		return
	if is_sprinting:
		set_sprinting(false)
	is_firing = true
	_trigger_ready = true
	_fire_timer = 0.0


func stop_firing() -> void:
	is_firing = false


func request_jump() -> void:
	if is_dead:
		return
	if drop_state == DropState.IN_PLANE:
		_eject_requested = true
		return
	_jump_requested = true


# ================================================================== DAMAGE ====

func take_damage(amount: int) -> void:
	if is_dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health)
	Input.vibrate_handheld(80)
	if hud != null and hud.has_method("flash_damage"):
		hud.flash_damage()
	if health <= 0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_firing = false
	set_sprinting(false)
	is_aiming = false
	velocity = Vector3.ZERO
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.cancel_reload()
	if not _is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	died.emit()
