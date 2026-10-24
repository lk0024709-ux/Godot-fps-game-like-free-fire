extends Node3D
##
## Main (Battle Royale Game Manager) — Map: "Rannbhoomi"
##
## Orchestrates:
##   1. Task 1 — Land Map Assembly (Grass Terrain, Central 15m Plateau, Grand Rajasthani Mahal
##      at (0, 15, 0), all 11 Modular Buildings in named POIs, NW Aravalli Mountain, Trimesh collisions,
##      plus grounded vehicles & MultiMesh nature scatter).
##   2. Task 2 — Elite Cargo Plane Drop (plane_cargo_elite.glb at Y=300m on NW edge, straight-line
##      flight at 50.0 m/s, player locked inside initially, EJECT button + 15.0s auto-eject,
##      free-fall, parachute auto-deploy at Y=50m -> 5.0 m/s, clean landing -> normal TPV).
##   3. Task 3 — Live HUD telemetry binding (RANNBHOOMI Minimap + Rotating Arrow, Top-Center Compass,
##      HP & EP bars, Backpack, Heal, Fire, Aim, Jump, Crouch, Reload, Multi-touch).
##

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Assets := preload("res://scripts/assets.gd")
const AssetLoader := preload("res://scripts/asset_loader.gd")
const MapData := preload("res://scripts/map_data.gd")
const RannbhoomiBuilder := preload("res://scripts/rannbhoomi_builder.gd")

const MAP_ID := "Veergarh"
const NATURE_CELL_SIZE: float = 250.0
const PLANE_HOLD_OFFSET := Vector3(0.0, 2.75, 11.5)

@export_group("Plane Drop")
@export var plane_drop_enabled: bool = true
@export var plane_altitude: float = 300.0
@export var plane_speed: float = 50.0
@export var auto_eject_time: float = 15.0
## NW island coastline edge (-530.33, 300, -530.33) -> exact 750.0m (= 50 m/s * 15s) to Center Mahal (0, 15, 0)!
@export var plane_start: Vector3 = Vector3(-530.33, 300.0, -530.33)
@export var plane_target: Vector3 = Vector3(950.0, 300.0, 950.0)

@export_group("Enemy Spawning")
@export var spawn_interval: float = 2.0
@export var fastest_spawn_interval: float = 0.95
@export var max_enemies: int = 8
@export var min_spawn_distance: float = 18.0
@export var max_spawn_distance: float = 52.0

@export_group("Arena")
@export var arena_size: float = 2000.0
@export var ocean_size: float = 4000.0

@export_group("Nature")
@export var nature_seed: int = 20241015
@export var tree_count: int = 1600
@export var rock_count: int = 800
@export var grass_count: int = 48
@export var plant_count: int = 24
@export var max_trees: int = 2000
@export var max_rocks: int = 1000
@export var nature_collision_radius: float = 55.0
@export var nature_view_distance: float = 1000.0
@export var multimesh_threshold: int = 40

@export_group("Vehicles")
@export var vehicle_count: int = 7
@export var vehicle_collision: bool = true

const GREEN_ZONES: Array[String] = ["Haveli", "Haritvan", "Kanak", "Khet"]

