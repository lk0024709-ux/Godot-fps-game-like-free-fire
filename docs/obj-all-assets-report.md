# OBJ assets (nature + characters + vehicles) + buildings — integration report

**Ek line me:** OBJ pack ke **129 models** (40 weapons + 66 nature + 16 characters + 7 vehicles) build ke waqt GLB me convert hote hain, game unhe use karta hai — 14 enterable buildings, Capsule/Box collision, MultiMesh ghaas, 7 gaadiyaan — CI **green**, APK 27.2 MB.

## 0) Kya kya joda gaya

| Cheez | Kitna | Kahan |
|---|---|---|
| Weapons | 40 models | pehle se integrated (iss kaam me chhua nahi) |
| Nature | 66 models (map pe pines/rocks/plants/grass use hote hain) | `assets/models/nature/` |
| Characters | 16 models (10 roster pehle se the; male_1 = Male_Suit) | `assets/models/characters/` |
| Vehicles | 7 models (saare map pe lage) | `assets/models/vehicles/` |
| Buildings | 14 (plan) — small_house 6×6×3, big_house 10×8×4, barn 12×8×5, shop 8×6×3.5 | `scripts/building_builder.gd` |

## 1) Model counts (source folders)

| Folder | `.obj` | `.mtl` | GLB mode |
|---|---|---|---|
| `assets/downloaded_obj/Weapons/` | 40 | 40 | `weapon` (barrel −Z, 1.0 m) |
| `assets/downloaded_obj/Nature/` | 66 | 66 | `prop` (Y-up, metres) |
| `assets/downloaded_obj/Characters/` | 16 | 16 | `character` (Y-up, 180°, metres) |
| `assets/downloaded_obj/Vehicles/` | 7 | 7 | `vehicle` (Y-up, 180°, metres) |
| **Total** | **129** | **129** | 5.2 s conversion, 19.5 MB → 11.6 MB |

Local validation: `tools/obj2glb.py` **129/129 converted**, `tools/glbcheck.py` **129/129, 0 errors**, 292,428 triangles. Har GLB ka base `y = 0`, X/Z centre; characters/vehicles ka muh/headlights **−Z** (GLB accessor se verify: eyes −0.27, headlights −1.62).

## 2) MODIFIED files (changed sections)

