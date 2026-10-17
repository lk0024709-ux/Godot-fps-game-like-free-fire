extends RefCounted
##
## Assets — saare 3D models banata hai (weapons + nature), sirf primitives se
## (box / cylinder / cone / sphere). Koi texture, koi image nahi — sirf
## StandardMaterial3D + albedo_color.
##
## HYBRID SYSTEM: pehle download kiya hua CC0 model try hota hai
## (`assets/downloaded/` — GitHub Actions build ke waqt FBX -> GLB convert karta hai,
## dekho tools/fbx2glb.py), aur wo na milne pe yahi file code se model bana deti hai
## (procedural fallback). Download ya conversion fail ho jaye to game phir bhi poora
## chalta hai — bas shape simple ho jata hai.
##
## Yahan se ye cheezein banti hain:
##   build_weapon_model()   -> 28 weapons ke view models (downloaded + procedural)
##   tree()/rock()/bush()/grass_tuft()/plant() -> nature props (downloaded + procedural)
##   build_character_model()-> player/enemy ka humanoid (downloaded + procedural)
##   build_vehicle_model()  -> gaadi (Phase F me physics aayegi, abhi static decoration)
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

## Downloaded weapon ka target size (metres, -Z lambai). Poore game me weapon ka size
## yahi se tay hota hai (per-gun `scale` `weapon_data.gd` me hai). In numbers ko chhuna
## ho to yahi jagah hai.
const WEAPON_TARGET_LENGTH := {
	"pistol": 0.30,
	"smg": 0.60,
	"rifle": 1.20,
	"sniper": 1.40,
	"shotgun": 1.10,
}

## Character ki height (metres) — player aur enemy dono ke liye
const CHARACTER_HEIGHT := 1.8

## Vehicle ki lambai (metres)
const VEHICLE_LENGTH := 4.4


# =========================================================== PUBLIC API ======

## Weapon ka poora view model (Node3D) — PEHLE downloaded CC0 model, warna procedural.
##
##   shape        : "pistol" / "smg" / "rifle" / "sniper" / "shotgun" (fallback + size)
##   body_color   : skin ka main rang (surface 0)
##   accent_color : doosra rang (baaki surfaces)
##   model_name   : downloaded model ka naam jaise "ar_5" (khali = procedural)
##   scale_hint   : us weapon ka size multiplier (jaise Bizon 1.3x, Skorpion 0.7x)
##   muzzle_hint  : -1 = AABB ke saamne wala sirra use karo, warna 0..1 = lambai ka hissa
##
## Diya gaya model mil gaya to:
##   - material override (body/accent), shadows off, size normalise, muzzle node add
## Mil nahi to yahin procedural shape banta hai (game kabhi rukta nahi).
static func build_weapon_model(shape: String, body_color: Color, accent_color: Color,
		model_name: String = "", scale_hint: float = 1.0, muzzle_hint: float = -1.0) -> Node3D:
	if not model_name.is_empty():
		var inst := _load_weapon_instance(model_name)
		if inst != null:
			var prepared := _prepare_weapon_model(inst, shape, body_color,
					accent_color, scale_hint, muzzle_hint)
			if prepared != null:
				return prepared
	# ---------- procedural fallback (downloaded model nahi mila) ----------
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


# ==================================================== DOWNLOADED MODEL PREP ==
# Neeche wale functions sirf downloaded (CC0) models pe kaam karte hain.
# Sab fail-soft hain: kuch bhi ajeeb mile to null/khali wapas, game chalta rehta hai.

## Downloaded model ka node: pehle PackedScene (.glb/.gltf — CI ka converted output),
## warna Mesh (.obj, agar Godot ne khud import kar liya ho). Kuch na mile to null
## (caller procedural shape bana lega — game kabhi rukta nahi).
static func _load_weapon_instance(model_name: String) -> Node3D:
	var scene := Loader.load_model(model_name, "weapons")
	if scene != null:
		var node := scene.instantiate()
		if node is Node3D:
			return node as Node3D
		node.queue_free()
	var holder := Loader.load_mesh_node(model_name, "weapons")
	if holder != null:
		return holder
	return null


