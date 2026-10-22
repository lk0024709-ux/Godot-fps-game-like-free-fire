extends Node3D
##
## Main (game manager) — map: "Veergarh" (naam scripts/map_data.gd me hai)
## - BATTLE ROYALE DROP: match 300m upar plane me shuru — JUMP OUT (ya 10s
##   auto-eject) -> free-fall (steering) -> 50m pe parachute (5 m/s) -> land.
##   Land karne ke baad hi dushman spawn hona shuru hote hain
## - Arena banata hai: 2000x2000m zameen + 4000x4000m samundar (Ocean) +
##   kinaron par deewar + center me purane cover boxes (sab code se)
## - ENTERABLE BUILDINGS banata hai (scripts/building_builder.gd): kuchh ghar, dukaan,
##   barn — darwaze se andar ja sakte ho, andar light + furniture (cover) bhi hai
## - Nature scatter karta hai: ZONES ke hisaab se ped/patthar/ghaas/plant
##   (downloaded OBJ models, aur na mile to procedural — dekho scripts/assets.gd).
##   40 se zyada ghaas/plant ho to MultiMeshInstance3D (ek draw call)
## - ZONES ke fixed spots pe gaadiyaan (vehicles) rakhta hai (abhi static decoration)
## - Enemies spawn karta hai
## - Score (+10 per kill) aur Game Over handle karta hai
##
## ZONES (Phase 3): gameplay ke saare zones ki jagah is ek table me hai — angle (compass
## direction), kaunsa prop kitna, aur gaadi kahan. Tum bina code padhe numbers badal
## sakte ho: angle/weights/vehicles. angle 0 = -Z (uttar), 90 = +X (purab), etc.
##

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const Assets := preload("res://scripts/assets.gd")
const AssetLoader := preload("res://scripts/asset_loader.gd")
const BUILDING := preload("res://scripts/building_builder.gd")
const MapData := preload("res://scripts/map_data.gd")

## Ye scene kaunsa map hai (naam map_data.gd se aata hai — wahan badlo)
const MAP_ID := "Veergarh"

@export_group("Enemy Spawning")
@export var spawn_interval: float = 1.8          ## kitne second me naya enemy
@export var fastest_spawn_interval: float = 0.9  ## max difficulty pe itna fast
@export var max_enemies: int = 8                 ## ek waqt me itne enemies
@export var min_spawn_distance: float = 9.0      ## player se itni door spawn

@export_group("Arena")
## BATTLE ROYALE SCALE: 2000x2000m (2km x 2km) zameen + 4000x4000m samundar.
## DHYAAN: sirf zameen, boundary deewar aur nature (ped/patthar) poore 2000m me
## phailte hain. Gameplay wala purana layout — buildings, gaadiyaan, cover boxes,
## enemy spawn — center ke LAYOUT_SIZE (52m) hisse me apni PURANI jagah par hi
## rehta hai (neeche LAYOUT_SIZE dekho). Naye POI baad me aayenge.
@export var arena_size: float = 2000.0           ## maidan kitna bada (2000 = 2000x2000m)
@export var ocean_size: float = 4000.0           ## samundar ka size (zameen se bada -> horizon tak paani)

@export_group("Nature")
## Ye seed fix hai — isliye har baar wahi ped/patthar/ghaas wahi jagah pe ugte hain.
## Badal ke dekho: pura layout badal jayega (par phir bhi deterministic rahega).
@export var nature_seed: int = 20241015
@export var tree_count: int = 2000               ## ped (poore 2000x2000 map me uniformly bikhre hue)
@export var rock_count: int = 1000               ## patthar (wese hi uniformly bikhre hue)
@export var bush_count: int = 14                 ## jhaadiyaan
@export var grass_count: int = 40                ## ghaas ke guchhe (inme collision nahi hota)
@export var plant_count: int = 20                ## plant / phool (inme bhi collision nahi)
## Performance cap: isse zyada ped/patthar kabhi nahi lagenge. Cap lagna to
## console me warning aati hai — TUNING ke liye numbers yahin badlo.
## (Counts ab ABSOLUTE hain — purana area-scale wala hisaab hata diya gaya hai,
## warna 2000m pe ped laakhon me chale jaate.)
@export var max_trees: int = 2000
@export var max_rocks: int = 1000
## Ped/patthar CENTER ke is radius ke andar alag nodes + collision ke saath
## lagte hain (jaise pehle); iske bahar hazaaron props sirf MultiMesh (bina
## collision) — 3000 physics bodies 4GB phone pe bahut mehnge padte.
@export var nature_collision_radius: float = 40.0
## MultiMesh nature itni door (m) tak dikhega — 250m cells me culling hoti hai
## (peeche/door ke cells draw nahi hote), 4GB perf ke liye. 0 = koi limit nahi (PC).
@export var nature_view_distance: float = 1000.0
## Ghaas/plant sirf in "hare-bhare" zones me lagte hain (spec). Baaki zones me
## patthar/registan hai -> wahan ghaas nahi ugeti.
const GREEN_ZONES: Array[String] = ["Haveli", "Haritvan", "Khet", "Kanak"]
## 40 se zyada grass/plant ho to MultiMeshInstance3D use hota hai (ek draw call).
## Ped/patthar hamesha MultiMesh me jaate hain (center-collision wale chhod kar).
@export var multimesh_threshold: int = 40

@export_group("Buildings")
@export var buildings_enabled: bool = true       ## enterable buildings banao?
@export var max_buildings: int = 18              ## spec: map pe max 18 buildings

@export_group("Vehicles")
@export var vehicle_count: int = 7               ## spec: 7 gaadiyaan (zones ke fixed spots pe)
@export var vehicle_collision: bool = true       ## aar-paar jaane wale gaadi pe box collision
## NOTE: gaadi me baithna/chadhna (enter-exit physics) Phase F ka kaam hai —
## abhi ye sirf static decoration hai (takkar hoti hai, par chal nahi sakte).

