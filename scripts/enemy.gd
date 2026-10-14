extends CharacterBody3D
##
## Enemy (dushman)
## Player ki taraf chalta hai, paas aakar thoda-thoda damage deta hai.
## 100 HP hai (weapon system aane ke baad har gun ka damage alag hai — pistol
## 30 se lekar M82B ke 120 tak — isliye HP badhaya, warna sab ek hi goli me marte).
## 20 HP wapas chahiye to neeche max_health = 20.0 kar do.
## Marne pe main.gd +10 score deta hai (signal "died" ke through).
##

signal died(enemy: Node3D)

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 2.6
@export var gravity: float = 18.0

@export_group("Attack")
@export var touch_damage: int = 10      ## spec: enemy touch = -10 HP
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.0
@export var stop_distance: float = 1.2  ## itna paas aa kar ruk jaata hai

@onready var body_mesh: MeshInstance3D = $Body
@onready var head_mesh: MeshInstance3D = $Head
@onready var wall_check: RayCast3D = $WallCheck

var health: float = 100.0
var is_dead: bool = false

var _player = null                     ## dynamic (player.gd wala node)
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _attack_timer: float = 0.0
var _flash_timer: float = 0.0
var _avoid_side: float = 1.0


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_avoid_side = 1.0 if randf() < 0.5 else -1.0

	# Har enemy ka apna material copy -> sirf wahi enemy laal flash kare
	for mesh in [body_mesh, head_mesh]:
		var mat := mesh.get_active_material(0)
		if mat != null:
			var copy := mat.duplicate() as StandardMaterial3D
			if copy != null:
				mesh.material_override = copy
				_materials.append(copy)
				_base_colors.append(copy.albedo_color)

	_find_player()


func _find_player() -> void:
	var list := get_tree().get_nodes_in_group("player")
	_player = list[0] if list.size() > 0 else null
	if wall_check != null and _player is CollisionObject3D:
		# wall-ray ko player ignore kare warna paas aate hi ruk jayega
		wall_check.add_exception(_player)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# ---- hit-flash wapas normal ----
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)

	# ---- gravity ----
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# ---- player dhundo (agar mar gaya / scene reload hua) ----
	if _player == null or not is_instance_valid(_player):
		_find_player()

	var move_dir := Vector3.ZERO
	var player_dead := false
	if _player != null and is_instance_valid(_player):
		player_dead = bool(_player.is_dead)

	if _player != null and not player_dead:
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()

		if dist > stop_distance:
			move_dir = to_player.normalized()
			# deewar aa gayi to side se nikalne ki koshish (simple avoidance)
			if wall_check != null and wall_check.is_colliding():
				move_dir = move_dir.rotated(Vector3.UP, deg_to_rad(55.0) * _avoid_side)

		# player ki taraf muh
		if dist > 0.3:
			var look_target := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
			if global_position.distance_squared_to(look_target) > 0.001:
				look_at(look_target, Vector3.UP)

		# ---- attack (touch) ----
		_attack_timer -= delta
		if dist <= attack_range and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			if _player.has_method("take_damage"):
				_player.take_damage(touch_damage)

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	move_and_slide()


# ---------------------------------------------------------------- damage ----

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	_set_flash(true)
	_flash_timer = 0.12
	if health <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	died.emit(self)
	queue_free()


func _set_flash(on: bool) -> void:
	for i in _materials.size():
		var mat: StandardMaterial3D = _materials[i]
		mat.albedo_color = Color(1.0, 0.3, 0.25) if on else _base_colors[i]
		mat.emission_enabled = on
		if on:
			mat.emission = Color(1.0, 0.25, 0.2)