const ZONES := {
	"Chowk": {"angle": -45.0, "spread": 44.0, "w_tree": 0.6, "w_rock": 1.1, "w_grass": 0.0, "w_plant": 0.0},
	"Haveli": {"angle": 0.0, "spread": 44.0, "w_tree": 0.8, "w_rock": 0.4, "w_grass": 1.0, "w_plant": 0.6},
	"Himvana": {"angle": 45.0, "spread": 44.0, "w_tree": 1.2, "w_rock": 0.3, "w_grass": 0.0, "w_plant": 0.0},
	"Kanak": {"angle": 90.0, "spread": 44.0, "w_tree": 0.8, "w_rock": 0.3, "w_grass": 1.0, "w_plant": 0.8},
	"Samudra": {"angle": 135.0, "spread": 44.0, "w_tree": 0.5, "w_rock": 0.9, "w_grass": 0.0, "w_plant": 0.0},
	"Marusthal": {"angle": 180.0, "spread": 44.0, "w_tree": 0.4, "w_rock": 1.2, "w_grass": 0.0, "w_plant": 0.0},
	"Khet": {"angle": -135.0, "spread": 44.0, "w_tree": 0.8, "w_rock": 0.3, "w_grass": 1.1, "w_plant": 0.9},
	"Haritvan": {"angle": -90.0, "spread": 44.0, "w_tree": 1.6, "w_rock": 0.4, "w_grass": 1.5, "w_plant": 1.4},
}

const VEHICLE_COLORS := {
	"Cop": Color(0.18, 0.20, 0.30),
	"Taxi": Color(0.88, 0.72, 0.16),
	"SUV": Color(0.42, 0.46, 0.44),
	"NormalCar1": Color(0.60, 0.62, 0.68),
	"NormalCar2": Color(0.52, 0.28, 0.24),
	"SportsCar": Color(0.70, 0.26, 0.16),
	"SportsCar2": Color(0.24, 0.42, 0.66),
	"default": Color(0.55, 0.57, 0.60),
}

const PARKED_VEHICLE_SPOTS := [
	{"model": "SUV", "pos": Vector3(0.0, 0.0, 118.0), "yaw": 0.0},
	{"model": "Cop", "pos": Vector3(310.0, 0.0, -252.0), "yaw": 0.6},
	{"model": "Taxi", "pos": Vector3(-290.0, 0.0, 260.0), "yaw": -0.8},
	{"model": "SportsCar", "pos": Vector3(265.0, 0.0, 265.0), "yaw": 2.2},
	{"model": "NormalCar1", "pos": Vector3(-118.0, 0.0, 14.0), "yaw": 1.57},
	{"model": "NormalCar2", "pos": Vector3(118.0, 0.0, -14.0), "yaw": -1.57},
	{"model": "SportsCar2", "pos": Vector3(-262.0, 0.0, -275.0), "yaw": 0.78},
]

@onready var sun: DirectionalLight3D = $Sun
@onready var player = $Player
@onready var hud = $HUD
@onready var enemy_container: Node3D = $Enemies
@onready var bullet_container: Node3D = $Bullets
@onready var spawn_timer: Timer = $SpawnTimer

var score: int = 0
var kills: int = 0
var game_over: bool = false

var _building_spots: Array = []
var _hill_spots: Array = []
var _world_summary: Dictionary = {}

# Cargo plane runtime state
var _cargo_plane: Node3D = null
var _plane_direction: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
var _plane_velocity: Vector3 = Vector3.ZERO
var _plane_elapsed: float = 0.0
var _player_ejected: bool = false


func _ready() -> void:
	for line in AssetLoader.report_lines():
		print("ASSETS: " + line)
	print("MAP: %s — %.0fx%.0fm arena, %.0fm ocean" % [
		MapData.display_name(MAP_ID), arena_size, arena_size, ocean_size
	])

	_build_arena()
	_spawn_vehicles()

	player.hud = hud
	hud.bind_weapon_manager(player.weapon_manager)

	# Wire HUD -> Player / Main actions
	hud.fire_pressed.connect(player.start_firing)
	hud.fire_released.connect(player.stop_firing)
	hud.jump_pressed.connect(player.request_jump)
	hud.aim_toggled.connect(player.set_aiming)
	hud.crouch_toggled.connect(player.set_crouching)
	hud.sprint_changed.connect(player.set_sprinting)
	hud.heal_pressed.connect(_on_heal_pressed)
	hud.eject_pressed.connect(_on_eject_pressed)
	hud.restart_pressed.connect(_restart)

	# Wire Player -> HUD / Main updates
	player.health_changed.connect(hud.set_health)
	player.ep_changed.connect(hud.set_ep)
	player.medkits_changed.connect(hud.set_medkits)
	player.drop_state_changed.connect(_on_player_drop_state_changed)
	player.aim_changed.connect(hud.set_aim_active)
	player.crouch_changed.connect(hud.set_crouch_active)
	player.died.connect(_on_player_died)

	hud.set_max_health(player.max_health)
	hud.set_health(player.health)
	hud.set_max_ep(player.max_ep)
	hud.set_ep(int(round(player.ep)))
	hud.set_medkits(player.medkits)
	hud.set_score(score)

	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	if plane_drop_enabled:
		_start_plane_drop()
	else:
		player.global_position = Vector3(0.0, 16.2, 26.0)
		_begin_ground_match()

	_push_hud_telemetry()