| File | Kya badla |
|---|---|
| `tools/obj2glb.py` | **Mode system**: folder se `weapon` / `prop` / `character` / `vehicle` auto-detect. `orient_matrix()` ab mode leta hai; prop = identity (Y-up), character/vehicle = `rotY(180)`. Size: weapon = longest→1.0, baaki = **asli metres** + base `y=0` + X/Z centre. Naya `--mode` flag, report me `kind`/`units`, CLI summary me per-mode counts. |
| `.github/workflows/build-apk.yml` | Step **7d** ka naam/comment: ab chaaron folders convert hote hain; har category ka GLB count print hota hai (`weapons/nature/characters/vehicles`) + nature ke liye warning. FBX step `--skip-existing` (OBJ versions hi jeette hain). |
| `scripts/asset_loader.gd` | `CHARACTER_FILES` naya mapping — **male_1 = Male_Suit**, male_2..8 = Casual/Shirt/LongSleeve + Smooth…; female_1..8 = Casual/Dress/Alternative/TankTop + Smooth…. `VEHICLE_FILES` **7 asli naam** (Cop, NormalCar1/2, Taxi, SUV, SportsCar/2) + purane aliases (`sedan→NormalCar1`, `sedan_2→NormalCar2`, `sports_2→SportsCar2`). Nature aliases se purana `pine_5→PineTree_1` hack hataya (ab asli PineTree_5 hai); `bush*` aliases jode. |
| `scripts/assets.gd` | Ped ke liye naya **`_ensure_capsule_collision()`** (radius 0.5 m) — `_ensure_collision()` `kind == "tree"` pe wahi use karta hai. Naya **`nature_mesh(kind, variant) -> Mesh`** (MultiMesh ke liye single-mesh model). Naya **`set_render_layer(node, layer)`** (player body layer 2 ke liye). |
| `scripts/main.gd` | `arena_size` **40 → 52** (14 buildings 40×40 ke ring me fit nahi hote — barn 12×8 hai). Naya **`BUILDING_PLAN`** + `_build_buildings()` / `_building_candidates()` / `_find_building_spot()` / `_footprint_hits_obstacle()` / `_footprint_hits_building()` (grid 0.5 m, zone ke ±90°, darwaza centre ki taraf, obstacles/buildings se clearance). `_scatter_nature()` rewrite: per-kind scale **tree 0.9–1.4, rock 0.7–1.4**, grass/plant **sirf GREEN_ZONES** (Haveli/Haritvan/Khet/Kanak), 40+ pe **MultiMeshInstance3D**, building ke andar prop nahi. `_distribute()` me `green_only`. Vehicle: **7** (zones + extra SportsCar2), building/vehicle clearance, naye model naam. `_spawn_points()` building ke andar spawn nahi karta. |
| `scripts/player.gd` | Body + name tag **render layer 2**; camera ka `cull_mask` se layer 2 hataya → **FPS me apna body invisible** (spec). Purana 'head node chhupao' code hata (OBJ character single mesh hai). |
| `scripts/enemy.gd` | `_has_limbs` flag: alag `leg_l/leg_r/arm_l/arm_r` mile to wahi hilte hain, warna **poora body sine bounce + sway** karta hai (OBJ characters ek hi mesh hain). Tint/height/HP sab waise hi. |
| `scripts/selftest.gd` | Har category ke models print; **count assertions** (weapons ≥40, nature ≥60, characters ≥16, vehicles ≥7) sirf tab jab source folder maujood ho; nature/character/vehicle naam-resolution checks; **tree CapsuleShape3D** check; **4 buildings** (solid pieces ≥6, 1 OmniLight3D, footprint) check. |
| `README.md`, `docs/model-assets-notes.md` | Files list, buildings, OBJ modes table, runtime scaling/collision table. |
| `.gitignore` | `assets/downloaded_obj/**/*.glb|.gltf|.obj.import` (pehle se tha, sirf comment update). |

## 3) NEW file — `scripts/building_builder.gd` (poora content)