@export_group("Plane Drop")
## BATTLE ROYALE START: player zameen pe spawn NAHI hota — 300m upar plane me
## hota hai. Plane map ke paar udta hai; player JUMP OUT (ya 10s me auto-eject)
## karta hai, free-fall me steering karta hai, 50m pe parachute khulta hai aur
## land karke normal FPS gameplay shuru hota hai.
@export var plane_drop_enabled: bool = true
@export var plane_start: Vector3 = Vector3(-900.0, 300.0, 0.0)    ## plane kahan se udta hai (map ke andar — turant kudo to bhi zameen mile)
@export var plane_direction: Vector3 = Vector3(1.0, 0.0, 0.0)     ## kis dish me (normal ize hota hai)
@export var plane_speed: float = 70.0            ## plane ki raftaar (m/s)
@export var auto_eject_time: float = 10.0        ## itne second me player khud bahar

## Neeche wala layout 40x40 ke hisaab se likha hai (positions/sizes) aur
## LAYOUT_SCALE se 52m ke center-layout me fit hota hai.
const ARENA_REFERENCE: float = 40.0

## PURANA gameplay layout (52x52m) — buildings, gaadiyaan, cover boxes aur
## enemy-spawn ring center ke is hisse me EXACT apni purani jagah pe rehte hain,
## chahe arena_size 2000 ho. Isi liye building-candidate grid bhi chhota rehta
## hai (2000m pe 0.5m grid = crore points, game start hi nahi hota).
const LAYOUT_SIZE: float = 52.0
const LAYOUT_SCALE: float = LAYOUT_SIZE / ARENA_REFERENCE   # 1.3

## Nature MultiMesh ko itne bade (m) cells me baanta jata hai — camera ke
## peeche ya view-distance se bahar wale cells draw nahi hote (perf).
const NATURE_CELL_SIZE: float = 250.0

@onready var player = $Player
@onready var hud = $HUD
@onready var enemy_container: Node3D = $Enemies
@onready var bullet_container: Node3D = $Bullets
@onready var spawn_timer: Timer = $SpawnTimer
@onready var sun: DirectionalLight3D = $Sun

var score: int = 0
var game_over: bool = false

# ---- plane drop (BR start) ka state ----
## Player plane ke andar seat pe is offset pe baithta hai (plane origin se upar).
## Plane origin fuselage ke center pe hai; floor ka top -1.4m pe hai — wahi seat.
const PLANE_SEAT_OFFSET := Vector3(0.0, -1.4, 0.0)
var _plane: Node3D = null               ## procedural drop plane (boxes wala)
var _plane_time: float = 0.0            ## plane udna shuru hue kitna time
var _plane_active: bool = false
var _ejected: bool = false

# ---- map ke "book-keeping" (building/vehicle overlap na ho) ----
## Har building ka spot: {pos: Vector3, half: Vector2 (x/z half-size), radius: float}
var _building_spots: Array = []
## Har gaadi ki jagah: {pos: Vector3, radius: float}
var _vehicle_spots: Array = []

# ------------------------------------------------------------------ ZONES ----
# Game ke 8 zones. `angle` = arena ke center se compass direction (0 = -Z, 90 = +X).
# `w_*` = us zone me prop kitna lagega (0 = bilkul nahi). Ye weight global count ko
# baant dete hain, isliye tree_count/rock_count badalne se sirf kul ginti badalti hai.
#
#   Himvana  (barf)      : sirf pine
#   Marusthal(registan)   : sirf patthar
#   Kanak, Khet (khet)    : halke pine + ghaas
#   Haritvan (jungle)     : ghane pine + ghaas + plant
#   Haveli                : 2-3 pine + ghaas
#   Chowk, Samudra        : default mix (patthar zyada, ped kam)
const ZONES := {
	"Chowk": {
		"angle": -45.0, "spread": 44.0,
		"w_tree": 0.5, "w_rock": 1.2, "w_grass": 0.0, "w_plant": 0.0,
		"vehicles": ["Taxi", "NormalCar1"],
	},
	"Haveli": {
		"angle": 0.0, "spread": 44.0,
		"w_tree": 0.6, "w_rock": 0.3, "w_grass": 0.9, "w_plant": 0.4,
		"vehicles": ["Cop"],
	},
	"Himvana": {
		"angle": 45.0, "spread": 44.0,
		"w_tree": 1.4, "w_rock": 0.0, "w_grass": 0.0, "w_plant": 0.0,
		"vehicles": [],
	},
	"Kanak": {
		"angle": 90.0, "spread": 44.0,
		"w_tree": 0.6, "w_rock": 0.3, "w_grass": 1.0, "w_plant": 0.7,
		"vehicles": ["SUV"],
	},
	"Samudra": {
		"angle": 135.0, "spread": 44.0,
		"w_tree": 0.3, "w_rock": 1.0, "w_grass": 0.0, "w_plant": 0.0,
		"vehicles": ["SportsCar"],
	},
	"Marusthal": {
		"angle": 180.0, "spread": 44.0,
		"w_tree": 0.0, "w_rock": 1.6, "w_grass": 0.0, "w_plant": 0.0,
		"vehicles": ["NormalCar2"],
	},
	"Khet": {
		"angle": -135.0, "spread": 44.0,
		"w_tree": 0.5, "w_rock": 0.2, "w_grass": 1.0, "w_plant": 0.8,
		"vehicles": [],
	},
	"Haritvan": {
		"angle": -90.0, "spread": 44.0,
		"w_tree": 1.8, "w_rock": 0.4, "w_grass": 1.6, "w_plant": 1.6,
		"vehicles": [],
	},
}