## Downloaded weapon ko view-model banane ke liye taiyaar karo.
## Null wapas aaya to caller procedural model bana lega.
static func _prepare_weapon_model(inst: Node3D, shape: String, body_color: Color,
		accent_color: Color, scale_hint: float, muzzle_hint: float) -> Node3D:
	# Mesh hi nahi hai (khali scene) -> kuch nahi kar sakte
	if _mesh_nodes(inst, 0, []).is_empty():
		inst.queue_free()
		return null

	_apply_weapon_skin(inst, body_color, accent_color)
	_strip_shadows(inst)

	var box := _visual_aabb(inst)
	if box.size == Vector3.ZERO:
		inst.queue_free()
		return null

	# ---- barrel -Z ki taraf hona chahiye (muzzle node usi taraf lagta hai) ----
	if _normalize_orientation(inst, box):
		box = _visual_aabb(inst)

	# ---- size normalise: model ki lambai (Z) ko target lambai bana do ----
	var factor := _normalize_scale(box, shape, scale_hint)

	# ---- origin: X/Z center, aur ubhaar (Y) ko hataya — holder ke origin pe gun ka beech ----
	# Z pe thoda AAGE (camera se door) khiska dete hain: warna poori gun ka aadha hissa
	# camera ke peeche chala jata hai aur stock camera me ghus jata hai (near plane 0.05).
	var forward_shift := 0.12 * _weapon_target_length(shape, scale_hint)
	var offset := Vector3(
		-(box.position.x + box.size.x * 0.5) * factor,
		-(box.position.y + box.size.y * 0.5) * factor,
		-(box.position.z + box.size.z * 0.5) * factor - forward_shift)

	var root := Node3D.new()
	root.name = "WeaponModel"
	root.add_child(inst)
	inst.scale = Vector3.ONE * factor
	inst.position = offset

	# ---- muzzle node (weapon_manager isko "Muzzle" naam se dhundhta hai) ----
	var muzzle := _add_muzzle_node(root, inst, box, factor, muzzle_hint)
	if muzzle != null:
		root.set_meta("muzzle", muzzle)

	return root