func _physics_process(delta: float) -> void:
	if _cargo_plane != null and is_instance_valid(_cargo_plane):
		_cargo_plane.global_position += _plane_velocity * delta
		if not _player_ejected:
			player.sync_with_plane(_cargo_plane, PLANE_HOLD_OFFSET, _plane_velocity)
			_plane_elapsed += delta
			var remaining := maxf(0.0, auto_eject_time - _plane_elapsed)
			hud.set_drop_countdown(remaining)
			if player.consume_eject_request():
				_eject_player(false)
			elif _plane_elapsed >= auto_eject_time:
				_eject_player(true)
		else:
			if _cargo_plane.global_position.distance_to(plane_start) > 2200.0:
				_cargo_plane.queue_free()
				_cargo_plane = null

	_push_hud_telemetry()


# ===================================================== PLANE DROP SEQUENCE ====

func _start_plane_drop() -> void:
	if _cargo_plane != null and is_instance_valid(_cargo_plane):
		_cargo_plane.queue_free()
		_cargo_plane = null
	_plane_elapsed = 0.0
	_player_ejected = false
	var start_pos := Vector3(plane_start.x, plane_altitude, plane_start.z)
	var end_pos := Vector3(plane_target.x, plane_altitude, plane_target.z)
	var flat_delta := Vector3(end_pos.x - start_pos.x, 0.0, end_pos.z - start_pos.z)
	if flat_delta.length_squared() < 1.0:
		flat_delta = Vector3(1.0, 0.0, 1.0)
	_plane_direction = flat_delta.normalized()
	_plane_velocity = _plane_direction * plane_speed

	_cargo_plane = RannbhoomiBuilder.load_cargo_plane()
	add_child(_cargo_plane)
	_cargo_plane.global_position = start_pos
	_cargo_plane.look_at(start_pos + _plane_direction * 100.0, Vector3.UP)

	# Disable sun shadow cascades during sky drop for crisp FPS on 4GB mobile GPUs
	if sun != null:
		sun.shadow_enabled = false

	player.enter_plane(_cargo_plane, PLANE_HOLD_OFFSET)
	hud.set_drop_state(player.DropState.IN_PLANE)
	hud.set_drop_countdown(auto_eject_time)
	print("DROP: CargoPlane spawned at %s -> speed %.1f m/s, auto-eject %.1fs" % [
		str(_cargo_plane.global_position), plane_speed, auto_eject_time
	])


func _on_eject_pressed() -> void:
	_eject_player(false)


func _eject_player(forced: bool = false) -> void:
	if _player_ejected or game_over:
		return
	_player_ejected = true
	player.eject_from_plane(_plane_velocity * 0.25)
	hud.set_drop_state(player.DropState.FREEFALL)
	print("DROP: Ejected (%s) at %s" % ["AUTO-15S" if forced else "MANUAL", str(player.global_position)])


