extends RefCounted
##
## Assets — saare 3D models banata hai (weapons + nature), sirf primitives se
## (box / cylinder / cone / sphere). Koi texture, koi image nahi — sirf
## StandardMaterial3D + albedo_color.
##
## HYBRID SYSTEM: pehle download kiya hua CC0 model try hota hai
## (`assets/downloaded/` — GitHub Actions build ke waqt bharta hai), aur wo na
## milne pe yahi file code se model bana deti hai (procedural fallback).
## Download fail ho jaye to game phir bhi poora chalta hai — bas shape simple ho jata hai.
##
## Weapons: 5 base shapes (pistol, smg, rifle, sniper, shotgun).
## Har shape function (body_color, accent_color) leta hai, isliye 28 weapons sirf
## colour badal ke bante hain. Har model me 10 se kam mesh children hote hain.
##
## Model ki direction: barrel -Z (aage) ki taraf, Y up.
## Barrel cylinder hamesha X pe 90 degree ghuma hua hai (axis Y -> Z).
##

const Loader := preload("res://scripts/asset_loader.gd")

const HALF_PI := PI * 0.5      # 90 degree (radians me)


# =========================================================== PUBLIC API ======

## shape ka naam + do colours lo, poora weapon model (Node3D) wapas do.
static func build_weapon_model(shape: String, body_color: Color, accent_color: Color) -> Node3D:
	match shape:
		"pistol":
			return _pistol(body_color, accent_color)
		"smg":
			return _smg(body_color, accent_color)
		"sniper":
			return _sniper(body_color, accent_color)
		"shotgun":
			return _shotgun(body_color, accent_color)
		_:
			return _rifle(body_color, accent_color)   # default = rifle


# ============================================================== HELPERS ======

## Ek material banao (metal + roughness ke saath)
static func _mat(color: Color, metallic: float = 0.45, roughness: float = 0.45) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


## Box (dabba) mesh -> parent me add
static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	_prepare(node)
	parent.add_child(node)
	return node