```gdscript
extends RefCounted
##
## BuildingBuilder — procedural, ENTERABLE buildings (Phase 5).
##
## Har building code se banti hai: floor + deewar ke tukde + ceiling + andar light
## + furniture. Koi texture nahi, sirf BoxMesh + StandardMaterial3D (procedural
## fallback wali hi style — poora game bina image ke chalta hai).
##
## Sabse zaroori baat: **deewar ke har tukde ka apna StaticBody3D + BoxShape3D hai**
## (spec). Isliye player deewar ke through nahi ja sakta, par darwaze ke gap se
## andar aa sakta hai. Darwaza "kaat kar" nahi banta — deewar 3 tukdo me banti hai:
##   left piece | door gap | right piece
##   upar lintel (gap ke oopar wala hissa)
##
## Chaar types (spec ke sizes):
##   small_house  6 x 3   x 6   — 1 door (1.2 x 2.2), aage ki deewar me
##   big_house    10 x 4  x 8   — 2 door (aage + peeche)
##   barn         12 x 5  x 8   — 1 bada door (3 x 3.5)
##   shop         8 x 3.5 x 6   — khula front: counter + 2 m ka entrance gap
##
## Building ka origin = floor ka center, zamin par (y=0). **Front = +Z** —
## main.gd building ko ghumata hai taaki darwaza arena ke beech ki taraf ho.
##
## Istemal (main.gd):
##     var b := BUILDING.build("small_house")     # Node3D (fail-soft: null)
##     b.position = spot
##     b.rotation.y = yaw
##
## Performance: ek building me ~8-12 StaticBody3D + 1 OmniLight3D. 14 buildings
## milakar ~150 bodies — mobile ke liye theek hai (koi shadow-casting light nahi).
##

const WALL_T := 0.25              ## deewar ki motai (metres)
const FLOOR_T := 0.30
const CEIL_T := 0.22

## kind -> (width x, height y, depth z) — spec ke sizes
const SIZES := {
	"small_house": Vector3(6.0, 3.0, 6.0),
	"big_house": Vector3(10.0, 4.0, 8.0),
	"barn": Vector3(12.0, 5.0, 8.0),
	"shop": Vector3(8.0, 3.5, 6.0),
}

## kind -> kitne darwaze (0 = khula front / counter)
const DOORS := {
	"small_house": 1,
	"big_house": 2,
	"barn": 1,
	"shop": 0,
}

## Darwaze ka size (width, height). Shop ka "gap" alag se handle hota hai.
const DOOR_SIZE := {
	"small_house": Vector2(1.2, 2.2),
	"big_house": Vector2(1.2, 2.2),
	"barn": Vector2(3.0, 3.5),
}

## Har kind ke rang (walls, roof, floor, wood)
const COLORS := {
	"small_house": [Color(0.78, 0.73, 0.62), Color(0.42, 0.30, 0.24), Color(0.52, 0.47, 0.40)],
	"big_house": [Color(0.72, 0.68, 0.60), Color(0.38, 0.28, 0.24), Color(0.48, 0.44, 0.38)],
	"barn": [Color(0.56, 0.34, 0.20), Color(0.32, 0.20, 0.13), Color(0.44, 0.30, 0.20)],
	"shop": [Color(0.70, 0.66, 0.56), Color(0.36, 0.34, 0.30), Color(0.46, 0.42, 0.36)],
}


## Building ka footprint (width, depth) — main.gd placement ke liye
static func footprint(kind: String) -> Vector2:
	var size: Vector3 = SIZES.get(kind, Vector3.ZERO)
	return Vector2(size.x, size.z)


## Poori building banao. Node3D wapas (andar saare StaticBody3D pieces).
## Unknown kind / kuch bhi galat -> null (caller skip kar dega).
static func build(kind: String) -> Node3D:
	if not SIZES.has(kind):
		return null
	var size: Vector3 = SIZES[kind]
	var colors: Array = COLORS[kind]
	var wall_color: Color = colors[0]
	var roof_color: Color = colors[1]
	var floor_color: Color = colors[2]

	var root := Node3D.new()
	root.name = "Building_" + kind
	root.set_meta("kind", kind)
	root.set_meta("footprint", Vector2(size.x, size.z))

	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var hw := w * 0.5
	var hd := d * 0.5

	var wall_mat := _mat(wall_color, 0.0, 0.92)
	var roof_mat := _mat(roof_color, 0.0, 0.95)
	var floor_mat := _mat(floor_color, 0.0, 0.98)

	# ---- floor (andar se chalne ke liye) ----
	_solid(root, "Floor", Vector3(w, FLOOR_T, d), Vector3(0.0, -FLOOR_T * 0.5, 0.0), floor_mat)

	# ---- ceiling / roof ----
	_solid(root, "Ceiling", Vector3(w, CEIL_T, d), Vector3(0.0, h + CEIL_T * 0.5, 0.0), roof_mat)

	# ---- walls ----
	if kind == "shop":
		_build_shop_front(root, w, h, wall_mat)
	else:
		var door: Vector2 = DOOR_SIZE[kind]
		_build_wall_with_door(root, "Front", w, h, d * 0.5, door, wall_mat)
		if int(DOORS.get(kind, 1)) >= 2:
			_build_wall_with_door(root, "Back", w, h, -d * 0.5, door, wall_mat)
		else:
			_solid(root, "BackWall", Vector3(w, h, WALL_T), Vector3(0.0, h * 0.5, -d * 0.5), wall_mat)

	# side walls (dono taraf, hamesha solid)
	_solid(root, "WallLeft", Vector3(WALL_T, h, d), Vector3(-hw + WALL_T * 0.5, h * 0.5, 0.0), wall_mat)
	_solid(root, "WallRight", Vector3(WALL_T, h, d), Vector3(hw - WALL_T * 0.5, h * 0.5, 0.0), wall_mat)

	# ---- andar ki light (chhat ke neeche) ----
	var light := OmniLight3D.new()
	light.name = "InteriorLight"
	light.position = Vector3(0.0, h - 0.35, 0.0)
	light.omni_range = maxf(w, d) * 0.8
	light.light_energy = 1.15
	light.light_color = Color(1.0, 0.88, 0.70)
	light.shadow_enabled = false          # mobile: 14 lights ke saath shadow mehnga hai
	root.add_child(light)

	_add_furniture(root, kind, w, h, d)

	return root


# ------------------------------------------------------------------ walls ----

## Front (z=+d/2) ya back (z=-d/2) wall — beech me darwaza, 3 tukde.
## Aage/peeche dono ek hi tarah banti hain; `label` sirf node ke naam ke liye hai.
static func _build_wall_with_door(root: Node3D, label: String, w: float, h: float, z: float,
		door: Vector2, mat: Material) -> void:
	var door_w: float = minf(door.x, w - 1.6)       # deewar me itna hi gap aa sakta hai
	var door_h: float = minf(door.y, h - 0.35)
	var half_gap := door_w * 0.5

	# left + right pieces (darwaze ke dono taraf)
	var left_len := w * 0.5 - half_gap
	if left_len > 0.05:
		_solid(root, label + "WallLeft", Vector3(left_len, h, WALL_T),
				Vector3(-(half_gap + left_len * 0.5), h * 0.5, z), mat)
		_solid(root, label + "WallRight", Vector3(left_len, h, WALL_T),
				Vector3(half_gap + left_len * 0.5, h * 0.5, z), mat)

	# lintel — darwaze ke gap ke oopar ka tukda
	var lintel_h := h - door_h
	if lintel_h > 0.05:
		_solid(root, label + "Lintel", Vector3(door_w, lintel_h, WALL_T),
				Vector3(0.0, door_h + lintel_h * 0.5, z), mat)


## Shop ka front: counter (0.9m) + ek taraf 2m ka khula entrance.
## Isliye player counter ke bagal se andar aa sakta hai (counter par se nahi).
static func _build_shop_front(root: Node3D, w: float, h: float, mat: Material) -> void:
	var z: float = SIZES["shop"].z * 0.5
	var entrance_w := 2.0
	var counter_w: float = w - entrance_w
	var counter_h := 0.95

	_solid(root, "FrontCounter", Vector3(counter_w, counter_h, 0.45),
			Vector3(-w * 0.5 + counter_w * 0.5, counter_h * 0.5, z - 0.1), mat)
	# entrance ke oopar ka hissa (chhat tak) — dukaan ka "sign board" jaisa
	_solid(root, "FrontLintel", Vector3(entrance_w, h - counter_h, WALL_T),
			Vector3(w * 0.5 - entrance_w * 0.5, counter_h + (h - counter_h) * 0.5, z), mat)
	# counter ke oopar halka board
	_solid(root, "CounterBoard", Vector3(counter_w, h - counter_h - 0.2, WALL_T),
			Vector3(-w * 0.5 + counter_w * 0.5, counter_h + (h - counter_h) * 0.5, z), mat)


# --------------------------------------------------------------- furniture ---

## Andar ka furniture (spec: crate = full cover, table = half, shelf = full, bed = half).
## Sab solid hain (takkar hoti hai) — yahi andar cover ka kaam karta hai.
## Darwaze ka rasta khula rehta hai (x = 0 ke aas-paas 1.4m).
static func _add_furniture(root: Node3D, kind: String, w: float, h: float, d: float) -> void:
	var wood := _mat(Color(0.52, 0.36, 0.20), 0.0, 0.85)
	var dark_wood := _mat(Color(0.36, 0.24, 0.14), 0.0, 0.9)
	var cloth := _mat(Color(0.62, 0.24, 0.22), 0.0, 0.95)
	var table_h := 0.80
	var hw := w * 0.5
	var hd := d * 0.5

	match kind:
		"small_house":
			_crate(root, Vector3(-hw + 0.8, 0.5, -hd + 0.8), 1.0, wood)
			_table(root, Vector3(hw - 1.2, table_h * 0.5, 0.3), Vector2(1.6, 0.9), table_h, dark_wood)
			_bed(root, Vector3(-hw + 0.75, 0.25, hd - 1.5), 0.9, 2.0, cloth, wood)
		"big_house":
			_crate(root, Vector3(-hw + 0.8, 0.5, -hd + 0.8), 1.0, wood)
			_crate(root, Vector3(-hw + 1.95, 0.5, -hd + 0.8), 1.0, wood)
			_shelf(root, Vector3(hw - 0.45, 0.9, -hd + 1.2), 1.8, h, dark_wood)
			_table(root, Vector3(1.8, table_h * 0.5, hd - 2.6), Vector2(1.8, 1.0), table_h, dark_wood)
			_bed(root, Vector3(-hw + 0.8, 0.25, hd - 1.4), 0.9, 2.0, cloth, wood)
		"barn":
			_crate(root, Vector3(-hw + 1.0, 0.5, -hd + 1.0), 1.0, wood)
			_crate(root, Vector3(-hw + 2.2, 0.5, -hd + 1.0), 1.0, wood)
			_crate(root, Vector3(-hw + 1.0, 1.5, -hd + 1.0), 0.9, wood)
			_shelf(root, Vector3(hw - 0.5, 0.9, -hd + 2.0), 2.3, h, dark_wood)
			_table(root, Vector3(hw - 2.2, table_h * 0.5, hd - 2.0), Vector2(2.0, 1.0), table_h, dark_wood)
		"shop":
			_table(root, Vector3(-hw + 1.4, table_h * 0.5, -hd + 1.6), Vector2(2.0, 1.0), table_h, dark_wood)
			_shelf(root, Vector3(hw - 0.45, 0.95, -hd + 1.6), 2.0, h, dark_wood)
			_crate(root, Vector3(-hw + 0.8, 0.5, hd - 1.6), 0.9, wood)


static func _crate(root: Node3D, pos: Vector3, s: float, mat: Material) -> void:
	_solid(root, "Crate", Vector3(s, s, s), pos, mat)


static func _table(root: Node3D, pos: Vector3, size: Vector2, table_h: float, mat: Material) -> void:
	# top + 4 patte — par collision ek hi box (simple + sasta)
	_solid(root, "TableTop", Vector3(size.x, 0.10, size.y), Vector3(pos.x, table_h - 0.05, pos.z), mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.10, table_h - 0.1, 0.10)
			box.material = mat
			leg.mesh = box
			leg.position = Vector3(pos.x + sx * (size.x * 0.5 - 0.12), (table_h - 0.1) * 0.5,
					pos.z + sz * (size.y * 0.5 - 0.12))
			root.add_child(leg)
	# ek hi collision box poore table ka (4 alag shapes ki zaroorat nahi)
	_add_collision(root, "TableBody", Vector3(size.x, table_h, size.y),
			Vector3(pos.x, table_h * 0.5, pos.z))


static func _shelf(root: Node3D, pos: Vector3, length: float, _room_h: float, mat: Material) -> void:
	var size := Vector3(0.45, 1.8, length)
	_solid(root, "Shelf", size, pos, mat)


static func _bed(root: Node3D, pos: Vector3, width: float, length: float, cloth: Material,
		wood: Material) -> void:
	_solid(root, "Bed", Vector3(width, 0.45, length), pos, wood)             # frame
	var blanket := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.04, 0.12, length * 0.72)
	box.material = cloth
	blanket.mesh = box
	blanket.position = Vector3(pos.x, 0.51, pos.z + length * 0.1)
	root.add_child(blanket)


# ---------------------------------------------------------------- helpers ----

## StaticBody3D + BoxMesh + BoxShape3D — ek solid tukda (deewar / mebel / floor).
static func _solid(root: Node3D, piece_name: String, size: Vector3, pos: Vector3,
		mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.collision_layer = 1
	body.position = pos

	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh_node.mesh = box
	body.add_child(mesh_node)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	root.add_child(body)
	return body


## Sirf collision (mesh already alag se bana hua hai — table ke patte jaise)
static func _add_collision(root: Node3D, piece_name: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.collision_layer = 1
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	root.add_child(body)


static func _mat(color: Color, metallic: float = 0.0, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
```