func _on_player_drop_state_changed(new_state: int) -> void:
	hud.set_drop_state(new_state)
	if new_state == player.DropState.PARACHUTE:
		print("DROP: Parachute deployed at y=%.2fm (fall speed %.1f m/s)" % [
			player.global_position.y, player.parachute_fall_speed
		])
	elif new_state == player.DropState.LANDED:
		print("DROP: Player landed at %s" % str(player.global_position))
		_begin_ground_match()


func _begin_ground_match() -> void:
	if sun != null:
		sun.shadow_enabled = true
	if not game_over and spawn_timer.is_stopped():
		spawn_timer.start()
		_spawn_enemy()


func get_cargo_plane() -> Node3D:
	return _cargo_plane


func is_player_ejected() -> bool:
	return _player_ejected


# ============================================================ ARENA ASSEMBLY ==

func _build_arena() -> void:
	_world_summary = RannbhoomiBuilder.build_world(self, arena_size)
	_building_spots = _world_summary.get("building_spots", [])
	_hill_spots = _world_summary.get("hill_spots", [])

	_build_ocean()
	_build_boundary_walls()
	_build_mahal_courtyard_cover()
	_scatter_nature()


func _build_ocean() -> void:
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.035, 0.28, 0.46, 0.78)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.20
	water_material.metallic = 0.05
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var plane := PlaneMesh.new()
	plane.size = Vector2(ocean_size, ocean_size)
	plane.material = water_material

	var water := MeshInstance3D.new()
	water.name = "Ocean_4000m"
	water.mesh = plane
	water.position.y = -0.5
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _build_boundary_walls() -> void:
	var half_arena: float = arena_size * 0.5
	var wall_color := Color(0.30, 0.34, 0.32)
	var wall_len: float = arena_size + 0.8
	_add_box(Vector3(0.0, 1.625, -half_arena), Vector3(wall_len, 3.25, 0.8), wall_color)
	_add_box(Vector3(0.0, 1.625, half_arena), Vector3(wall_len, 3.25, 0.8), wall_color)
	_add_box(Vector3(-half_arena, 1.625, 0.0), Vector3(0.8, 3.25, wall_len), wall_color)
	_add_box(Vector3(half_arena, 1.625, 0.0), Vector3(0.8, 3.25, wall_len), wall_color)


func _build_mahal_courtyard_cover() -> void:
	# Tactical royal sandstone/wood cover crates around the Shahi Mahal forecourt (Y = 15m)
	var forecourt_crates := [
		[Vector3(-18.0, 16.0, 32.0), Vector3(2.4, 2.0, 2.4), Color(0.66, 0.46, 0.25)],
		[Vector3(18.0, 16.0, 32.0), Vector3(2.4, 2.0, 2.4), Color(0.66, 0.46, 0.25)],
		[Vector3(-34.0, 16.0, 0.0), Vector3(2.4, 2.0, 3.0), Color(0.62, 0.43, 0.23)],
		[Vector3(34.0, 16.0, 0.0), Vector3(2.4, 2.0, 3.0), Color(0.62, 0.43, 0.23)],
	]
	for item in forecourt_crates:
		_add_box(item[0], item[1], item[2])


# ============================================================ NATURE SCATTER ==