## Spec ke hisaab se buildings ka plan (kul 14 — max 18 ke andar).
const BUILDING_PLAN := {
	"Haveli": ["small_house", "small_house", "small_house", "big_house"],
	"Chowk": ["shop", "shop", "big_house"],
	"Kanak": ["barn", "barn"],
	"Khet": ["barn"],
	"Haritvan": ["small_house"],
	"Himvana": ["small_house"],
	"Marusthal": ["shop"],
	"Samudra": ["small_house"],
}

## Har zone ke prop ka rang (procedural fallback pe lagta hai; downloaded models
## apne asli rang rakhte hain). Desert = bhura, barf = dhulmil safed.
const ZONE_TINT := {
	"Himvana": Color(0.78, 0.84, 0.88),
	"Marusthal": Color(0.72, 0.62, 0.42),
	"Chowk": Color(0.72, 0.66, 0.52),
	"Samudra": Color(0.60, 0.72, 0.78),
}

## Vehicle ke rang (procedural fallback ke liye) — downloaded model apna rang rakhta hai
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

## Cover ka layout: [position, size, colour] — 40m-reference me likha hai,
## LAYOUT_SCALE se center ke 52m layout me lagta hai (purani jagah, purana size).
## Boundary deewarein is list me NAHI hain — wo arena_size ke kinare pe alag se
## banti hain (_build_arena dekho), warna 2000m pe crate bhi 100m ke ho jaate.
var _obstacles := [
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
	# Android/PCK asset diagnostics go to the engine log, never to the gameplay HUD.
	for line in AssetLoader.report_lines():
		print("ASSETS: " + line)
	print("MAP: %s — %.0fx%.0fm arena, %.0fm ocean" % [MapData.display_name(MAP_ID), arena_size, arena_size, ocean_size])
	_build_arena()
	_spawn_vehicles()

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

	# plane drop -> HUD / player
	player.parachute_opened.connect(_on_player_parachute_opened)
	player.landed.connect(_on_player_landed)
	hud.jump_out_pressed.connect(_eject_player)
	hud.sprint_pressed.connect(_on_hud_sprint_pressed)
	hud.sprint_released.connect(_on_hud_sprint_released)

	# HP bar player ke max_health ke hisaab se (player.gd me max_health badlo to bar bhi sahi)
	hud.set_max_health(player.max_health)
	hud.set_health(player.health)
	hud.set_score(score)

	# Dushman spawn plane-drop ke BAAD shuru hote hain (land karne pe).
	# Plane drop off ho to pehle jaisa seedha ground match.
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	if plane_drop_enabled:
		_start_plane_drop()
	else:
		_start_ground_match()


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

	# ---- samundar (zameen ke chaaron taraf, horizon tak) ----
	_build_ocean()

	# ---- boundary deewarein: arena ke KINARE pe (±arena_size/2) ----
	# lambaai = poora arena, par unchai/motai purani wali hi (52m layout me
	# deewar 3.25m unchi, 0.78m moti thi) — arena_size se scale karte to
	# 125m unchi deewar ban jaati.
	var half_arena: float = arena_size * 0.5
	var wall_color := Color(0.30, 0.32, 0.36)
	var wall_len: float = arena_size + 0.8
	_add_box(Vector3(0, 1.625, -half_arena), Vector3(wall_len, 3.25, 0.8), wall_color)
	_add_box(Vector3(0, 1.625, half_arena), Vector3(wall_len, 3.25, 0.8), wall_color)
	_add_box(Vector3(-half_arena, 1.625, 0), Vector3(0.8, 3.25, wall_len), wall_color)
	_add_box(Vector3(half_arena, 1.625, 0), Vector3(0.8, 3.25, wall_len), wall_color)

	# ---- cover boxes: purana center layout, jyon ka tyon (LAYOUT_SCALE) ----
	for item in _obstacles:
		_add_box((item[0] as Vector3) * LAYOUT_SCALE, (item[1] as Vector3) * LAYOUT_SCALE, item[2])

	# ---- buildings PEHLE (unki jagah reserve ho jaye), phir nature ----
	_build_buildings()

	# ---- nature: ped / patthar / ghaas (hybrid: OBJ model ya procedural) ----
	_scatter_nature()


## Samundar: zameen ke neeche ek bada flat plane (4000x4000m) — kinare se
## horizon tak paani. Koi texture nahi (perf), wahi material jo Neel Dweep
## (map.gd) ki ocean use karti hai. Saath me ek invisible catch-floor bhi —
## agar koi plane se jaldi kud ke ya steering karte hue map ke bahar gire to
## hamesha zameen mile (infinite fall nahi).
func _build_ocean() -> void:
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.035, 0.25, 0.43, 0.70)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.22
	water_material.metallic = 0.04
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

	# ---- invisible catch-floor (paani ke thoda niche) ----
	var catch_body := StaticBody3D.new()
	catch_body.name = "OceanCatchFloor"
	catch_body.collision_layer = 1
	var catch_shape := CollisionShape3D.new()
	var catch_box := BoxShape3D.new()
	catch_box.size = Vector3(ocean_size, 1.0, ocean_size)
	catch_shape.shape = catch_box
	catch_shape.position = Vector3(0.0, -3.0, 0.0)
	catch_body.add_child(catch_shape)
	add_child(catch_body)


# ------------------------------------------------------------- buildings ----


