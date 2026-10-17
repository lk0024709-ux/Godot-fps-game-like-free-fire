extends Node3D
##
## Main (game manager)
## - Arena banata hai: zameen + chaaron taraf deewar + thode cover boxes (sab code se)
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
const BUILDING := preload("res://scripts/building_builder.gd")

@export_group("Enemy Spawning")
@export var spawn_interval: float = 1.8          ## kitne second me naya enemy
@export var fastest_spawn_interval: float = 0.9  ## max difficulty pe itna fast
@export var max_enemies: int = 8                 ## ek waqt me itne enemies
@export var min_spawn_distance: float = 9.0      ## player se itni door spawn

@export_group("Arena")
## 52x52m — pehle 40 tha, par 14 buildings (barn 12x8) 40x40 ke ring me fit nahi hote.
## Nature/vehicle/buildings sab isi se scale hote hain (ARENA_REFERENCE = 40).
@export var arena_size: float = 52.0             ## maidan kitna bada (52 = 52x52m)

@export_group("Nature")
## Ye seed fix hai — isliye har baar wahi ped/patthar/ghaas wahi jagah pe ugte hain.
## Badal ke dekho: pura layout badal jayega (par phir bhi deterministic rahega).
@export var nature_seed: int = 20241015
@export var tree_count: int = 26                 ## ped (deewar ke paas patti me)
@export var rock_count: int = 18                 ## patthar
@export var bush_count: int = 14                 ## jhaadiyaan
@export var grass_count: int = 40                ## ghaas ke guchhe (inme collision nahi hota)
@export var plant_count: int = 20                ## plant / phool (inme bhi collision nahi)
## Performance cap (spec): isse zyada ped/patthar kabhi nahi lagenge. Cap lagna to
## console me warning aati hai — TUNING ke liye numbers yahin badlo.
@export var max_trees: int = 80
@export var max_rocks: int = 50
## Ghaas/plant sirf in "hare-bhare" zones me lagte hain (spec). Baaki zones me
## patthar/registan hai -> wahan ghaas nahi ugeti.
const GREEN_ZONES: Array[String] = ["Haveli", "Haritvan", "Khet", "Kanak"]
## 40 se zyada grass/plant ho to MultiMeshInstance3D use hota hai (ek draw call)
@export var multimesh_threshold: int = 40
## Patti: props deewar ke kitne paas lage (1.0 = deewar tak, 0.7 = thoda andar tak)
@export var props_band_factor: float = 0.62

@export_group("Buildings")
@export var buildings_enabled: bool = true       ## enterable buildings banao?
@export var max_buildings: int = 18              ## spec: map pe max 18 buildings

@export_group("Vehicles")
@export var vehicle_count: int = 7               ## spec: 7 gaadiyaan (zones ke fixed spots pe)
@export var vehicle_collision: bool = true       ## aar-paar jaane wale gaadi pe box collision
## NOTE: gaadi me baithna/chadhna (enter-exit physics) Phase F ka kaam hai —
## abhi ye sirf static decoration hai (takkar hoti hai, par chal nahi sakte).

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

	# ---- buildings PEHLE (unki jagah reserve ho jaye), phir nature ----
	_build_buildings()

	# ---- nature: ped / patthar / ghaas (hybrid: OBJ model ya procedural) ----
	_scatter_nature()


# ------------------------------------------------------------- buildings ----

## BOUNDARY_BOXES: _obstacles ke pehle 4 boxes arena ki boundary deewarein hain
## (inhe building ke clash check me nahi ginte — arena ki limit alag se check hoti hai).
const BOUNDARY_BOXES := 4


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
			var building: Node3D = BUILDING.build(kind)
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
func _building_candidates() -> Array:
	var out: Array = []
	var half_arena: float = arena_size * 0.5
	var step := 0.5
	var n := int(half_arena / step)
	var min_dist: float = arena_size * 0.17
	var max_dist: float = half_arena - 1.5
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
	var half_arena: float = arena_size * 0.5
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
		if absf(pos.x) + fw * 0.5 > half_arena - 1.2 or absf(pos.z) + fd * 0.5 > half_arena - 1.2:
			continue
		if _footprint_hits_obstacle(pos.x, pos.z, fw, fd):
			continue
		if _footprint_hits_building(pos.x, pos.z, fw, fd):
			continue

		var score := diff * 10.0 + absf(float(cand["dist"]) - arena_size * 0.34)
		if score < best_score:
			best_score = score
			best = {"pos": pos, "yaw": yaw, "half": Vector2(fw * 0.5, fd * 0.5)}
	return best