func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed

	var inner_limit: float = arena_size * 0.5 - 8.0
	var container := Node3D.new()
	container.name = "Nature"
	add_child(container)

	var types := [
		["tree", tree_count, 1.1, 1.8, "w_tree", false],
		["rock", rock_count, 0.9, 1.7, "w_rock", false],
		["grass", grass_count, 1.0, 1.7, "w_grass", true],
		["plant", plant_count, 1.0, 1.5, "w_plant", true],
	]

	var placed := {}
	var total_placed := 0
	var mm_used: Array[String] = []

	for entry in types:
		var kind: String = str(entry[0])
		var wanted: int = int(entry[1])
		var min_scale: float = float(entry[2])
		var max_scale: float = float(entry[3])
		var weight_key: String = str(entry[4])
		var green_only: bool = bool(entry[5])

		var cap := max_trees if kind == "tree" else (max_rocks if kind == "rock" else 0)
		if cap > 0 and wanted > cap:
			wanted = cap

		var assignments := _distribute(wanted, weight_key, green_only)
		var placements: Array = []
		var counter := 0

		for zone_name in assignments:
			var zone_count: int = int(assignments[zone_name])
			var zone: Dictionary = ZONES[zone_name]
			for i in zone_count:
				var pos := Vector3.ZERO
				var found := false
				for attempt in 20:
					pos = _pick_prop_position(zone, inner_limit, rng)
					if _prop_spot_free(pos):
						pos.y = RannbhoomiBuilder.sample_ground_height(pos.x, pos.z)
						found = true
						break
				if not found:
					continue
				placements.append({
					"pos": pos,
					"scale": rng.randf_range(min_scale, max_scale),
					"variant": counter % 5,
					"yaw": rng.randf() * TAU,
					"zone": zone_name,
				})
				counter += 1

		var collidable: bool = kind == "tree" or kind == "rock"
		var node_items: Array = []
		var mm_items: Array = []
		for item in placements:
			var p: Vector3 = item["pos"]
			if collidable and Vector2(p.x, p.z).length() <= nature_collision_radius:
				node_items.append(item)
			else:
				mm_items.append(item)

		var spawned := 0
		if not mm_items.is_empty():
			if collidable or placements.size() > multimesh_threshold:
				if _spawn_multimesh(container, kind, mm_items):
					mm_used.append("%s x%d" % [kind, mm_items.size()])
					spawned += mm_items.size()
					mm_items = []
			node_items.append_array(mm_items)

		for item in node_items:
			var prop: Node3D = _make_prop(kind, int(item["variant"]), float(item["scale"]))
			if prop == null:
				continue
			prop.position = item["pos"]
			prop.rotation.y = float(item["yaw"])
			container.add_child(prop)
			spawned += 1

		total_placed += spawned
		placed[kind] = spawned

	print("Nature: %d props placed %s%s" % [
		total_placed,
		placed,
		("  MultiMesh: " + ", ".join(mm_used)) if not mm_used.is_empty() else "",
	])


func _pick_prop_position(zone: Dictionary, inner_limit: float, rng: RandomNumberGenerator) -> Vector3:
	var center_angle: float = deg_to_rad(float(zone.get("angle", 0.0)))
	var spread_rad: float = deg_to_rad(float(zone.get("spread", 44.0)))
	for attempt in 16:
		var pos := Vector3(
			rng.randf_range(-inner_limit, inner_limit),
			0.0,
			rng.randf_range(-inner_limit, inner_limit)
		)
		var flat := Vector2(pos.x, pos.z)
		if flat.length() < 42.0:
			continue
		var diff: float = absf(wrapf(flat.angle() - center_angle, -PI, PI))
		if diff <= spread_rad:
			return pos
	var angle: float = center_angle + rng.randf_range(-spread_rad, spread_rad)
	var radius: float = rng.randf_range(115.0, inner_limit)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _prop_spot_free(pos: Vector3) -> bool:
	# Keep central plateau ramps & Mahal courtyard unobstructed
	if absf(pos.x) < 106.0 and absf(pos.z) < 106.0:
		return false
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		if Vector2(pos.x - center.x, pos.z - center.z).length() < float(spot["radius"]) + 4.0:
			return false
	for hs in _hill_spots:
		var hcenter: Vector3 = hs["pos"]
		if Vector2(pos.x - hcenter.x, pos.z - hcenter.z).length() < float(hs["radius"]):
			return false
	return true