## Downloaded character (player/enemy) ka model — 1.8m, pair zameen pe, X/Z center.
## `tint` ka alpha > 0 ho to poore model ka rang usme mila diya jata hai (enemy = dark red).
static func build_character_model(model_name: String, body_color: Color, accent_color: Color,
		tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var scene := Loader.load_model(model_name, "characters")
	if scene == null:
		return null
	var inst := scene.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var model := inst as Node3D
	if _mesh_nodes(model, 0, []).is_empty():
		model.queue_free()
		return null

	_apply_character_skin(model, body_color, accent_color, tint)

	var root := Node3D.new()
	root.name = "CharacterModel"
	root.add_child(model)
	fit_to_height(model, CHARACTER_HEIGHT)     # 1.8m + pair y=0 + X/Z center
	return root


## Kisi bhi prop/model ka rang halka sa zone ke rang me mila do (procedural fallback
## shapes pe kaam karta hai — downloaded models apne asli CC0 rang rakhte hain).
## `amount` = kitna milana hai (0 = kuch nahi, 1 = poora zone ka rang).
static func tint_grey(node: Node3D, zone_color: Color, amount: float = 0.55) -> void:
	for mesh_node in _mesh_nodes(node, 0, []):
		var mat: Material = mesh_node.material_override
		if mat is StandardMaterial3D:
			var std := mat.duplicate() as StandardMaterial3D
			std.albedo_color = std.albedo_color.lerp(zone_color, clampf(amount, 0.0, 1.0))
			mesh_node.material_override = std
			continue
		var mesh: Mesh = mesh_node.mesh
		if mesh == null:
			continue
		for i in maxi(1, mesh.get_surface_count()):
			var surface_mat: Material = mesh.surface_get_material(i)
			if surface_mat is StandardMaterial3D:
				var copy := (surface_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.albedo_color = copy.albedo_color.lerp(zone_color, clampf(amount, 0.0, 1.0))
				mesh_node.set_surface_override_material(i, copy)


## Node ke saare collision shapes band karo (vehicle_collision = false ke liye)
static func disable_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		elif child is Node:
			disable_collision(child)


## Downloaded vehicle — lambai ~4.4m, base y=0, X/Z center. StaticBody3D wapas deta hai
## (apne collision ke saath), taaki main.gd seedha position de kar add kar sake.
## Model na mila to null (caller procedural gaadi bana sakta hai).
static func build_vehicle_model(model_name: String) -> StaticBody3D:
	var scene := Loader.load_model(model_name, "vehicles")
	if scene == null:
		return null
	var inst := scene.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var model := inst as Node3D
	if _mesh_nodes(model, 0, []).is_empty():
		model.queue_free()
		return null

	var box := _visual_aabb(model)
	if box.size == Vector3.ZERO:
		model.queue_free()
		return null

	var length: float = maxf(box.size.z, 0.0001)
	var factor := VEHICLE_LENGTH / length
	model.scale = Vector3.ONE * factor
	_strip_shadows(model)          # gaadi ki shadow dekhne layak nahi lagti bade scene me

	var body := StaticBody3D.new()
	body.name = "Vehicle"
	body.collision_layer = 1
	body.add_child(model)

	# ---- collision box: model ke AABB ke hisaab se, base y=0 pe ----
	var size := Vector3(box.size.x * factor, box.size.y * factor, box.size.z * factor)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x * 0.92, 0.5), maxf(size.y * 0.9, 0.5), maxf(size.z * 0.96, 0.5))
	col.shape = shape
	col.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
	body.add_child(col)

	# model ka base y=0 pe aur X/Z center
	model.position = Vector3(
		-(box.position.x + box.size.x * 0.5) * factor,
		-box.position.y * factor,
		-(box.position.z + box.size.z * 0.5) * factor)
	return body


## Procedural humanoid — downloaded character model na mile to enemy.gd isko use karta hai.
## (Capsule + sphere + cylinders se banta hai, lekin node ke naam wahi hain jo downloaded
##  model me hain — leg_l, leg_r, arm_l, arm_r — isliye sine-wave animation phir bhi chalti hai.)
static func fallback_character(body_color: Color, accent_color: Color,
		tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var body := body_color
	var accent := accent_color
	if tint.a > 0.0:
		body = body.lerp(tint, 0.8)
		accent = accent.lerp(tint, 0.8)
	var cloth := _mat(body, 0.0, 0.9)
	var skin := _mat(body.lerp(Color(0.85, 0.68, 0.55), 0.7), 0.0, 0.85)
	var trouser := _mat(accent, 0.0, 0.9)

	var root := Node3D.new()
	root.name = "CharacterModel"

	# dhadh (torso) + sar
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.24
	torso_mesh.height = 0.86
	torso_mesh.material = cloth
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 1.20, 0.0)
	root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.30
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.62, 0.0)
	root.add_child(head)

	# haath-pair: har limb ek Node3D pivot hai (kandha / kamar), uske andar danda
	for spec in [["arm_l", 1.0, 1.42, 0.28, 0.075, 0.55, true],
			["arm_r", -1.0, 1.42, 0.28, 0.075, 0.55, true],
			["leg_l", 1.0, 0.88, 0.12, 0.115, 0.80, false],
			["leg_r", -1.0, 0.88, 0.12, 0.115, 0.80, false]]:
		var pivot := Node3D.new()
		pivot.name = String(spec[0])
		pivot.position = Vector3(float(spec[1]) * float(spec[3]), float(spec[2]), 0.0)
		root.add_child(pivot)

		var limb := MeshInstance3D.new()
		var limb_mesh := CapsuleMesh.new()
		limb_mesh.radius = float(spec[4])
		limb_mesh.height = float(spec[5])
		limb_mesh.material = skin if bool(spec[6]) else trouser
		limb.mesh = limb_mesh
		limb.position = Vector3(0.0, -float(spec[5]) * 0.5, 0.0)
		pivot.add_child(limb)

	return root