## Spec ka BUILDING_PLAN -> arena ke ring pe enterable buildings.
## Darwaza arena ke beech ki taraf hota hai (yaw 90 deg ke multiple pe snap, isliye
## deewarein axis-aligned rehti hain aur collision check simple AABB hai).
func _build_buildings() -> void:
	if not buildings_enabled:
		print("Buildings: off (buildings_enabled = false)")
		return

	var container := Node3D.new()
	container.name = "Buildings"
	add_child(container)

	# saare candidate spots ek hi baar nikaal lo (per-building 10k grid scan mehnga hai)
	var candidates := _building_candidates()

	var count := 0
	var kinds := {}
	for zone_name in BUILDING_PLAN:
		var kinds_in_zone: Array = BUILDING_PLAN[zone_name]
		for kind_value in kinds_in_zone:
			if count >= max_buildings:
				break
			var kind: String = str(kind_value)
			var spot := _find_building_spot(str(zone_name), kind, candidates)
			if spot.is_empty():
				push_warning("Buildings: %s (%s) ke liye jagah nahi mili -> skip"
						% [kind, zone_name])
				continue
			var model_variant := int(kinds.get(kind, 0))
			var building: Node3D = BUILDING.build(kind, model_variant)
			if building == null:
				continue
			building.position = spot["pos"]
			building.rotation.y = float(spot["yaw"])
			container.add_child(building)

			var half: Vector2 = spot["half"]
			_building_spots.append({
				"pos": spot["pos"],
				"half": half,
				"radius": Vector2(half.x, half.y).length(),
				"max_half": maxf(half.x, half.y),
			})
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			count += 1

	print("Buildings: %d placed %s" % [count, kinds])


## Ring ke saare candidate spots (0.5 m grid) — ek hi baar banta hai, phir har
## building ke liye reuse hota hai. Har entry: {pos, dist, angle}
## Grid LAYOUT_SIZE (52m) par banta hai, arena_size (2000m) par NAHI — warna
## 0.5m grid ke ~1.6 crore points bante aur game start hone me hi atak jaata.
func _building_candidates() -> Array:
	var out: Array = []
	var half_layout: float = LAYOUT_SIZE * 0.5
	var step := 0.5
	var n := int(half_layout / step)
	var min_dist: float = LAYOUT_SIZE * 0.17
	var max_dist: float = half_layout - 1.5
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var x := float(ix) * step
			var z := float(iz) * step
			var dist := sqrt(x * x + z * z)
			if dist < min_dist or dist > max_dist:
				continue                          # beech ka maidan khula / deewar se door
			out.append({"pos": Vector3(x, 0.0, z), "dist": dist, "angle": atan2(z, x)})
	return out


## Zone ke aas-paas ek jagah dhundo jahan building fit ho jaye.
## Best = zone ki dish ke sabse paas + preferred ring radius ke sabse paas.
## Kuch na mile to {} -> building skip (game phir bhi chalta hai).
func _find_building_spot(zone_name: String, kind: String, candidates: Array) -> Dictionary:
	var zone: Dictionary = ZONES.get(zone_name, {})
	if zone.is_empty():
		return {}
	var zone_angle: float = deg_to_rad(float(zone.get("angle", 0.0)))
	var fp: Vector2 = BUILDING.footprint(kind)
	var half_layout: float = LAYOUT_SIZE * 0.5
	var best := {}
	var best_score := 1e20

	for cand in candidates:
		var pos: Vector3 = cand["pos"]
		var diff: float = absf(wrapf(float(cand["angle"]) - zone_angle, -PI, PI))
		if diff > deg_to_rad(90.0):
			continue                              # apni zone ke aas-paas hi

		# darwaza arena ke beech ki taraf -> yaw 90 deg ke multiple me snap
		var yaw_steps := roundf(atan2(-pos.x, -pos.z) / (PI * 0.5))
		var yaw := yaw_steps * (PI * 0.5)
		var fw: float = fp.x
		var fd: float = fp.y
		if int(yaw_steps) % 2 != 0:               # 90/270 -> footprint swap
			fw = fp.y
			fd = fp.x
		if absf(pos.x) + fw * 0.5 > half_layout - 1.2 or absf(pos.z) + fd * 0.5 > half_layout - 1.2:
			continue
		if _footprint_hits_obstacle(pos.x, pos.z, fw, fd):
			continue
		if _footprint_hits_building(pos.x, pos.z, fw, fd):
			continue

		var score := diff * 10.0 + absf(float(cand["dist"]) - LAYOUT_SIZE * 0.34)
		if score < best_score:
			best_score = score
			best = {"pos": pos, "yaw": yaw, "half": Vector2(fw * 0.5, fd * 0.5)}
	return best


## Building ka footprint (fw x fd, AABB) kisi cover box / low wall se takrata hai?
## (_obstacles me ab sirf cover boxes hain; boundary deewarein 1000m door hain.)
func _footprint_hits_obstacle(x: float, z: float, fw: float, fd: float) -> bool:
	for i in _obstacles.size():
		var item: Array = _obstacles[i]
		var opos: Vector3 = (item[0] as Vector3) * LAYOUT_SCALE
		var osize: Vector3 = (item[1] as Vector3) * LAYOUT_SCALE
		if absf(x - opos.x) < (fw + osize.x) * 0.5 + 0.4 \
				and absf(z - opos.z) < (fd + osize.z) * 0.5 + 0.4:
			return true
	return false


## Do buildings ek doosre me na ghusein (0.8 m ka gap)
func _footprint_hits_building(x: float, z: float, fw: float, fd: float) -> bool:
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		var half: Vector2 = spot["half"]
		if absf(x - center.x) < fw * 0.5 + half.x + 0.8 \
				and absf(z - center.z) < fd * 0.5 + half.y + 0.8:
			return true
	return false


# ------------------------------------------------------------- nature props --