func _spawn_multimesh(container: Node3D, kind: String, placements: Array) -> bool:
	var variants := {}
	for item in placements:
		variants[int(item["variant"])] = true

	var meshes := {}
	var ground_offsets := {}
	for variant in variants:
		var mesh := Assets.nature_mesh(kind, int(variant))
		if mesh == null and (kind == "tree" or kind == "rock"):
			mesh = _fallback_nature_mesh(kind)
		if mesh == null:
			return false
		meshes[variant] = mesh
		ground_offsets[variant] = _mesh_ground_offset(mesh)

	var groups := {}
	for item in placements:
		var p: Vector3 = item["pos"]
		var key := "%d:%d:%d" % [
			int(item["variant"]),
			int(floor(p.x / NATURE_CELL_SIZE)),
			int(floor(p.z / NATURE_CELL_SIZE)),
		]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(item)

	for key in groups:
		var items: Array = groups[key]
		var first: Dictionary = items[0]
		var variant := int(first["variant"])
		var p0: Vector3 = first["pos"]
		var cell_x := int(floor(p0.x / NATURE_CELL_SIZE))
		var cell_z := int(floor(p0.z / NATURE_CELL_SIZE))
		var cell_center := Vector3(
			(float(cell_x) + 0.5) * NATURE_CELL_SIZE,
			0.0,
			(float(cell_z) + 0.5) * NATURE_CELL_SIZE
		)
		var offset: Vector3 = ground_offsets[variant]

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[variant]
		multimesh.instance_count = items.size()
		for i in items.size():
			var item: Dictionary = items[i]
			var s: float = float(item["scale"])
			var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * s)
			var ipos: Vector3 = item["pos"]
			var origin: Vector3 = ipos - cell_center + basis * offset
			multimesh.set_instance_transform(i, Transform3D(basis, origin))

		var node := MultiMeshInstance3D.new()
		node.name = "%sMM%d_%d_%d" % [kind.capitalize(), variant, cell_x, cell_z]
		node.multimesh = multimesh
		node.position = cell_center
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var half_cell: float = NATURE_CELL_SIZE * 0.5 + 8.0
		node.custom_aabb = AABB(
			Vector3(-half_cell, -2.0, -half_cell),
			Vector3(half_cell * 2.0, 32.0, half_cell * 2.0)
		)
		if nature_view_distance > 0.0:
			node.visibility_range_end = nature_view_distance
		container.add_child(node)
	return true


func _mesh_ground_offset(mesh: Mesh) -> Vector3:
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	return Vector3(-center.x, -aabb.position.y, -center.z)


func _fallback_nature_mesh(kind: String) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	if kind == "tree":
		mat.albedo_color = Color(0.20, 0.42, 0.19)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.05
		cone.height = 3.6
		cone.radial_segments = 8
		cone.material = mat
		return cone
	mat.albedo_color = Color(0.46, 0.47, 0.49)
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 0.66
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = mat
	return sphere


func _distribute(total: int, weight_key: String, green_only: bool = false) -> Dictionary:
	var weights := {}
	var sum := 0.0
	for zone_name in ZONES:
		if green_only and not GREEN_ZONES.has(zone_name):
			continue
		var w: float = float(ZONES[zone_name].get(weight_key, 0.0))
		if w <= 0.0:
			continue
		weights[zone_name] = w
		sum += w

	var out := {}
	if weights.is_empty() or total <= 0:
		return out

	var names := weights.keys()
	names.sort()
	var left := total
	for i in names.size():
		var zone_name: String = str(names[i])
		if i == names.size() - 1:
			out[zone_name] = left
			break
		var count := int(round(float(total) * float(weights[zone_name]) / sum))
		count = mini(count, left)
		out[zone_name] = count
		left -= count
	return out


func _make_prop(kind: String, variant: int, scale_f: float) -> Node3D:
	match kind:
		"tree":
			return Assets.tree(scale_f, variant)
		"rock":
			return Assets.rock(scale_f, variant)
		"plant":
			return Assets.plant(scale_f, variant)
		"grass":
			return Assets.grass_tuft(scale_f, variant)
		_:
			return null


# ================================================================ VEHICLES ====

