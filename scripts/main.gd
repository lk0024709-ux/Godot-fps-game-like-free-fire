extends Node3D
##
## Main (game manager)
## - Arena banata hai: zameen + chaaron taraf deewar + cover boxes (sab code se,
##   koi asset nahi)
## - Enemies spawn karta hai
## - Score (+10 per kill) aur Game Over handle karta hai
##

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Assets := preload("res://scripts/assets.gd")

@export_group("Enemy Spawning")
@export var spawn_interval: float = 1.8          ## kitne second me naya enemy
@export var fastest_spawn_interval: float = 0.9  ## max difficulty pe itna fast
@export var max_enemies: int = 8                 ## ek waqt me itne enemies
@export var min_spawn_distance: float = 9.0      ## player se itni door spawn

@export_group("Arena")
@export var arena_size: float = 40.0             ## maidan kitna bada (40 = 40x40m, 20 = 20x20m)

@export_group("Nature")
## Ye seed fix hai — isliye har baar wahi ped/patthar/ghaas wahi jagah pe ugte hain.
## Badal ke dekho: pura layout badal jayega (par phir bhi deterministic rahega).
@export var nature_seed: int = 20241015
@export var tree_count: int = 14                 ## ped (deewar ke paas patti me)
@export var rock_count: int = 10                 ## patthar
@export var bush_count: int = 12                 ## jhaadiyaan
@export var grass_count: int = 26                ## ghaas ke guchhe (inme collision nahi hota)

## Neeche wala layout isi 40x40 ke hisaab se likha hai. arena_size badloge to
## sab kuch (deewarein + cover boxes + spawn ghere) automatically scale ho jayega.
const ARENA_REFERENCE: float = 40.0

@onready var player = $Player
@onready var hud = $HUD
@onready var enemy_container: Node3D = $Enemies
@onready var bullet_container: Node3D = $Bullets
@onready var spawn_timer: Timer = $SpawnTimer

var score: int = 0
var game_over: bool = false

## Cover / deewar ka layout: [position, size, colour]
var _obstacles := [
	# --- chaaron taraf ki boundary (arena se bahar na ja sako) ---
	[Vector3(0, 1.25, -20), Vector3(40, 2.5, 0.6), Color(0.30, 0.32, 0.36)],
	[Vector3(0, 1.25, 20), Vector3(40, 2.5, 0.6), Color(0.30, 0.32, 0.36)],
	[Vector3(-20, 1.25, 0), Vector3(0.6, 2.5, 40), Color(0.30, 0.32, 0.36)],
	[Vector3(20, 1.25, 0), Vector3(0.6, 2.5, 40), Color(0.30, 0.32, 0.36)],
	# --- andar ke cover boxes (lakdi ke crate) ---
	[Vector3(-6, 1.0, -5), Vector3(2, 2, 2), Color(0.62, 0.42, 0.22)],
	[Vector3(-6, 3.05, -5), Vector3(1.3, 1.3, 1.3), Color(0.70, 0.50, 0.26)],
	[Vector3(7, 1.0, 4), Vector3(2, 2, 2), Color(0.62, 0.42, 0.22)],
	[Vector3(14, 1.0, -14), Vector3(3, 2, 2), Color(0.62, 0.42, 0.22)],
	[Vector3(-13, 1.0, 13), Vector3(2, 2, 3), Color(0.62, 0.42, 0.22)],
	# --- concrete walls (nichi, aar-paar dekhne ke liye) ---
	[Vector3(0, 0.8, -11), Vector3(10, 1.6, 0.6), Color(0.55, 0.55, 0.58)],
	[Vector3(0, 0.8, 11), Vector3(10, 1.6, 0.6), Color(0.55, 0.55, 0.58)],
	[Vector3(-11, 0.8, 0), Vector3(0.6, 1.6, 10), Color(0.55, 0.55, 0.58)],
	[Vector3(11, 0.8, 0), Vector3(0.6, 1.6, 10), Color(0.55, 0.55, 0.58)],
	# --- pillars ---
	[Vector3(4, 1.5, -4), Vector3(1.2, 3, 1.2), Color(0.45, 0.47, 0.5)],
	[Vector3(-4, 1.5, 4), Vector3(1.2, 3, 1.2), Color(0.45, 0.47, 0.5)],
]


func _ready() -> void:
	_build_arena()

	# player ko HUD aur bullet-container de do
	player.hud = hud
	player.bullet_parent = bullet_container

	# weapon system ka display (gun ka naam + ammo + gun-picker) HUD pe
	hud.bind_weapon_manager(player.weapon_manager)

	# HUD -> player / main
	hud.fire_pressed.connect(player.start_firing)
	hud.fire_released.connect(player.stop_firing)
	hud.jump_pressed.connect(player.request_jump)
	hud.restart_pressed.connect(_restart)

	# player -> HUD / main
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)

	# HP bar player ke max_health ke hisaab se (player.gd me max_health badlo to bar bhi sahi)
	hud.set_max_health(player.max_health)
	hud.set_health(player.health)
	hud.set_score(score)

	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.start()
	_spawn_enemy()


# ------------------------------------------------------------- arena banana --

func _build_arena() -> void:
	# ---- zameen ----
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena_size, arena_size)
	plane.material = _make_ground_material()
	ground_mesh.mesh = plane
	ground.add_child(ground_mesh)

	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(arena_size, 1.0, arena_size)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)

	add_child(ground)

	# ---- cover boxes / deewarein ----
	# layout 40x40 ke hisaab se likha hai, isliye chhote/bade maidan ke liye scale
	var scale_factor: float = arena_size / ARENA_REFERENCE
	for item in _obstacles:
		_add_box((item[0] as Vector3) * scale_factor, (item[1] as Vector3) * scale_factor, item[2])

	# ---- nature: ped / patthar / jhaadi / ghaas (hybrid: download ya procedural) ----
	_scatter_nature()