## Us shape ki target lambai (metres) — `weapon_data.gd` ka per-gun `scale` bhi lagta hai.
static func _weapon_target_length(shape: String, scale_hint: float) -> float:
	return float(WEAPON_TARGET_LENGTH.get(shape, 1.0)) * maxf(0.05, scale_hint)


## Downloaded model ki asli lambai dekh kar scale factor nikalo.
##   * target: pistol 0.30 m, smg 0.60 m, rifle 1.20 m, sniper 1.40 m, shotgun 1.10 m
##     (per-weapon `scale` multiplier `weapon_data.gd` se aata hai — Bizon 1.3x etc.)
##   * spec ke safety rules: model 0.3 m se chhota ho to 3x tak, 1.5 m se bada ho to
##     aadha (aakhri hadd) — taaki koi ajeeb file poore screen ko na bhar de.
static func _normalize_scale(box: AABB, shape: String, scale_hint: float) -> float:
	var length: float = maxf(box.size.z, 0.0001)
	var factor := _weapon_target_length(shape, scale_hint) / length
	if length < 0.3:
		factor = maxf(factor, 3.0)
	elif length > 1.5:
		factor = minf(factor, 0.5)
	return factor


## Barrel -Z pe hona chahiye. Har gun ka lambai wala axis Z hai (CI ke converter
## tools/obj2glb.py + tools/fbx2glb.py yahi likhte hain), lekin koi haath se daala
## gaya model ulta aa sakta hai:
##   * lambai ka axis X/Y hai -> usko Z pe ghumao (safe, isse kuch bigadta nahi)
##   * 180 degree ka auto-flip jaan-boojh kar NAHI karte
## Returns: true agar model ghumana pada (tab caller AABB dobara nikaale).
static func _normalize_orientation(inst: Node3D, box: AABB) -> bool:
	var longest := "z"
	if box.size.x > box.size.z and box.size.x >= box.size.y:
		longest = "x"
	elif box.size.y > box.size.z and box.size.y > box.size.x:
		longest = "y"

	if longest == "z":
		# lambai theek hai; sirf tab warning jab shape shak wala ho (lambai ~ height)
		if box.size.z < box.size.y * 1.1:
			push_warning("WeaponModel: '%s' ki lambai (%.2f) aur ubhaar (%.2f) lagbhag barabar hain — barrel -Z hai ya nahi, ek baar dekh lo"
					% [inst.name, box.size.z, box.size.y])
		return false

	inst.rotation.y += HALF_PI if longest == "x" else 0.0
	inst.rotation.x -= HALF_PI if longest == "y" else 0.0
	push_warning("WeaponModel: '%s' ka lambai axis %s tha -> Z pe ghumaya (barrel -Z maan liya, manual review)"
			% [inst.name, longest.to_upper()])
	return true


## Weapon ke model ke rang: surface 0 = body, baaki sab = accent.
## (Single-surface models pe poora body colour lagta hai.) Spec: metallic 0.6, roughness 0.4
static func _apply_weapon_skin(node: Node3D, body_color: Color, accent_color: Color) -> void:
	var body_mat := _mat(body_color, 0.6, 0.4)
	var accent_mat := _mat(accent_color, 0.6, 0.4)
	for mesh_node in _mesh_nodes(node, 0, []):
		var mesh: Mesh = mesh_node.mesh
		var surfaces := 1
		if mesh != null:
			surfaces = maxi(1, mesh.get_surface_count())
		if surfaces <= 1:
			mesh_node.material_override = body_mat
		else:
			for i in surfaces:
				mesh_node.set_surface_override_material(i, body_mat if i == 0 else accent_mat)


