extends RefCounted
##
## Assets — weapon models banata hai, sirf primitives se (box / cylinder / cone / sphere).
## Koi texture, koi image, koi download nahi — sirf StandardMaterial3D + albedo_color.
##
## 5 base shapes: pistol, smg, rifle, sniper, shotgun.
## Har shape function (body_color, accent_color) leta hai, isliye 28 weapons sirf
## colour badal ke bante hain. Har model me 10 se kam mesh children hote hain.
##
## Model ki direction: barrel -Z (aage) ki taraf, Y up.
## Barrel cylinder hamesha X pe 90 degree ghuma hua hai (axis Y -> Z).
##

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