## Ped / patthar / ghaas / plant ko ZONES ke hisaab se bikher deta hai.
##
## Deterministic: `nature_seed` fix hai, isliye har run me SAME layout banta hai.
## Props poore arena me UNIFORMLY bikhre hote hain (zone ke sector ke andar
## har jagah ek-si density) — purani "deewar ke paas patti" wala tareeka 2000m
## pe beech ka 1900m khali chhod deta. Buildings/cover ki jagah phir bhi
## chhod dete hain (_prop_spot_free).
##
## Har prop pehle downloaded OBJ model try karta hai, warna procedural shape
## (dekho scripts/assets.gd + scripts/asset_loader.gd). Download fail ho to ye
## function wahi kaam procedural se kar deta hai — koi error nahi.
##
## Numbers (Battle Royale scale):
##   tree x2000 / rock x1000 (tree_count/rock_count, absolute counts)
##   pine  scale 0.9-1.4 x LAYOUT_SCALE (ped ka size purana hi — arena ke
##         saath scale karte to 200m lambe ped ban jaate)
##   rock  scale 0.7-1.4 x LAYOUT_SCALE
##   grass/plant — sirf GREEN_ZONES me, collision nahi
## Rendering/physics vibhajan:
##   - center ke nature_collision_radius (40m) ke andar ke ped/patthar:
##     alag nodes + collision (Capsule/Box, jaise pehle) — gameplay wahi.
##   - uske bahar ke HAZAARON ped/patthar: MultiMeshInstance3D (250m cells,
##     bina collision) — ek variant+cell = ek draw call, 4GB ke liye zaroori.
func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed

	var inner_limit: float = arena_size * 0.5 - 1.3        # boundary deewar se thoda andar

	var container := Node3D.new()
	container.name = "Nature"
	add_child(container)

	# ---- prop types: kind, count, min scale, max scale, zone-weight, green-only ----
	var types := [
		["tree", tree_count, 0.9, 1.4, "w_tree", false],
		["rock", rock_count, 0.7, 1.4, "w_rock", false],
		["grass", grass_count, 0.85, 1.55, "w_grass", true],
		["plant", plant_count, 0.85, 1.35, "w_plant", true],
	]

	var placed := {}
	var total_placed := 0
	var mm_used: Array[String] = []

	for entry in types:
		var kind: String = str(entry[0])
		var wanted: int = int(entry[1])        # absolute count (area-scale hata diya — upar dekho)
		var min_scale: float = float(entry[2])
		var max_scale: float = float(entry[3])
		var weight_key: String = str(entry[4])
		var green_only: bool = bool(entry[5])

		# ---- performance caps (2000 trees, 1000 rocks) ----
		var cap := 0
		if kind == "tree":
			cap = max_trees
		elif kind == "rock":
			cap = max_rocks
		if cap > 0 and wanted > cap:
			push_warning("Nature: %s ka cap lag gaya (%d -> %d) — max_%ss badhao to aur lagenge"
					% [kind, wanted, cap, kind])
			wanted = cap

		# ---- zone weights se hissa batao (green_only -> sirf hare zones) ----
		var assignments := _distribute(wanted, weight_key, green_only)

		# pehle saari jagah chuno (taaki MultiMesh ek saath bana sake)
		# Building ke paas jagah na mile to DOBARA try karo (sirf drop na karo).
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
						found = true
						break
				if not found:
					continue                    # 20 koshish ke baad bhi jagah nahi
				# ped ka size LAYOUT se — arena (2000m) se scale karte to dev-bade ped bante
				var scale_f: float = rng.randf_range(min_scale, max_scale) * LAYOUT_SCALE
				placements.append({
					"pos": pos,
					"scale": scale_f,
					"variant": counter % 5,
					"yaw": rng.randf() * TAU,
					"zone": zone_name,
				})
				counter += 1

		# ---- kisko alag node (collision ke saath), kisko MultiMesh? ----
		var collidable: bool = kind == "tree" or kind == "rock"
		var node_items: Array = []      # alag nodes (center, collision ke saath)
		var mm_items: Array = []        # MultiMesh (bina collision)
		for item in placements:
			var p: Vector3 = item["pos"]
			if collidable and Vector2(p.x, p.z).length() <= nature_collision_radius:
				node_items.append(item)
			else:
				mm_items.append(item)

		# ---- MultiMesh wala hissa ----
		# Ped/patthar hamesha MultiMesh me (fallback mesh ki wajah se hamesha
		# mumkin — varna 2000 alag nodes phone ko mar denge). Ghaas/plant par
		# purana rule: sirf threshold se zyada hon tab (aur mesh mile tab).
		var spawned := 0
		if not mm_items.is_empty():
			if collidable or placements.size() > multimesh_threshold:
				if _spawn_multimesh(container, kind, mm_items):
					mm_used.append("%s x%d" % [kind, mm_items.size()])
					spawned += mm_items.size()
					mm_items = []
			node_items.append_array(mm_items)   # jo MultiMesh me nahi gaya, node banega

		# ---- alag nodes wala hissa (center ke collision-wale props) ----
		for item in node_items:
			var prop: Node3D = _make_prop(kind, int(item["variant"]), float(item["scale"]),
					str(item["zone"]))
			if prop == null:
				continue
			prop.position = item["pos"]
			prop.rotation.y = float(item["yaw"])       # halka ghumav, natural lage
			container.add_child(prop)
			spawned += 1
		total_placed += spawned
		placed[kind] = spawned

	# ---- ek line summary (CI / phone log me kaam aati hai) ----
	print("Nature: %d props placed %s%s" % [total_placed, placed,
			("  MultiMesh: " + ", ".join(mm_used)) if not mm_used.is_empty() else ""])