func _spawn_vehicles() -> void:
	var container := Node3D.new()
	container.name = "Vehicles"
	add_child(container)

	var count := 0
	for spot in PARKED_VEHICLE_SPOTS:
		if count >= vehicle_count:
			break
		var model_name := String(spot["model"])
		var body := _make_vehicle(model_name)
		if body == null:
			continue
		var p: Vector3 = spot["pos"]
		p.y = RannbhoomiBuilder.sample_ground_height(p.x, p.z)
		body.position = p
		body.rotation.y = float(spot["yaw"])
		if not vehicle_collision:
			Assets.disable_collision(body)
		container.add_child(body)
		count += 1

	print("Vehicles: %d placed" % count)


func _make_vehicle(model_name: String) -> StaticBody3D:
	var body := Assets.build_vehicle_model(model_name)
	if body == null:
		var color: Color = VEHICLE_COLORS.get(model_name, VEHICLE_COLORS["default"])
		body = Assets.fallback_vehicle(model_name, color)
	return body


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


# ============================================================ ENEMY SPAWNING ==

func _on_spawn_timer_timeout() -> void:
	if game_over or not player.is_landed():
		return
	if enemy_container.get_child_count() >= max_enemies:
		return

	_spawn_enemy()
	spawn_timer.wait_time = maxf(fastest_spawn_interval, spawn_interval - float(score) * 0.0015)


func _spawn_enemy() -> void:
	var enemy = ENEMY_SCENE.instantiate()
	enemy.died.connect(_on_enemy_died)
	enemy_container.add_child(enemy)
	enemy.global_position = _pick_spawn_position()


func _pick_spawn_position() -> Vector3:
	var center: Vector3 = player.global_position
	var space := get_world_3d().direct_space_state
	var half_limit := arena_size * 0.5 - 20.0
	for attempt in 18:
		var angle := randf() * TAU
		var dist := randf_range(min_spawn_distance, max_spawn_distance)
		var x := clampf(center.x + cos(angle) * dist, -half_limit, half_limit)
		var z := clampf(center.z + sin(angle) * dist, -half_limit, half_limit)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, 80.0, z),
			Vector3(x, -5.0, z)
		)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			var nrm: Vector3 = hit["normal"]
			if nrm.y >= 0.72:
				return Vector3(hp.x, hp.y + 0.35, hp.z)
	var fallback_y := RannbhoomiBuilder.sample_ground_height(center.x + 22.0, center.z)
	return Vector3(center.x + 22.0, fallback_y + 0.4, center.z)


# ===================================================== HUD TELEMETRY & SCORE ==

func _push_hud_telemetry() -> void:
	if hud == null or not hud.has_method("update_tactical_hud"):
		return
	var enemy_positions: Array[Vector2] = []
	for e in enemy_container.get_children():
		if e is Node3D:
			var ep_node := e as Node3D
			enemy_positions.append(Vector2(ep_node.global_position.x, ep_node.global_position.z))

	var plane_xz := Vector2.ZERO
	var has_plane := _cargo_plane != null and is_instance_valid(_cargo_plane)
	if has_plane:
		plane_xz = Vector2(_cargo_plane.global_position.x, _cargo_plane.global_position.z)

	var ppos: Vector3 = player.global_position
	var poi := RannbhoomiBuilder.poi_name_at(ppos.x, ppos.z)
	hud.update_tactical_hud(
		Vector2(ppos.x, ppos.z),
		player.global_rotation.y,
		ppos.y,
		poi,
		enemy_positions,
		has_plane,
		plane_xz,
		Vector2(plane_start.x, plane_start.z),
		Vector2(plane_target.x, plane_target.z)
	)


func _on_heal_pressed() -> void:
	player.use_medkit()


func _on_enemy_died(_enemy) -> void:
	if game_over:
		return
	kills += 1
	score += 10
	player.add_ep(25)
	if kills % 2 == 0:
		player.grant_medkit(1)
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