## Cylinder (belan) mesh -> barrel, scope tube, magazine tube ke liye
static func _cylinder(parent: Node3D, radius: float, height: float, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = mat
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	_prepare(node)
	parent.add_child(node)
	return node


## Cone (shanka) mesh -> flash hider / choke ke liye.
## NOTE: Godot 4 me koi "ConeMesh" class nahi hai! Cone CylinderMesh se banta hai
## jiska ek radius 0 ho (top_radius = 0). Mota hissa peeche, nok aage (-Z).
static func _cone(parent: Node3D, radius: float, height: float, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = mat
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	_prepare(node)
	parent.add_child(node)
	return node


## Sphere (gola) mesh -> muzzle flash ke liye
static func _sphere(parent: Node3D, radius: float, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	_prepare(node)
	parent.add_child(node)
	return node


## View-model me shadow nahi chahiye (warna camera ke saamne ajeeb shadow padti hai)
static func _prepare(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## (Optional) Kisi bhi node pe simple box collision lagane ke liye.
## View-model me zaroorat nahi padti, lekin agar kabhi weapon zameen pe drop
## karana ho to seedha kaam aayega.
static func _add_collision(parent: Node3D, box_size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


## Muzzle flash: chhota peela emissive sphere, barrel ke sirre pe, default hidden.
## Naam "Muzzle" hi rehna chahiye — weapon_manager isi naam se dhoondta hai.
static func _muzzle(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.86, 0.35)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.72, 0.18)
	flash_mat.emission_energy_multiplier = 3.0
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var node := _sphere(parent, 0.055, flash_mat, pos)
	node.name = "Muzzle"
	node.visible = false
	return node


# =============================================================== MODELS ======
# mesh children (muzzle ke saath): pistol 6, smg 9, rifle 8, sniper 9, shotgun 9

## PISTOL — body, barrel, grip, magazine, sight  (6 mesh)
static func _pistol(body_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "PistolModel"
	var body := _mat(body_color, 0.6, 0.32)
	var accent := _mat(accent_color, 0.35, 0.6)

	_box(root, Vector3(0.10, 0.20, 0.55), body, Vector3(0.0, 0.0, 0.0))                  # slide/body
	_cylinder(root, 0.035, 0.30, accent, Vector3(0.0, 0.02, -0.40), Vector3(HALF_PI, 0, 0))  # barrel (90 deg X)
	_box(root, Vector3(0.09, 0.26, 0.13), accent, Vector3(0.0, -0.21, 0.15),
			Vector3(deg_to_rad(-12.0), 0, 0))                                            # grip
	_box(root, Vector3(0.07, 0.16, 0.10), body, Vector3(0.0, -0.28, 0.13))               # magazine
	_box(root, Vector3(0.05, 0.05, 0.10), accent, Vector3(0.0, 0.13, -0.18))             # rear sight
	_muzzle(root, Vector3(0.0, 0.02, -0.57))
	return root


## SMG — body, barrel, handguard, grip, magazine, stock, rail, flash hider  (9 mesh)
static func _smg(body_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SmgModel"
	var body := _mat(body_color, 0.5, 0.4)
	var accent := _mat(accent_color, 0.35, 0.6)

	_box(root, Vector3(0.11, 0.20, 0.62), body, Vector3(0.0, 0.0, 0.0))                  # body
	_cylinder(root, 0.028, 0.30, accent, Vector3(0.0, 0.03, -0.45), Vector3(HALF_PI, 0, 0))  # barrel
	_box(root, Vector3(0.10, 0.12, 0.22), accent, Vector3(0.0, -0.02, -0.30))            # handguard
	_box(root, Vector3(0.09, 0.24, 0.12), accent, Vector3(0.0, -0.20, 0.12),
			Vector3(deg_to_rad(-10.0), 0, 0))                                            # grip
	_box(root, Vector3(0.07, 0.32, 0.11), body, Vector3(0.0, -0.26, -0.02))              # magazine
	_box(root, Vector3(0.07, 0.13, 0.26), body, Vector3(0.0, -0.01, 0.42))               # stock
	_box(root, Vector3(0.06, 0.05, 0.22), accent, Vector3(0.0, 0.14, -0.10))             # top rail
	_cone(root, 0.035, 0.10, accent, Vector3(0.0, 0.03, -0.62), Vector3(-HALF_PI, 0, 0))  # flash hider
	_muzzle(root, Vector3(0.0, 0.03, -0.68))
	return root


## RIFLE — body, barrel, handguard, grip, magazine, stock, rail  (8 mesh)
static func _rifle(body_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "RifleModel"
	var body := _mat(body_color, 0.5, 0.42)
	var accent := _mat(accent_color, 0.35, 0.6)

	_box(root, Vector3(0.12, 0.22, 0.80), body, Vector3(0.0, 0.0, 0.0))                  # receiver
	_cylinder(root, 0.025, 0.55, accent, Vector3(0.0, 0.03, -0.68), Vector3(HALF_PI, 0, 0))  # barrel
	_box(root, Vector3(0.10, 0.13, 0.34), accent, Vector3(0.0, 0.0, -0.48))              # handguard
	_box(root, Vector3(0.09, 0.20, 0.11), body, Vector3(0.0, -0.17, 0.18),
			Vector3(deg_to_rad(-12.0), 0, 0))                                            # pistol grip
	_box(root, Vector3(0.08, 0.30, 0.15), accent, Vector3(0.0, -0.24, -0.06),
			Vector3(deg_to_rad(8.0), 0, 0))                                              # magazine
	_box(root, Vector3(0.09, 0.16, 0.34), body, Vector3(0.0, -0.02, 0.58))               # stock
	_box(root, Vector3(0.07, 0.07, 0.26), accent, Vector3(0.0, 0.16, -0.10))             # sight rail
	_muzzle(root, Vector3(0.0, 0.03, -0.96))
	return root


## SNIPER — body, barrel, scope tube, 2 scope mounts, grip, magazine, stock  (9 mesh)
static func _sniper(body_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SniperModel"
	var body := _mat(body_color, 0.45, 0.45)
	var accent := _mat(accent_color, 0.6, 0.3)

	_box(root, Vector3(0.12, 0.20, 1.00), body, Vector3(0.0, 0.0, 0.0))                  # body
	_cylinder(root, 0.022, 0.80, accent, Vector3(0.0, 0.03, -0.92), Vector3(HALF_PI, 0, 0))  # long barrel
	_cylinder(root, 0.055, 0.44, accent, Vector3(0.0, 0.21, -0.10), Vector3(HALF_PI, 0, 0))  # scope tube
	_box(root, Vector3(0.04, 0.09, 0.06), body, Vector3(0.0, 0.13, -0.26))               # scope mount (front)
	_box(root, Vector3(0.04, 0.09, 0.06), body, Vector3(0.0, 0.13, 0.06))                # scope mount (rear)
	_box(root, Vector3(0.07, 0.18, 0.12), accent, Vector3(0.0, -0.18, -0.05))            # magazine
	_box(root, Vector3(0.09, 0.20, 0.11), body, Vector3(0.0, -0.17, 0.16),
			Vector3(deg_to_rad(-12.0), 0, 0))                                            # grip
	_box(root, Vector3(0.10, 0.18, 0.42), body, Vector3(0.0, -0.02, 0.62))               # stock
	_muzzle(root, Vector3(0.0, 0.03, -1.32))
	return root


## SHOTGUN — body, barrel, magazine tube, pump, grip, stock, receiver  (9 mesh)
static func _shotgun(body_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ShotgunModel"
	var body := _mat(body_color, 0.5, 0.42)
	var accent := _mat(accent_color, 0.5, 0.4)

	_box(root, Vector3(0.13, 0.22, 0.80), body, Vector3(0.0, 0.0, 0.0))                  # receiver
	_cylinder(root, 0.032, 0.66, accent, Vector3(0.0, 0.07, -0.66), Vector3(HALF_PI, 0, 0))  # barrel
	_cylinder(root, 0.026, 0.54, body, Vector3(0.0, -0.03, -0.60), Vector3(HALF_PI, 0, 0))   # magazine tube
	_box(root, Vector3(0.11, 0.13, 0.24), accent, Vector3(0.0, -0.01, -0.42))            # pump / forend
	_box(root, Vector3(0.09, 0.20, 0.11), body, Vector3(0.0, -0.17, 0.16),
			Vector3(deg_to_rad(-12.0), 0, 0))                                            # grip
	_box(root, Vector3(0.10, 0.17, 0.36), body, Vector3(0.0, -0.03, 0.54))               # stock
	_box(root, Vector3(0.15, 0.09, 0.26), accent, Vector3(0.0, 0.14, 0.02))              # receiver top
	_cone(root, 0.038, 0.10, accent, Vector3(0.0, 0.07, -1.03), Vector3(-HALF_PI, 0, 0))     # choke
	_muzzle(root, Vector3(0.0, 0.07, -1.09))
	return root


# ============================================================== NATURE =======
#
# Phase 1 — trees / rocks / bushes / grass.
#
# Har function ka flow ek hi hai:
#   1) GitHub Actions ne jo CC0 model download kiya hai, wo try karo (asset_loader.gd)
#   2) Na mila to yahin code se simple model bana do (procedural fallback)
# Isliye ye functions akele me bhi kaam karte hain aur download ke saath bhi.
#
# `variant` = kaunsa roop (0,1,2...). Har kind ke liye NICHE wali list me naam hain —
# wahi naam asset_loader.gd dhoondhta hai, aur wahi ginti procedural fallback bhi samajhta hai.
#

## kind -> downloaded file ke naam (fuzzy match, extension ke bina).
## Ye 14 files .github/workflows/build-apk.yml ke step "7c" me download hoti hain.
const NATURE_MODELS := {
	"tree": ["tree_default", "tree_detailed", "tree_pineTallA", "tree_pineRoundC", "tree_fat"],
	"rock": ["rock_largeA", "rock_largeC", "rock_smallB", "rock_smallFlatA"],
	"bush": ["plant_bushDetailed", "plant_bush", "plant_bushSmall"],
	"grass": ["grass", "grass_large"],
}

## Fallback ke colours (ye har variant ke liye thoda alag hote hain)
const _TREE_TRUNK := Color(0.32, 0.21, 0.12)
const _TREE_LEAF := [Color(0.20, 0.42, 0.19), Color(0.24, 0.48, 0.22), Color(0.16, 0.36, 0.17)]
const _ROCK_COLOR := [Color(0.46, 0.47, 0.49), Color(0.40, 0.41, 0.44), Color(0.52, 0.51, 0.48)]
const _BUSH_COLOR := [Color(0.22, 0.40, 0.20), Color(0.26, 0.45, 0.23), Color(0.19, 0.35, 0.18)]
const _GRASS_COLOR := Color(0.30, 0.52, 0.24)


## TREE — ped. Pehle downloaded model, warna trunk + patte (code se).
static func tree(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	var downloaded := _try_downloaded("tree", variant, scale_f, "Tree", true)
	if downloaded != null:
		return downloaded

	# ---------- procedural fallback ----------
	var root := Node3D.new()
	root.name = "Tree"
	var tone: Color = _TREE_LEAF[absi(variant) % _TREE_LEAF.size()]
	var trunk_mat := _mat(_TREE_TRUNK, 0.0, 0.9)
	var leaf_mat := _mat(tone, 0.0, 0.85)

	# trunk (cylinder default Y axis pe khada hota hai, isliye rotation nahi chahiye)
	_cylinder(root, 0.16, 1.7, trunk_mat, Vector3(0.0, 0.85, 0.0), Vector3.ZERO)
	# patte: do "cone" (CylinderMesh jiska top_radius 0 hai) ek ke upar ek
	_cone(root, 1.05, 1.8, leaf_mat, Vector3(0.0, 2.0, 0.0), Vector3.ZERO)
	_cone(root, 0.75, 1.5, leaf_mat, Vector3(0.0, 2.9, 0.0), Vector3.ZERO)

	root.scale = Vector3.ONE * scale_f
	_ensure_collision(root, "tree")
	return root


## ROCK — patthar.
static func rock(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	var downloaded := _try_downloaded("rock", variant, scale_f, "Rock", true)
	if downloaded != null:
		return downloaded

	# ---------- procedural fallback ----------
	var root := Node3D.new()
	root.name = "Rock"
	var tone: Color = _ROCK_COLOR[absi(variant) % _ROCK_COLOR.size()]
	var rock_mat := _mat(tone, 0.0, 0.95)

	# main dhela: sphere ko dabaya hua (y pe 0.6)
	var main_sphere := _sphere(root, 0.55, rock_mat, Vector3(0.0, 0.33, 0.0))
	main_sphere.scale = Vector3(1.0, 0.6, 1.0)
	# ek chhota dhela saath me
	var side_sphere := _sphere(root, 0.3, rock_mat, Vector3(0.45, 0.18, 0.2))
	side_sphere.scale = Vector3(1.0, 0.6, 1.0)

	root.scale = Vector3.ONE * scale_f
	_ensure_collision(root, "rock")
	return root


## BUSH — chhota jhaadi.
static func bush(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	var downloaded := _try_downloaded("bush", variant, scale_f, "Bush", true)
	if downloaded != null:
		return downloaded

	# ---------- procedural fallback ----------
	var root := Node3D.new()
	root.name = "Bush"
	var tone: Color = _BUSH_COLOR[absi(variant) % _BUSH_COLOR.size()]
	var mat := _mat(tone, 0.0, 0.9)

	_sphere(root, 0.42, mat, Vector3(0.0, 0.36, 0.0))
	_sphere(root, 0.30, mat, Vector3(0.34, 0.26, 0.14))
	_sphere(root, 0.28, mat, Vector3(-0.26, 0.24, -0.22))

	root.scale = Vector3.ONE * scale_f
	_ensure_collision(root, "bush")
	return root


## GRASS TUFT — ghaas ke guchhe. NOTE: isme collision JAAN-BOOJH kar nahi hai
## (decor hai — player iske aar-paar chalta rehta hai, aur 25+ tufts pe physics bachega).
static func grass_tuft(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	var downloaded := _try_downloaded("grass", variant, scale_f, "GrassTuft", false)
	if downloaded != null:
		return downloaded

	# ---------- procedural fallback ----------
	var root := Node3D.new()
	root.name = "GrassTuft"
	var mat := _mat(_GRASS_COLOR, 0.0, 0.9)

	# teen patte (cone), har ek thoda alag jhuka hua
	_cone(root, 0.055, 0.45, mat, Vector3(0.0, 0.22, 0.0), Vector3(-0.12, 0.0, 0.0))
	_cone(root, 0.05, 0.38, mat, Vector3(0.10, 0.19, 0.06), Vector3(0.18, 0.0, 0.25))
	_cone(root, 0.045, 0.32, mat, Vector3(-0.09, 0.16, -0.05), Vector3(0.15, 0.0, -0.28))

	root.scale = Vector3.ONE * scale_f
	return root


# ---------------------------------------------------- hybrid load / fallback --

## Downloaded model try karo -> Node3D (collision ke saath) ya null.
## Null mila to caller apna procedural model bana leta hai.
static func _try_downloaded(kind: String, variant: int, scale_f: float, node_name: String,
		with_collision: bool) -> Node3D:
	var names: Array = NATURE_MODELS.get(kind, [])
	if names.is_empty():
		return null
	var fragment: String = str(names[absi(variant) % names.size()])

	var scene := Loader.load_model(fragment, "nature")
	if scene == null:
		return null      # download nahi hua -> fallback (bilkul normal baat hai)

	var inst := scene.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var model := inst as Node3D

	model.scale = Vector3.ONE * scale_f
	# NOTE: meshes ke shadows default ON hote hain (MeshInstance3D), kuch set karne ki zaroorat nahi.

	var root := Node3D.new()
	root.name = node_name
	root.add_child(model)

	# Model ka origin (0,0,0) base pe ho ya beech me — hum usko zameen pe bitha dete hain:
	# sabse neeche wala point theek y = 0 par aa jata hai.
	var box := _visual_aabb(model)
	model.position.y -= box.position.y

	if with_collision:
		_ensure_collision(root, kind)
	return root


# ------------------------------------------------------------- collision -----

## Model ke aas-paas ek StaticBody3D + BoxShape3D laga do (takkar ke liye).
## Box ka size model ke AABB se apne aap nikalta hai — koi hardcoded size nahi.
##
## DHYAAN DO: `get_aabb()` sirf GeometryInstance3D (MeshInstance3D etc.) pe hota
## hai — Node3D pe NAHI. Isliye `_visual_aabb()` mesh children ko dekhta hai.
## "grass" me collision nahi lagta (decor hai).
static func _ensure_collision(node: Node3D, kind: String, aabb: AABB = AABB()) -> StaticBody3D:
	if kind == "grass":
		return null

	var box := aabb
	if box.size == Vector3.ZERO:
		box = _visual_aabb(node)
	if box.size == Vector3.ZERO:
		return null      # kuch mesh hi nahi mila

	# kind ke hisaab se kitna mota box (ped ke patte halke hote hain -> patla box)
	var radius_scale := 1.0
	var height_scale := 1.0
	match kind:
		"tree":
			radius_scale = 0.55
			height_scale = 0.85
		"bush":
			radius_scale = 0.70
			height_scale = 0.90
		_:
			radius_scale = 0.85     # rock / default
			height_scale = 0.85

	var size := Vector3(
		maxf(box.size.x * radius_scale, 0.30),
		maxf(box.size.y * height_scale, 0.30),
		maxf(box.size.z * radius_scale, 0.30))

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	# Ground-drop ke baad box ka neeche wala point y = 0 par hai, isliye center = height/2
	body.position = Vector3(
		box.position.x + box.size.x * 0.5,
		size.y * 0.5,
		box.position.z + box.size.z * 0.5)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	node.add_child(body)
	return body


## Node ke saare mesh children ka mila-jula AABB — node ke apne local space me.
static func _visual_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var has_any := false

	for child in node.get_children():
		var child_box := AABB()
		var found := false

		if child is GeometryInstance3D:
			# MeshInstance3D / wahi class jisme get_aabb() hai
			child_box = (child as GeometryInstance3D).get_aabb()
			found = child_box.size != Vector3.ZERO
		elif child is Node3D:
			child_box = _visual_aabb(child as Node3D)
			found = child_box.size != Vector3.ZERO
		if not found:
			continue

		# child ke transform (position/rotation/scale) ke hisaab se box ko ghumao-phirao.
		# 8 corners nikal ke naya box banate hain -> rotation ke saath bhi theek rehta hai.
		var xform: Transform3D = (child as Node3D).transform
		var low := Vector3.INF
		var high := -Vector3.INF
		for i in 8:
			# 8 corners = box ke har combination ko jodna (bit 0 = x, bit 1 = y, bit 2 = z)
			var offset := Vector3.ZERO
			if (i & 1) != 0:
				offset.x = child_box.size.x
			if (i & 2) != 0:
				offset.y = child_box.size.y
			if (i & 4) != 0:
				offset.z = child_box.size.z
			var world_corner: Vector3 = xform * (child_box.position + offset)
			# NOTE: Vector3.min()/max() sirf Godot 4.3+ me hain — 4.2 ke liye minf/maxf
			low = Vector3(minf(low.x, world_corner.x), minf(low.y, world_corner.y), minf(low.z, world_corner.z))
			high = Vector3(maxf(high.x, world_corner.x), maxf(high.y, world_corner.y), maxf(high.z, world_corner.z))
		var box_in_parent := AABB(low, high - low)

		result = box_in_parent if not has_any else result.merge(box_in_parent)
		has_any = true

	return result