## Zone ke sector ke andar UNIFORMLY bikhri jagah (poore arena square me).
## Tareeka: square me random point lo; zone ki dish (±spread) ke andar ho to
## manzoor. Isse density har jagah ek-si rehti hai — na ring ki bheed, na
## center me khaali ghera (2000m ke map par yahi chahiye). Square-uniform
## matlab kinare/konon tak bhi ped honge, sirf gol ghare me nahi.
func _pick_prop_position(zone: Dictionary, inner_limit: float, rng: RandomNumberGenerator) -> Vector3:
	var center_angle: float = deg_to_rad(float(zone.get("angle", 0.0)))
	var spread_rad: float = deg_to_rad(float(zone.get("spread", 44.0)))
	for attempt in 16:
		var pos := Vector3(
				rng.randf_range(-inner_limit, inner_limit), 0.0,
				rng.randf_range(-inner_limit, inner_limit))
		var flat := Vector2(pos.x, pos.z)
		if flat.length() < 4.0:
			continue                    # player spawn (center) ke aas-paas khali rakho
		var diff: float = absf(wrapf(flat.angle() - center_angle, -PI, PI))
		if diff <= spread_rad:
			return pos
	# 16 koshish me sector wala na mila to sector ki dish me polar point
	var angle: float = center_angle + rng.randf_range(-spread_rad, spread_rad)
	var radius: float = rng.randf_range(4.0, inner_limit)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Ye jagah kisi building/cover box ke andar/paas to nahi?
## (ped building ki deewar ya crate ke andar na dhase)
func _prop_spot_free(pos: Vector3) -> bool:
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		var flat := Vector2(pos.x - center.x, pos.z - center.z)
		if flat.length() < float(spot["radius"]) + 1.2:
			return false
	# cover boxes (sirf center layout me hain, isliye ye check sasta hai)
	for item in _obstacles:
		var opos: Vector3 = (item[0] as Vector3) * LAYOUT_SCALE
		var osize: Vector3 = (item[1] as Vector3) * LAYOUT_SCALE
		if absf(pos.x - opos.x) < osize.x * 0.5 + 0.8 \
				and absf(pos.z - opos.z) < osize.z * 0.5 + 0.8:
			return false
	return true


## Props ko MultiMeshInstance3D me daalo — variant ke hisaab se AUR 250m ke
## cells (NATURE_CELL_SIZE) me baant kar. Ek akele 2000-instance MultiMesh ka
## AABB poora map hota hai, isliye wo hamesha poora draw hota (~40 lakh tris,
## 4GB phone mar jaayega). Cells me baantne se camera ke peeche wale cells
## frustum-cull aur door wale visibility-cull ho jaate hain.
##
## Model ka single mesh chahiye — na mile to ped/patthar ke liye procedural
## fallback mesh (_fallback_nature_mesh) lagta hai (taaki hazaaron props kabhi
## alag nodes na banen); ghaas/plant ke liye false (caller alag nodes lagata
## hai — unki ginti kam hai, purana behavior wahi).
## Note: MultiMesh props par zone-tint nahi lagta (sirf center ke alag nodes
## par lagta hai) — scale pe ye jaan-boojh kar chhoda gaya trade-off hai.
func _spawn_multimesh(container: Node3D, kind: String, placements: Array) -> bool:
	# pehle SAARE meshes resolve karo — ek bhi na mile to plan cancel
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

	# (variant, cell) ke hisaab se groups — cell key: arena / 250m
	var groups := {}
	for item in placements:
		var p: Vector3 = item["pos"]
		var key := "%d:%d:%d" % [int(item["variant"]),
				int(floor(p.x / NATURE_CELL_SIZE)), int(floor(p.z / NATURE_CELL_SIZE))]
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
				(float(cell_x) + 0.5) * NATURE_CELL_SIZE, 0.0,
				(float(cell_z) + 0.5) * NATURE_CELL_SIZE)
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
			# node cell-center pe hai, isliye instance positions relative hain;
			# basis * offset mesh ko zameen pe bithata hai (center-origin mesh ke liye)
			var origin: Vector3 = ipos - cell_center + basis * offset
			multimesh.set_instance_transform(i, Transform3D(basis, origin))

		var node := MultiMeshInstance3D.new()
		node.name = "%sMM%d_%d_%d" % [kind.capitalize(), variant, cell_x, cell_z]
		node.multimesh = multimesh
		node.position = cell_center
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# apna AABB khud batao (cell + ped ke phailaav ki jagah) — taaki culling pakki ho
		var half_cell: float = NATURE_CELL_SIZE * 0.5 + 6.0
		node.custom_aabb = AABB(
				Vector3(-half_cell, -1.0, -half_cell),
				Vector3(half_cell * 2.0, 14.0, half_cell * 2.0))
		if nature_view_distance > 0.0:
			node.visibility_range_end = nature_view_distance
		container.add_child(node)
	return true


## Mesh ko zameen pe bithane ka offset: AABB ka sabse neeche wala point y=0 par
## aur XZ center (0,0) par aa jaaye. Downloaded nature meshes pehle se aise
## hi hain (offset lagbhag 0) — center-origin procedural fallback (cone/sphere)
## ke liye ye zaroori hai, warna ped aadha zameen me dhas jaayega.
func _mesh_ground_offset(mesh: Mesh) -> Vector3:
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	return Vector3(-center.x, -aabb.position.y, -center.z)


## Downloaded nature mesh na mile to MultiMesh ke liye saada primitive mesh —
## isi guarantee ki wajah se 2000 ped kabhi galti se 2000 alag nodes nahi bante.
## Rung assets.gd ke procedural ped/patthar wale hi hain.
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
	sphere.height = 0.66            # dabaya hua gola = patthar jaisa
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = mat
	return sphere


## `total` ko zones me weight ke hisaab se baanto (weight 0 wale zones skip).
## `green_only` = true -> sirf GREEN_ZONES (ghaas/plant spec).
## Wapas: {zone_name: count}
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
	names.sort()                       # deterministic order
	var left := total
	for i in names.size():
		var zone_name: String = str(names[i])
		if i == names.size() - 1:
			out[zone_name] = left      # aakhri zone ko bacha hua sab de do
			break
		var count := int(round(float(total) * float(weights[zone_name]) / sum))
		count = mini(count, left)
		out[zone_name] = count
		left -= count
	return out