# ------------------------------------------------------------- nature props --

## Ped / patthar / jhaadi / ghaas ko maidan ke kinare wali patti me bikher deta hai.
##
## Deterministic: `nature_seed` fix hai, isliye har run me SAME layout banta hai.
## Saare props deewar ke paas wali patti me rakhe jaate hain (beech ka khel ka maidan
## khula rehta hai) — enemies ke spawn ring (radius 0.4 * arena_size) se bahar.
##
## Har prop pehle "downloaded CC0 model" try karta hai, warna procedural shape
## (dekho scripts/assets.gd + scripts/asset_loader.gd). Download fail ho to ye
## function wahi kaam procedural se kar deta hai — koi error nahi.
func _scatter_nature() -> void:
	var arena_scale: float = arena_size / ARENA_REFERENCE
	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed

	var inner_radius: float = arena_size * 0.5 - 1.3        # deewar se thoda andar
	var band_min: float = inner_radius * 0.86               # ped/patthar isi patti me
	# chhote maidan me itne hi props lagao (warna bhare-bhare lagega)
	var area_scale: float = maxf(0.3, arena_scale * arena_scale)

	var container := Node3D.new()
	container.name = "Nature"
	add_child(container)

	var kinds := {
		"tree": [tree_count, 0.95, 1.35, 1.0],
		"rock": [rock_count, 0.85, 1.30, 1.0],
		"bush": [bush_count, 0.90, 1.40, 1.0],
		"grass": [grass_count, 0.85, 1.55, 0.62],   # ghaas thodi andar tak bhi aa sakti hai
	}

	for kind in ["tree", "rock", "bush", "grass"]:
		var spec: Array = kinds[kind]
		var total: int = maxi(4, int(float(spec[0]) * area_scale))
		var min_scale: float = float(spec[1])
		var max_scale: float = float(spec[2])
		var band_factor: float = float(spec[3])

		for i in total:
			var angle := rng.randf() * TAU
			var radius := rng.randf_range(inner_radius * band_factor, inner_radius)
			var prop: Node3D = _make_prop(kind, i % 5, rng.randf_range(min_scale, max_scale) * arena_scale)
			if prop == null:
				continue
			prop.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			prop.rotation.y = rng.randf() * TAU      # halka ghumav, natural lage
			container.add_child(prop)


## Ek nature prop banao (kind ke hisaab se assets.gd ka function)
func _make_prop(kind: String, variant: int, scale_f: float) -> Node3D:
	match kind:
		"tree":
			return Assets.tree(scale_f, variant)
		"rock":
			return Assets.rock(scale_f, variant)
		"bush":
			return Assets.bush(scale_f, variant)
		"grass":
			return Assets.grass_tuft(scale_f, variant)
	return null


func _add_box(box_pos: Vector3, box_size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = box_pos
	body.collision_layer = 1

	var mesh_node := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	box_mesh.material = mat
	mesh_node.mesh = box_mesh
	body.add_child(mesh_node)

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	shape_node.shape = shape
	body.add_child(shape_node)

	add_child(body)


## Zameen pe grid pattern (chhota sa procedural shader — koi image nahi)
func _make_ground_material() -> Material:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.17, 0.21, 0.19);
uniform vec3 line_color : source_color = vec3(0.33, 0.45, 0.36);
uniform float tiles = 20.0;

void fragment() {
	vec2 grid = abs(fract(UV * tiles) - 0.5);
	float dist_to_line = min(grid.x, grid.y);
	float is_line = smoothstep(0.02, 0.07, dist_to_line);
	ALBEDO = mix(line_color, base_color, is_line);
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


# ------------------------------------------------------------- enemy spawn --

func _on_spawn_timer_timeout() -> void:
	if game_over:
		return
	if enemy_container.get_child_count() >= max_enemies:
		return

	_spawn_enemy()

	# jitne zyada kill, utna tez spawn (difficulty)
	spawn_timer.wait_time = maxf(fastest_spawn_interval, spawn_interval - float(score) * 0.0015)


func _spawn_enemy() -> void:
	var enemy = ENEMY_SCENE.instantiate()
	enemy.died.connect(_on_enemy_died)
	enemy_container.add_child(enemy)
	enemy.global_position = _pick_spawn_position()


## Arena ke kinare wale 8 points me se wo chuno jo player se door ho
func _pick_spawn_position() -> Vector3:
	var points := _spawn_points()
	points.shuffle()
	var player_pos: Vector3 = player.global_position
	# chhote maidan me spawn points player ke paas aa jate hain, isliye safe distance
	var safe_distance: float = minf(min_spawn_distance, arena_size * 0.35)
	for p in points:
		var flat_distance: float = Vector2(p.x - player_pos.x, p.z - player_pos.z).length()
		if flat_distance > safe_distance:
			return p
	return points[0]


func _spawn_points() -> Array:
	var out: Array = []
	var radius := arena_size * 0.4      # 40 ka maidan -> 16m pe spawn
	for i in 8:
		var angle := TAU * float(i) / 8.0
		out.append(Vector3(cos(angle) * radius, 0.3, sin(angle) * radius))
	return out


# -------------------------------------------------------- score / game over --

func _on_enemy_died(_enemy) -> void:
	if game_over:
		return
	score += 10                       # spec: har kill = +10 score
	hud.set_score(score)


func _on_player_died() -> void:
	if game_over:
		return
	game_over = true
	spawn_timer.stop()
	player.stop_firing()
	hud.show_game_over(score)


func _restart() -> void:
	get_tree().reload_current_scene()