## 4) VERIFY checklist (phone pe)

1. **Nature dikhti hai** — pines (4–7 m), rocks (0.5–1.8 m), phool/ghaas Haveli/Haritvan/Khet/Kanak me. Grass patthar wale Marusthal/Samudra me nahi ugega. Ped se takkar hoti hai (capsule), ghaas se nahi.
2. **Buildings** — Haveli 3 chhote ghar + 1 bada, Chowk 2 dukaan + 1 bada ghar, Kanak 2 barn, baaki zones me 1-1. Total **14**. Darwaze se andar jao: andar light jalti hai, floor/ceiling hai, crate/table/shelf/bed pe takkar hoti hai.
3. **Characters** — 10 characters select karo: Rey = `Male_Suit`, Zen = `Male_Casual`, Vihaan = `Female_Casual`… Enemies random male/female model pe, **gehra laal tint** (0.55, 0.12, 0.12), 1.8 m, chalte waqt body bounce/sway.
4. **Vehicles** — Chowk me Taxi + NormalCar1, Haveli Cop, Samudra SportsCar, Kanak SUV, Marusthal NormalCar2, aur ek random jagah **SportsCar2** = **7** gaadiyaan, 4.4 m lambi, solid collision.
5. **FPS > 30** — 129 models ke GLB sirf 11.6 MB / 292k tris, map pe ek waqt me ~14 buildings + ~45 ped + ~30 patthar + 1 MultiMesh (ghaas) + 1 MultiMesh (plant). Agar FPS girta hai: `max_trees`/`max_rocks` ghatao ya `grass_count`/`plant_count` kam karo (MultiMesh already 1 draw call per variant).
6. **Fail-soft** — `assets/models/` khali kar do to bhi game chalta hai (procedural ped/ghar/gaadi), crash nahi.

