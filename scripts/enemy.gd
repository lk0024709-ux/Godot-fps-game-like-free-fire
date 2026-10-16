extends CharacterBody3D
##
## Enemy (dushman)
## Player ki taraf chalta hai, paas aakar thoda-thoda damage deta hai.
## 200 HP hai (har gun ka damage alag hai — shotgun ke 14 per pellet se lekar
## M82B sniper ke 120 tak, isliye HP itna rakha: pistol ~7, SMG ~10, rifle 4-5
## aur sniper 2-3 goli lete hain. Chhoti-badi gun ka farq saaf mehsoos hota hai.)
## Value badalni ho to neeche sirf max_health ka number badal do.
## Marne pe main.gd +10 score deta hai (signal "died" ke through).
##
## BODY (Phase 4): pehle yahan ek rang-biranga CAPSULE box tha. Ab downloaded CC0
## character model (male_1..male_5 / female_1..female_5 me se random) lagta hai,
## uspe gehra laal tint (0.55, 0.12, 0.12), height 1.8m, aur chalte waqt
## haath-pair sine-wave se hilte hain. Model na mile to kuch nahi lagta —
## phir bhi poora gameplay (chase/attack/damage/score) chalta rehta hai.
##

signal died(enemy: Node3D)

const ASSETS := preload("res://scripts/assets.gd")
const CHARACTERS := preload("res://scripts/character_data.gd")

@export_group("Stats")
@export var max_health: float = 200.0
@export var move_speed: float = 2.6
@export var gravity: float = 18.0

@export_group("Attack")
@export var touch_damage: int = 10      ## spec: enemy touch = -10 HP
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.0
@export var stop_distance: float = 1.2  ## itna paas aa kar ruk jaata hai

@export_group("Body")
@export var show_name: bool = true      ## sar ke upar naam (Label3D)
@export var flash_time: float = 0.12    ## goli lagne pe laal chamak
@export var animation_speed: float = 7.0  ## chalte waqt haath-pair ki raftaar

@onready var wall_check: RayCast3D = $WallCheck

var health: float = 200.0
var is_dead: bool = false

var _player = null                     ## dynamic (player.gd wala node)
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _attack_timer: float = 0.0
var _flash_timer: float = 0.0
var _avoid_side: float = 1.0

# ---- body (downloaded character model) ----
var _body: Node3D = null               ## poora character model
var _leg_l: Node3D = null              ## sub-mesh nodes (GLB me naam fixed hain)
var _leg_r: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _walk_phase: float = 0.0
var _moving: bool = false
var _character_name: String = ""


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_avoid_side = 1.0 if randf() < 0.5 else -1.0

	_build_body()
	_find_player()


## Random character model se dushman ka body banao (gehra laal tint).
## Sab kuch fail-soft hai: model na mile to _body null reh jata hai.
func _build_body() -> void:
	var pick: String = CHARACTERS.ENEMY_POOL[
			randi() % CHARACTERS.ENEMY_POOL.size()]
	var model := ASSETS.build_character_model(pick,
			Color(0.60, 0.20, 0.18),                     # bina model wale fallback ke rang
			Color(0.30, 0.12, 0.12),
			CHARACTERS.ENEMY_TINT)                       # spec: (0.55, 0.12, 0.12)
	if model == null:
		# asset nahi mila -> procedural humanoid (dushman kabhi invisible nahi rehta)
		model = ASSETS.fallback_character(Color(0.60, 0.20, 0.18), Color(0.30, 0.12, 0.12),
				CHARACTERS.ENEMY_TINT)
		_character_name = "Dushman"

	model.name = "Body"
	add_child(model)
	_body = model

	# 1.8m + pair zameen pe (downloaded model already 1.8m hota hai — safety net)
	ASSETS.fit_to_height(model, CHARACTERS.ENEMY_HEIGHT)

	# haath-pair ke nodes (GLB me naam: leg_l, leg_r, arm_l, arm_r)
	_leg_l = model.find_child("leg_l", true, false) as Node3D
	_leg_r = model.find_child("leg_r", true, false) as Node3D
	_arm_l = model.find_child("arm_l", true, false) as Node3D
	_arm_r = model.find_child("arm_r", true, false) as Node3D

	if _character_name.is_empty():
		_character_name = pick.capitalize().replace("_", " ")
	if show_name:
		_add_name_tag(model)
	_collect_flash_materials(model)


## Sar ke upar chhota naam — player ko pata chale kaunsa dushman hai
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


## Body ke saare materials ikattha karo taaki goli lagne pe laal flash ho sake
func _collect_flash_materials(node: Node) -> void:
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

	_moving = move_dir.length_squared() > 0.01
	_animate_limbs(delta)

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	move_and_slide()


## Chalte waqt haath-pair hilana (sine wave). Model na ho to kuch nahi hota.
## Har limb ka node apne pivot pe hai (tools/fbx2glb.py character ke chhote tukde
## banata hai: leg_l/leg_r ka pivot kamar pe, arm_l/arm_r ka pivot kandhe pe).
func _animate_limbs(delta: float) -> void:
	if _body == null:
		return
	var speed := animation_speed if _moving else 1.6
	_walk_phase += delta * speed
	var leg_swing := sin(_walk_phase) * (0.55 if _moving else 0.05)
	var arm_swing := -leg_swing * 0.7

	if _leg_l != null:
		_leg_l.rotation.x = leg_swing
	if _leg_r != null:
		_leg_r.rotation.x = -leg_swing
	if _arm_l != null:
		_arm_l.rotation.x = arm_swing
	if _arm_r != null:
		_arm_r.rotation.x = -arm_swing


# ---------------------------------------------------------------- damage ----

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	_set_flash(true)
	_flash_timer = flash_time
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