## Character ke kapdon ke rang (+ optional tint). Surface 0 = body, baaki = accent.
static func _apply_character_skin(node: Node3D, body_color: Color, accent_color: Color,
		tint: Color = Color(0, 0, 0, 0)) -> void:
	var body := body_color
	var accent := accent_color
	if tint.a > 0.0:
		body = body.lerp(tint, 0.8)      # enemy: gehra laal
		accent = accent.lerp(tint, 0.8)
	var body_mat := _mat(body, 0.0, 0.85)
	var accent_mat := _mat(accent, 0.0, 0.85)
	for mesh_node in _mesh_nodes(node, 0, []):
		var mesh: Mesh = mesh_node.mesh
		var surfaces := 1
		if mesh != null:
			surfaces = maxi(1, mesh.get_surface_count())
		if surfaces <= 1:
			mesh_node.material_override = body_mat
		else:
			for i in surfaces:
				mesh_node.set_surface_override_material(i, body_mat if i == 0 else accent_mat)


## Saare MeshInstance3D children ki list (recursive) — enemy.gd/HUD/debug ke liye public
static func collect_meshes(node: Node) -> Array:
	return _mesh_nodes(node, 0, [])


## Saare MeshInstance3D children (recursive) ki list
static func _mesh_nodes(node: Node, depth: int, out: Array) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		if child is Node3D:
			_mesh_nodes(child, depth + 1, out)
	return out


## Mesh children ki shadows band karo (view models/guns ke liye).
## GI bhi band — mobile pe bacha hua kaam achha hai.
static func _strip_shadows(node: Node) -> void:
	for mesh_node in _mesh_nodes(node, 0, []):
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Weapon ke aage (barrel ke sirre) pe chhota emissive sphere — naam "Muzzle", hidden.
## weapon_manager isi ko dhundh kar muzzle flash on/off karta hai.
static func _add_muzzle_node(root: Node3D, inst: Node3D, box: AABB, factor: float,
		muzzle_hint: float) -> Node3D:
	var front_z: float = box.position.z
	if muzzle_hint >= 0.0:
		front_z = box.position.z + box.size.z * clampf(muzzle_hint, 0.0, 1.0)

	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.86, 0.35)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.72, 0.18)
	flash_mat.emission_energy_multiplier = 3.0
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = flash_mat
	node.mesh = mesh
	node.name = "Muzzle"
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# flash ko root ke space me rakho (inst scaled hai, isliye factor se guna)
	var tip := Vector3(
		box.position.x + box.size.x * 0.5,
		box.position.y + box.size.y * 0.5,
		front_z)
	node.position = inst.position + tip * factor
	root.add_child(node)
	return node


## Node ko di gayi height pe fit karo: scale + pair y=0 + X/Z center.
## (Downloaded characters already 1.8m hote hain — ye safety net hai.)
static func fit_to_height(node: Node3D, target_height: float) -> float:
	var box := _visual_aabb(node)
	if box.size == Vector3.ZERO or box.size.y < 0.0001:
		return 1.0
	var factor := target_height / box.size.y
	node.scale = Vector3.ONE * factor
	# mesh ka base y=0 pe aur X/Z center pe
	node.position = Vector3(
		-(box.position.x + box.size.x * 0.5) * factor,
		-box.position.y * factor,
		-(box.position.z + box.size.z * 0.5) * factor)
	return factor


## Node ke saare mesh children ka mila-jula AABB (public wrapper — tests/HUD ke liye)
static func visual_aabb(node: Node3D) -> AABB:
	return _visual_aabb(node)


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

