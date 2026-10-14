extends CharacterBody3D
##
## Player (FPS)
## PC   : WASD chalne ke liye, mouse se dekhna, left-click se firing, Space = jump
## Mobile: left joystick chalne ke liye, right half pe swipe se dekhna,
##         FIRE / JUMP buttons HUD se aate hain.
##

signal health_changed(health: int)
signal died

const BULLET_SCENE := preload("res://scenes/bullet.tscn")

@export_group("Movement")
@export var move_speed: float = 6.0           ## m/s
@export var jump_velocity: float = 4.8
@export var gravity: float = 18.0

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var touch_sensitivity: float = 0.005
@export var pitch_limit_deg: float = 85.0

@export_group("Combat")
@export var max_health: int = 100             ## spec: start 100 HP
@export var fire_cooldown: float = 0.14       ## auto-fire ka gap
@export var bullet_speed: float = 55.0
@export var bullet_damage: float = 10.0
@export var gun_kick: float = 0.06            ## gun ka chhota recoil

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gun: Node3D = $Head/Camera3D/Gun

var health: int = 100
var is_dead: bool = false
var is_firing: bool = false

# main.gd ye do set karta hai (HUD + bullets ka parent node)
var hud = null
var bullet_parent = null

var _pitch: float = 0.0
var _recoil: float = 0.0
var _kick: float = 0.0
var _gun_base_pos: Vector3 = Vector3.ZERO
var _fire_timer: float = 0.0
var _jump_requested: bool = false
var _look_touch: int = -1
var _is_mobile: bool = false


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_is_mobile = OS.has_feature("mobile")
	_gun_base_pos = gun.position

	# PC pe mouse ko capture karo (ESC se free hota hai)
	if not _is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ------------------------------------------------------------------ input ----

func _unhandled_input(event: InputEvent) -> void:
	# ---------- PC: mouse se dekhna ----------
	if event is InputEventMouseMotion and not _is_mobile:
		if not is_dead:
			_rotate_view(event.relative * mouse_sensitivity)
		return

	# ---------- Mobile: screen ke right half pe swipe = look ----------
	if event is InputEventScreenTouch:
		var half_width: float = get_viewport().get_visible_rect().size.x * 0.5
		if event.pressed:
			if not is_dead and _look_touch == -1 and event.position.x > half_width:
				_look_touch = event.index
		elif event.index == _look_touch:
			_look_touch = -1
	elif event is InputEventScreenDrag:
		if not is_dead and event.index == _look_touch:
			_rotate_view(event.relative * touch_sensitivity)

	# ---------- PC: ESC = mouse free, click = wapas capture ----------
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and not _is_mobile:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _rotate_view(delta_vec: Vector2) -> void:
	rotate_y(-delta_vec.x)   # left/right -> body ghumti hai
	var limit := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(_pitch - delta_vec.y, -limit, limit)   # up/down -> sir ghumta hai


# ---------------------------------------------------------------- physics ----

func _physics_process(delta: float) -> void:
	_apply_look(delta)

	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# ---- firing (gun dabaya rahe to lagatar chalti hai) ----
	var wants_fire: bool = is_firing
	if not _is_mobile and Input.is_action_pressed("fire"):
		wants_fire = true
	if wants_fire:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = fire_cooldown
			shoot()

	# ---- movement input (keyboard + joystick) ----
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_forward", "move_backward")

	if hud != null:
		var stick: Vector2 = hud.get_move_vector()
		if stick.length_squared() > input_dir.length_squared():
			input_dir = stick
	if input_dir.length() < 0.15:      # dead-zone
		input_dir = Vector2.ZERO
	input_dir = input_dir.limit_length(1.0)

	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	# ---- gravity + jump ----
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") or _jump_requested:
		velocity.y = jump_velocity
	_jump_requested = false

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()


## Camera ka pitch + recoil har frame lagana
func _apply_look(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 1.6)
	var limit := deg_to_rad(pitch_limit_deg)
	head.rotation = Vector3(clampf(_pitch + _recoil, -limit, limit), 0.0, 0.0)

	_kick = move_toward(_kick, 0.0, delta * 6.0)
	gun.position = _gun_base_pos + Vector3(0.0, 0.0, gun_kick * _kick)


# ---------------------------------------------------------------- shooting --

func shoot() -> void:
	if is_dead or bullet_parent == null or not is_instance_valid(bullet_parent):
		return

	var dir: Vector3 = -camera.global_transform.basis.z.normalized()
	# chhota sa spread, taaki firing natural lage
	var spread := deg_to_rad(1.0)
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	dir = dir.rotated(camera.global_transform.basis.x, randf_range(-spread, spread))
	dir = dir.normalized()

	var bullet = BULLET_SCENE.instantiate()
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	bullet.shooter = self
	bullet_parent.add_child(bullet)
	bullet.global_position = camera.global_position + dir * 0.9
	bullet.face_direction()

	_recoil += deg_to_rad(0.7)
	_kick = 1.0
	Input.vibrate_handheld(30)   # mobile pe halki vibration


# ---------------------------------------------------- HUD se aane wale calls -

func start_firing() -> void:
	if is_dead:
		return
	is_firing = true
	_fire_timer = 0.0     # pehli goli turant


func stop_firing() -> void:
	is_firing = false


func request_jump() -> void:
	if not is_dead:
		_jump_requested = true


# ------------------------------------------------------------------ damage ---

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
	velocity = Vector3.ZERO
	if not _is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # restart button click ho sake
	died.emit()
