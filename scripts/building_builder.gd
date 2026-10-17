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