## Ek nature prop banao. Pehle downloaded model (assets.gd se), warna procedural.
## Zone ke hisaab se tint bhi lagta hai (Himvana safed-ish, Marusthal bhura).
func _make_prop(kind: String, variant: int, scale_f: float, zone_name: String = "") -> Node3D:
	var prop: Node3D = null
	match kind:
		"tree":
			prop = Assets.tree(scale_f, variant)
		"rock":
			prop = Assets.rock(scale_f, variant)
		"bush":
			prop = Assets.bush(scale_f, variant)
		"plant":
			prop = Assets.plant(scale_f, variant)
		"grass":
			prop = Assets.grass_tuft(scale_f, variant)
		_:
			prop = null

	if prop != null and ZONE_TINT.has(zone_name):
		Assets.tint_grey(prop, ZONE_TINT[zone_name])
	return prop


# --------------------------------------------------------------- vehicles ----

## ZONES ke fixed spots pe gaadiyaan rakhta hai (spec: Chowk Taxi+NormalCar1, Haveli Cop,
## Samudra SportsCar, Kanak SUV, Marusthal NormalCar2, + 1 random SportsCar2 = 7).
##
## Abhi ye sirf *static decoration* hai — collision ke saath khadi rehti hain,
## andar baithna/chalana Phase F ka kaam hai. Model na mile to assets.gd ki
## procedural gaadi lagti hai (game kabhi rukta nahi).
func _spawn_vehicles() -> void:
	var container := Node3D.new()
	container.name = "Vehicles"
	add_child(container)

	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed + 7

	# pehle zones ke fixed spots, phir spec wali extra SportsCar2
	var wanted: Array = []
	for zone_name in ZONES:
		for model_name in ZONES[zone_name].get("vehicles", []):
			wanted.append({"zone": zone_name, "model": str(model_name)})
	wanted.append({"zone": "", "model": "SportsCar2"})

	var count := 0
	for item in wanted:
		if count >= vehicle_count:
			break
		var spot := _find_vehicle_spot(str(item["zone"]), rng)
		if spot.is_empty():
			continue
		var body := _make_vehicle(str(item["model"]))
		if body == null:
			continue
		body.position = spot["pos"]
		body.rotation.y = float(spot["yaw"])
		if not vehicle_collision:
			Assets.disable_collision(body)
		container.add_child(body)
		_vehicle_spots.append({"pos": spot["pos"], "radius": 2.6})
		count += 1

	print("Vehicles: %d placed" % count)


## Gaadi ke liye jagah: apni zone ke ring pe, buildings aur doosri gaadiyon se door.
## Extra (random) gaadi ke liye koi bhi zone chalega.
##
## Buildings ring ka bada hissa le lete hain, isliye 60 koshish + "sabse khali jagah"
## wala best-effort: 7 me se ek bhi gaadi drop nahi hoti.
func _find_vehicle_spot(zone_name: String, rng: RandomNumberGenerator) -> Dictionary:
	var zone: Dictionary = ZONES.get(zone_name, {})
	if zone.is_empty():
		var names := ZONES.keys()
		zone = ZONES[names[rng.randi() % names.size()]]
	var base_angle := deg_to_rad(float(zone.get("angle", 0.0)))
	# gaadiyaan center ke layout (LAYOUT_SIZE) me hi — purane spots ke aas-paas
	var limit: float = LAYOUT_SIZE * 0.5 - 3.0

	var best := {}
	var best_gap := -1e9
	for attempt in 60:
		var angle := base_angle + rng.randf_range(-0.9, 0.9)
		var radius := LAYOUT_SIZE * rng.randf_range(0.24, 0.46)
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(pos.x) > limit or absf(pos.z) > limit:
			continue                              # boundary deewar se door
		var gap := _building_gap(pos)
		if gap > 2.2 and _vehicle_spot_free(pos):
			return {"pos": pos, "yaw": atan2(-pos.x, -pos.z) + rng.randf_range(-0.4, 0.4)}
		if gap > best_gap:
			best_gap = gap
			best = {"pos": pos, "yaw": atan2(-pos.x, -pos.z) + rng.randf_range(-0.4, 0.4)}
	# koi bhi jagah 2.2 m se door nahi mili -> jo sabse khali thi wahi le lo
	return best


## Pos se nazdeeki building ki deewar tak ka gap (metres). Bada = zyada khali.
func _building_gap(pos: Vector3) -> float:
	var gap := 1e9
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		var d := Vector2(pos.x - center.x, pos.z - center.z).length()
		gap = minf(gap, d - float(spot.get("max_half", spot["radius"])))
	return gap


## Doosri gaadi se door hai? (4.5 m — gaadi 4.4 m lambi hai)
func _vehicle_spot_free(pos: Vector3) -> bool:
	for spot in _vehicle_spots:
		var vcenter: Vector3 = spot["pos"]
		if Vector2(pos.x - vcenter.x, pos.z - vcenter.z).length() < 4.5:
			return false
	return true


## Ek gaadi: downloaded model (collision ke saath) ya procedural fallback
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
	# tiles ka size metres me wahi rakho jo 52m layout me tha (52m/20 = 2.6m) —
	# warna 2000m ki zameen par ek tile 100m ka dikhega.
	material.set_shader_parameter("tiles", 20.0 * arena_size / LAYOUT_SIZE)
	return material


# ------------------------------------------------- plane drop (BR start) ----

## Match shuru: player 300m upar plane me, plane map ke paar udta hai.
func _start_plane_drop() -> void:
	_plane = _build_drop_plane()
	_plane.position = plane_start
	_plane_time = 0.0
	_plane_active = true
	_ejected = false

	# PERF (4GB): drop ke dauran shadow rendering band — 2000 pedo ki shadow
	# mehngi hai aur itni unchaii se waise bhi koi nahi dekh raha.
	# Landing pe wapas on hota hai (_on_player_landed dekho).
	sun.shadow_enabled = false

	player.begin_plane_drop()
	hud.show_drop_ui()
	hud.set_drop_countdown(auto_eject_time)
	print("DROP: plane started at %s, auto-eject in %.0fs" % [plane_start, auto_eject_time])