## Building ka footprint (fw x fd, AABB) kisi cover box / low wall se takrata hai?
func _footprint_hits_obstacle(x: float, z: float, fw: float, fd: float) -> bool:
	var scale_f: float = arena_size / ARENA_REFERENCE
	for i in _obstacles.size():
		if i < BOUNDARY_BOXES:
			continue
		var item: Array = _obstacles[i]
		var opos: Vector3 = (item[0] as Vector3) * scale_f
		var osize: Vector3 = (item[1] as Vector3) * scale_f
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
## Props deewar ke paas wali patti me rakhe jaate hain (beech ka khel ka maidan khula
## rehta hai) — aur buildings ki jagah chhod dete hain.
##
## Har prop pehle downloaded OBJ model try karta hai, warna procedural shape
## (dekho scripts/assets.gd + scripts/asset_loader.gd). Download fail ho to ye
## function wahi kaam procedural se kar deta hai — koi error nahi.
##
## Spec ke numbers:
##   pine  scale 0.9-1.4, CapsuleShape3D collision (r=0.5)
##   rock  scale 0.7-1.4, BoxShape3D collision
##   grass/plant — sirf GREEN_ZONES me, collision nahi, aur 40 se zyada ho to
##                 MultiMeshInstance3D (ek draw call)
func _scatter_nature() -> void:
	var arena_scale: float = arena_size / ARENA_REFERENCE
	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed

	var inner_radius: float = arena_size * 0.5 - 1.3        # deewar se thoda andar
	# chhote maidan me kam props (warna bhare-bhare lagega)
	var area_scale: float = maxf(0.3, arena_scale * arena_scale)

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
		var wanted: int = int(float(int(entry[1])) * area_scale)
		var min_scale: float = float(entry[2])
		var max_scale: float = float(entry[3])
		var weight_key: String = str(entry[4])
		var green_only: bool = bool(entry[5])

		# ---- performance caps (spec: 80 trees, 50 rocks) ----
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
		# Building ke paas jagah na mile to DOBARA try karo (sirf drop na karo) —
		# warna 14 buildings poora ring kha jati hain aur ped/ghaas kam reh jate hain.
		var placements: Array = []
		var counter := 0
		for zone_name in assignments:
			var zone_count: int = int(assignments[zone_name])
			var zone: Dictionary = ZONES[zone_name]
			for i in zone_count:
				var pos := Vector3.ZERO
				var found := false
				for attempt in 20:
					pos = _pick_prop_position(zone, inner_radius, rng)
					if _prop_spot_free(pos):
						found = true
						break
				if not found:
					continue                    # 20 koshish ke baad bhi jagah nahi
				var scale_f: float = rng.randf_range(min_scale, max_scale) * arena_scale
				placements.append({
					"pos": pos,
					"scale": scale_f,
					"variant": counter % 5,
					"yaw": rng.randf() * TAU,
					"zone": zone_name,
				})
				counter += 1

		# ---- 40+ ghaas/plant -> MultiMeshInstance3D (ek draw call) ----
		if (kind == "grass" or kind == "plant") and placements.size() > multimesh_threshold:
			if _spawn_multimesh(container, kind, placements):
				mm_used.append("%s x%d" % [kind, placements.size()])
				placed[kind] = placements.size()
				total_placed += placements.size()
				continue
			# model MultiMesh ke laayak nahi -> neeche individual nodes hi lagenge

		for item in placements:
			var prop: Node3D = _make_prop(kind, int(item["variant"]), float(item["scale"]),
					str(item["zone"]))
			if prop == null:
				continue
			prop.position = item["pos"]
			prop.rotation.y = float(item["yaw"])       # halka ghumav, natural lage
			container.add_child(prop)
			total_placed += 1
		placed[kind] = placements.size()

	# ---- ek line summary (CI / phone log me kaam aati hai) ----
	print("Nature: %d props placed %s%s" % [total_placed, placed,
			("  MultiMesh: " + ", ".join(mm_used)) if not mm_used.is_empty() else ""])