## kind -> downloaded model ke naam (assets/downloaded/nature/ folder se).
## Naam asset_loader.gd se hote hain: "pine_2" -> PineTree_2.glb, "grass_large_2" ->
## Grass_Large_Extruded.glb (aliases asset_loader.gd ke SPECIAL_ALIASES me hain).
## Ye pool ginti bhi tay karta hai: bade pool = zyada variety.
const NATURE_MODELS := {
	"tree": ["pine_1", "pine_2", "pine_3", "pine_4", "pine_5"],
	"rock": ["rock_1", "rock_2", "rock_3", "rock_4", "rock_5"],
	"bush": ["plant_1", "plant_2", "plant_flowers"],
	"plant": ["plant_1", "plant_2", "plant_flowers"],
	"grass": ["grass_small", "grass_large", "grass_large_2"],
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


## PLANT — phool/paudhe (bush wale meshes ka door ka roop, thoda rangeen).
## Collision nahi (decor hai), lekin grass se bada dikhta hai.
static func plant(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	var downloaded := _try_downloaded("plant", variant, scale_f, "Plant", false)
	if downloaded != null:
		return downloaded

	# ---------- procedural fallback: chhota jhaadi + rangeen phool ----------
	var root := Node3D.new()
	root.name = "Plant"
	var tone: Color = _BUSH_COLOR[absi(variant) % _BUSH_COLOR.size()]
	var leaf_mat := _mat(tone, 0.0, 0.9)
	var flower_mat := _mat(Color(0.80, 0.45, 0.62), 0.0, 0.8)

	_sphere(root, 0.34, leaf_mat, Vector3(0.0, 0.30, 0.0))
	_sphere(root, 0.24, leaf_mat, Vector3(0.26, 0.22, 0.10))
	_cylinder(root, 0.02, 0.34, _mat(Color(0.26, 0.40, 0.20), 0.0, 0.9),
			Vector3(0.0, 0.55, 0.0), Vector3.ZERO)
	_sphere(root, 0.10, flower_mat, Vector3(0.0, 0.72, 0.0))
	_sphere(root, 0.08, flower_mat, Vector3(0.14, 0.64, 0.06))

	root.scale = Vector3.ONE * scale_f
	return root


## GRASS TUFT — ghaas ke guchhe. NOTE: isme collision JAAN-BOOJH kar nahi hai
## (decor hai — player iske aar-paar chalta rehta hai, aur 25+ tufts pe physics bachega).
static func grass_tuft(scale_f: float = 1.0, variant: int = 0) -> Node3D:
	# ghaas ka model flat hai — 90/180 degree ghumane se wahi guchha alag dikhta hai
	var downloaded := _try_downloaded("grass", variant, scale_f, "GrassTuft", false,
			(90.0 + 90.0 * float(absi(variant) % 3)), false)
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


## Ek nature model ka single Mesh (MultiMeshInstance3D ke liye).
## MultiMesh ek hi Mesh ka instance baar-baar draw karta hai — isliye model me
## **ek hi mesh node** hona chahiye (hamara OBJ->GLB aisa hi banata hai).
## Na mile / zyada mesh nodes hon to null (caller alag-alag nodes laga dega).
static func nature_mesh(kind: String, variant: int) -> Mesh:
	var names: Array = NATURE_MODELS.get(kind, [])
	if names.is_empty():
		return null
	var scene := Loader.load_model(str(names[absi(variant) % names.size()]), "nature")
	if scene == null:
		return null
	var inst := scene.instantiate()
	if not (inst is Node3D):
		inst.free()
		return null
	var meshes := _mesh_nodes(inst, 0, [])
	if meshes.size() != 1:
		inst.free()
		return null
	var node: MeshInstance3D = meshes[0]
	# converter geometry ko node me hi bake karta hai; agar transform bacha hua ho to
	# MultiMesh galat jagah lagega -> aise model ko MultiMesh me na daalo.
	if not node.transform.is_equal_approx(Transform3D.IDENTITY):
		inst.free()
		return null
	var mesh: Mesh = node.mesh
	inst.free()
	return mesh


## Kisi node ke saare visual children (MeshInstance3D, Label3D, ...) ka render layer
## set karo. Player ka body layer 2 pe jata hai aur uske apne camera ka cull_mask
## layer 2 ko nahi dekhta (FPS me apna body na dikhe).
static func set_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for child in node.get_children():
		set_render_layer(child, layer)


# ---------------------------------------------------- hybrid load / fallback --

## Downloaded model try karo -> Node3D (collision ke saath) ya null.
## Null mila to caller apna procedural model bana leta hai.
##
## `variant` se pool me se model chuna jata hai (pool se bahar nikal jaye to wrap ho jata hai),
## `yaw_deg` se model ko ghumaya jata hai (0 = seedha, 180 = ulta — plant ke liye kaam aata hai),
## `with_shadow` se mesh ki shadow band ho sakti hai (grass ke liye — mobile pe mehnga hai).
static func _try_downloaded(kind: String, variant: int, scale_f: float, node_name: String,
		with_collision: bool, yaw_deg: float = 0.0, with_shadow: bool = true) -> Node3D:
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
	if _mesh_nodes(model, 0, []).is_empty():
		model.queue_free()
		return null

	var root := Node3D.new()
	root.name = node_name
	root.add_child(model)

	# Model ka origin (0,0,0) base pe ho ya beech me — hum usko zameen pe bitha dete hain:
	# sabse neeche wala point theek y = 0 par aa jata hai. Yahi pe X/Z bhi center karte hain.
	var box := _visual_aabb(model)
	var authored_scale := Vector3.ONE * scale_f
	model.scale = authored_scale
	model.position = Vector3(
		-(box.position.x + box.size.x * 0.5) * scale_f,
		-box.position.y * scale_f,
		-(box.position.z + box.size.z * 0.5) * scale_f)

	if not is_zero_approx(yaw_deg):
		root.rotation.y = deg_to_rad(yaw_deg)
	if not with_shadow:
		_strip_shadows(model)

	if with_collision:
		_ensure_collision(root, kind)
	return root


## Procedural fallback gaadi — downloaded model na mile to main.gd yeh banata hai.
## (Jaan-boojh kar simple: 5 box + 4 cylinder. Sirf tab dikhti hai jab asset na ho.)
static func fallback_vehicle(_model_name: String, body_color: Color) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "VehicleFallback"
	root.collision_layer = 1        # layer 1 = duniya (goli/enemy isi se takrate hain)

	var body_mat := _mat(body_color, 0.35, 0.45)
	var glass_mat := _mat(Color(0.10, 0.14, 0.20), 0.2, 0.25)
	var tyre_mat := _mat(Color(0.09, 0.09, 0.10), 0.0, 0.95)
	var light_mat := _mat(Color(0.95, 0.92, 0.70), 0.0, 0.4)

	_box(root, Vector3(1.8, 0.7, 4.2), body_mat, Vector3(0.0, 0.75, 0.0))          # body
	_box(root, Vector3(1.6, 0.62, 2.0), glass_mat, Vector3(0.0, 1.4, 0.15))        # cabin
	_box(root, Vector3(1.85, 0.12, 0.3), light_mat, Vector3(0.0, 0.85, -2.05))     # headlight bar
	# chaar pahiye (cylinder default Y axis pe hota hai -> Z pe 90 degree ghumao)
	var wheel_rot := Vector3(HALF_PI, 0.0, 0.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.3, 1.3]:
			_cylinder(root, 0.34, 0.24, tyre_mat, Vector3(0.85 * sx, 0.34, sz), wheel_rot)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.85, 4.3)
	col.shape = shape
	col.position = Vector3(0.0, 0.93, 0.0)
	root.add_child(col)
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

	# Ped = CapsuleShape3D (r = 0.5m, spec). Baaki = BoxShape3D.
	if kind == "tree":
		return _ensure_capsule_collision(node, box, 0.5)

	# kind ke hisaab se kitna mota box (ped ke patte halke hote hain -> patla box)
	var radius_scale := 1.0
	var height_scale := 1.0
	match kind:
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


## Ped ke liye CapsuleShape3D (gol tana). `radius` spec se (0.5 m).
## Capsule ki height me dono gol caps bhi aate hain, isliye height >= 2*radius rakhte hain.
static func _ensure_capsule_collision(node: Node3D, box: AABB, radius: float) -> StaticBody3D:
	var height: float = maxf(box.size.y, radius * 2.2)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.position = Vector3(box.position.x + box.size.x * 0.5, height * 0.5,
			box.position.z + box.size.z * 0.5)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
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