## Plane ke bina match (plane_drop_enabled = false) — pehle jaisa seedha shuru
func _start_ground_match() -> void:
	spawn_timer.start()
	_spawn_enemy()


func _physics_process(delta: float) -> void:
	if not _plane_active or _plane == null or not is_instance_valid(_plane):
		return

	_plane_time += delta
	_plane.position += plane_direction.normalized() * plane_speed * delta

	if not _ejected:
		# player har frame plane ke saath seat pe (upar-neeche nahi girta)
		player.global_position = _plane.position + PLANE_SEAT_OFFSET
		hud.set_drop_countdown(maxf(0.0, auto_eject_time - _plane_time))

		# PC: Space = turant jump out (mobile: HUD ka JUMP OUT button)
		if Input.is_action_just_pressed("jump"):
			_eject_player()
	elif _plane.position.length() > 3200.0 or _plane_time > 90.0:
		_plane.queue_free()               # plane door nikal gaya — node free
		_plane = null
		_plane_active = false


## JUMP OUT button / Space / auto-eject — sab yahan se
func _eject_player() -> void:
	if not _plane_active or _ejected:
		return
	if not player.is_in_plane():
		return
	_ejected = true
	hud.hide_drop_ui()
	player.eject_from_plane()
	print("DROP: player ejected at %s" % player.global_position)


## Sada low-poly plane: sirf 9 box (koi texture nahi, shadow off — 4GB perf).
## Nose +X ki taraf hai, isliye plane_direction (1,0,0) ke saath seedha chalta hai.
## Andar se dekho to fuselage diwarein backface-cull hoti hain (khuli darwaza
## jaisa) — neeche ka poora 2km map dikhta hai, drop point chunne me aasan.
func _build_drop_plane() -> Node3D:
	var plane := Node3D.new()
	plane.name = "DropPlane"

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.87, 0.90)
	body_mat.roughness = 0.85
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.16, 0.20, 0.28)
	dark_mat.roughness = 0.95

	_add_plane_box(plane, Vector3(0.0, 0.0, 0.0), Vector3(14.0, 3.4, 3.2), body_mat)      # fuselage
	_add_plane_box(plane, Vector3(8.0, -0.4, 0.0), Vector3(2.4, 2.0, 2.2), body_mat)      # nose
	_add_plane_box(plane, Vector3(6.0, 0.9, 0.0), Vector3(1.8, 0.9, 2.4), dark_mat)       # cockpit
	_add_plane_box(plane, Vector3(0.0, -1.55, 0.0), Vector3(12.0, 0.3, 2.2), dark_mat)    # floor
	_add_plane_box(plane, Vector3(-0.5, -1.1, 0.0), Vector3(4.5, 0.35, 20.0), body_mat)   # wing
	_add_plane_box(plane, Vector3(-0.5, -1.7, 5.5), Vector3(2.6, 1.4, 1.4), dark_mat)     # engine L
	_add_plane_box(plane, Vector3(-0.5, -1.7, -5.5), Vector3(2.6, 1.4, 1.4), dark_mat)    # engine R
	_add_plane_box(plane, Vector3(-6.4, 1.8, 0.0), Vector3(2.0, 3.4, 0.35), body_mat)     # tail fin
	_add_plane_box(plane, Vector3(-6.4, -0.2, 0.0), Vector3(1.6, 0.3, 6.5), body_mat)     # tail wing

	add_child(plane)
	return plane


func _add_plane_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	# PERF: shadow cast band (300m upar shadow ka koi fayda nahi)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _on_player_parachute_opened() -> void:
	hud.show_toast("PARACHUTE DEPLOYED!")


func _on_player_landed() -> void:
	hud.show_toast("Landed!")
	sun.shadow_enabled = true          # shadows wapas — ab ground fight shuru
	if not game_over:
		_start_ground_match()          # ab dushman spawn hona shuru


func _on_hud_sprint_pressed() -> void:
	player.set_sprint_requested(true)


func _on_hud_sprint_released() -> void:
	player.set_sprint_requested(false)


# ------------------------------------------------------------- enemy spawn --

func _on_spawn_timer_timeout() -> void:
	if game_over:
		return
	if player.is_dropping():               # safety: abhi plane/chute phase me hain
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
	var safe_distance: float = minf(min_spawn_distance, LAYOUT_SIZE * 0.35)
	for p in points:
		var flat_distance: float = Vector2(p.x - player_pos.x, p.z - player_pos.z).length()
		if flat_distance > safe_distance:
			return p
	return points[0]


## Spawn points center-layout (LAYOUT_SIZE) ke kinare pe — par building ke andar
## nahi (warna dushman deewar ke andar paida ho jayega). Har direction ke liye
## 3 radius try karte hain. (2000m arena ke kinare spawn karte to dushman
## player tak pahunchne me hi 5 minute laga deta — gameplay center me hi hai.)
func _spawn_points() -> Array:
	var out: Array = []
	for i in 8:
		var angle := TAU * float(i) / 8.0
		for r_scale in [0.40, 0.34, 0.28]:
			var radius: float = LAYOUT_SIZE * float(r_scale)
			var point := Vector3(cos(angle) * radius, 0.3, sin(angle) * radius)
			if _spawn_point_free(point):
				out.append(point)
				break
	if out.is_empty():
		out.append(Vector3(0.0, 0.3, 0.0))      # aakhri sahara (kabhi crash nahi)
	return out


## Spawn point kisi building ke andar/paas to nahi?
func _spawn_point_free(point: Vector3) -> bool:
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		var flat := Vector2(point.x - center.x, point.z - center.z)
		if flat.length() < float(spot["radius"]) + 1.4:
			return false
	return true


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