## Kisi zone me ek prop ki jagah (center se `zone.angle` wali dish me, thoda bikhra hua)
func _pick_prop_position(zone: Dictionary, inner_radius: float, rng: RandomNumberGenerator) -> Vector3:
	var center_angle: float = deg_to_rad(float(zone.get("angle", 0.0)))
	var half: float = arena_size * 0.5
	var band := clampf(props_band_factor, 0.3, 0.98)
	var spread_deg: float = float(zone.get("spread", 44.0))
	for attempt in 12:
		var angle: float = center_angle + deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
		var radius: float = rng.randf_range(inner_radius * band, inner_radius)
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		# deewar ke andar hi raho (chhote maidan me bhi safe)
		pos.x = clampf(pos.x, -half + 1.0, half - 1.0)
		pos.z = clampf(pos.z, -half + 1.0, half - 1.0)
		# beech ka maidan khula rakho (spawn ring 0.40 pe hai, props uske thoda andar
		# se shuru ho sakte hain — buildings ki wajah se ring tang hai)
		if Vector2(pos.x, pos.z).length() < arena_size * 0.33:
			continue
		return pos
	# 12 koshish me na mila to ring pe hi rakh do
	var fallback_angle := center_angle + deg_to_rad(rng.randf_range(-spread_deg, spread_deg))
	return Vector3(cos(fallback_angle) * inner_radius, 0.0, sin(fallback_angle) * inner_radius)


## Ye jagah kisi building ke andar/paas to nahi? (ped building ki deewar me na dhase)
func _prop_spot_free(pos: Vector3) -> bool:
	for spot in _building_spots:
		var center: Vector3 = spot["pos"]
		var flat := Vector2(pos.x - center.x, pos.z - center.z)
		if flat.length() < float(spot["radius"]) + 1.2:
			return false
	return true


## Ghaas/plant ko MultiMeshInstance3D me daalo (40+ instances = 1 draw call).
## Model ka single mesh chahiye — na mile to false (caller individual nodes lagayega).
func _spawn_multimesh(container: Node3D, kind: String, placements: Array) -> bool:
	var groups := {}
	for item in placements:
		var variant := int(item["variant"])
		if not groups.has(variant):
			groups[variant] = []
		groups[variant].append(item)

	# pehle SAARE meshes resolve karo — koi ek bhi na mile to plan cancel
	var meshes := {}
	for variant in groups:
		var mesh := Assets.nature_mesh(kind, int(variant))
		if mesh == null:
			return false
		meshes[variant] = mesh

	for variant in groups:
		var items: Array = groups[variant]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[variant]
		multimesh.instance_count = items.size()
		for i in items.size():
			var item: Dictionary = items[i]
			var s: float = float(item["scale"])
			var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * s)
			var ipos: Vector3 = item["pos"]
			multimesh.set_instance_transform(i, Transform3D(basis, ipos))
		var node := MultiMeshInstance3D.new()
		node.name = "%sMultiMesh%d" % [kind.capitalize(), int(variant)]
		node.multimesh = multimesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(node)
	return true


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
	var limit: float = arena_size * 0.5 - 3.0

	var best := {}
	var best_gap := -1e9
	for attempt in 60:
		var angle := base_angle + rng.randf_range(-0.9, 0.9)
		var radius := arena_size * rng.randf_range(0.24, 0.46)
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


## Spawn points arena ke kinare pe — par building ke andar nahi (warna dushman
## deewar ke andar paida ho jayega). Har direction ke liye 3 radius try karte hain.
func _spawn_points() -> Array:
	var out: Array = []
	for i in 8:
		var angle := TAU * float(i) / 8.0
		for r_scale in [0.40, 0.34, 0.28]:
			var radius: float = arena_size * float(r_scale)
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