### CI evidence

* Run **#55** (`39010373293`, commit `3eeb92e`) — **Success**, 1 m 9 s. Steps 7d OBJ (129 models), 7e GLB check, 8b parse gate, 8d selftest, 9 APK export — sab green. Annotation: *"Asset selftest PASS"*.
* Artifact `FreeFireFPS-apk` **27.2 MB** (`sha256:dbae70bd…39bcc`), release `latest-apk` me `FreeFireFPS.apk`.
* Local: 129/129 GLB valid, 0 errors; characters/vehicles ka muh −Z verify; 14/14 buildings ki placement algorithm ko Python replica se verify kiya (same grid/limits ke saath).

## 5) IF IT FAILS — 3 sabse zyada mumkin errors + fix

| # | Lakshan | Wajah | Fix |
|---|---|---|---|
| 1 | Ped **lete hue** / gaadi khadi (vertical) dikhti hai | `obj2glb.py` galat mode (folder naam se auto-detect hota hai) | `python3 tools/obj2glb.py assets/downloaded_obj/Nature --out-root assets/models --mode prop` (characters/vehicles ke liye `--mode character` / `--mode vehicle`). Mode code: `MODE_BY_FOLDER` in `tools/obj2glb.py`. |
| 2 | Ped/gaadi **badi ya gayab**, ghaas zameen ke andar | scale ya base y=0 | `main.gd` me `tree_count`/`rock_count` ke saath scale range (`types` array) dekho; `assets.gd` `fit_to_height()` characters ko 1.8 m karta hai, `build_vehicle_model()` 4.4 m. Nature GLB ka base `y=0` hai — agar nahi, `obj2glb.py` ka `units` report dekho. |
| 3 | Building ke andar ja nahi pa rahe / deewar me phans rahe | door gap ya collision | `building_builder.gd` me `DOOR_SIZE` (`1.2 × 2.2`, barn `3 × 3.5`), aur `_build_wall_with_door()` ka lintel check karo. Agar buildings overlap kar rahi hain to `main.gd` `BUILDING_PLAN` se ek building hatao (max 18 hai, abhi 14) ya `arena_size` badhao. |

Note: `7d` conversion fail-soft hai — fail hone pe bhi build rukega nahi, par **selftest ke count checks** (weapons ≥40 / nature ≥60 / characters ≥16 / vehicles ≥7) usi run me red kar denge, isliye chhup nahi sakta.
