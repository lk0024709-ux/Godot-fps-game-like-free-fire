extends RefCounted
##
## RannbhoomiBuilder — Task 1 Land Map Assembler + Trimesh Collision Engine
##
## Assembles the complete Battle Royale map ("Rannbhoomi"):
##   1. Seamless Grass Terrain (replaces old blue/green debug grid shader completely)
##   2. 200x200x15m Central Plateau with 4 cardinal walk-up ramps
##   3. Grand Rajasthani Mahal at exact center (0, 15, 0)
##   4. All 11 Modular Buildings organized into named POIs:
##        - Shahi Mahal & Crossroads Outposts (Center ring)
##        - Veergram Village (South-West)
##        - Military Base (North-East)
##        - Purana Bazaar (South-East)
##   5. Aravalli Switchback Mountain (terrain_aravalli_switchback / terrain_mount_abu)
##      in the North-West zone with its 8m ghat road & 25m summit lake plateau
##   6. StaticBody3D + ConcavePolygonShape3D (Trimesh) collision on EVERY placed asset,
##      sharing prebuilt ConcavePolygonShape3D instances per Mesh for 4GB RAM phones.
##

## World coordinate mapping matching assets/ui/rannbhoomi_minimap.png (1:1 orthographic):
## u = 0.5 + x / MAP_MINIMAP_SPAN, v = 0.5 + z / MAP_MINIMAP_SPAN
const MAP_MINIMAP_SPAN: float = 1400.0
const MAHAL_CENTER_POS := Vector3(0.0, 15.0, 0.0)
const ARAVALLI_NW_POS := Vector3(-350.0, 0.0, -360.0)

const MAHAL_PATHS: Array[String] = [
	"res://assets/models/rajasthani_mahal_full.glb",
	"res://assets/models/mahal/rajasthani_mahal_full.glb",
	"res://assets/models/mahal/rajasthani_mahal_mega.glb",
	"res://assets/downloaded_models/rajasthani_mahal_mega.glb",
	"res://assets/downloaded_models/mahal/rajasthani_mahal_mega.glb",
]

const ARAVALLI_PATHS: Array[String] = [
	"res://assets/models/terrain_aravalli_switchback.glb",
	"res://assets/models/terrain/terrain_aravalli_switchback.glb",
	"res://assets/models/terrain/terrain_mount_abu.glb",
	"res://assets/downloaded_models/terrain/terrain_mount_abu.glb",
]

const ARAVALLI_COLLISION_PATHS: Array[String] = [
	"res://assets/models/terrain/terrain_mount_abu_collision.glb",
	"res://assets/downloaded_models/terrain/terrain_mount_abu_collision.glb",
]

const TERRAIN_GROUND_PATHS: Array[String] = [
	"res://assets/models/terrain/terrain_ground.glb",
	"res://assets/downloaded_models/terrain/terrain_ground.glb",
]

const TERRAIN_PLATEAU_PATHS: Array[String] = [
	"res://assets/models/terrain/terrain_plateau.glb",
	"res://assets/downloaded_models/terrain/terrain_plateau.glb",
]

const TERRAIN_HILL_PATHS: Array[String] = [
	"res://assets/models/terrain/terrain_hill_large.glb",
	"res://assets/downloaded_models/terrain/terrain_hill_large.glb",
]

const CARGO_PLANE_PATHS: Array[String] = [
	"res://assets/models/plane_cargo_elite.glb",
	"res://assets/models/vehicles/plane_cargo_elite.glb",
	"res://assets/downloaded_models/vehicles/plane_cargo_elite.glb",
]

const GRASS_TEXTURE_PATHS: Array[String] = [
	"res://assets/textures/grass_1k.png",
	"res://assets/textures/grass.png",
]

const ROCK_TEXTURE_PATHS: Array[String] = [
	"res://assets/textures/rock_stone_1k.png",
]

## All 11 Modular Buildings from indus-assets-gen with exact footprints (width X, depth Z, height Y)
const MODULAR_SPECS := {
	"house_blue": {"size": Vector3(30.3, 9.0, 30.3), "color": Color(0.18, 0.44, 0.75)},
	"school_yellow": {"size": Vector3(45.3, 6.7, 30.3), "color": Color(0.91, 0.76, 0.29)},
	"apartment_green": {"size": Vector3(30.3, 9.7, 30.3), "color": Color(0.37, 0.62, 0.35)},
	"warehouse_metal": {"size": Vector3(45.3, 3.7, 30.3), "color": Color(0.42, 0.48, 0.55)},
	"cabin_wood": {"size": Vector3(15.3, 6.0, 15.2), "color": Color(0.55, 0.36, 0.20)},
	"ruined_building": {"size": Vector3(30.3, 6.1, 30.3), "color": Color(0.52, 0.50, 0.46)},
	"shop_row": {"size": Vector3(30.3, 6.0, 17.4), "color": Color(0.84, 0.48, 0.24)},
	"villa_white": {"size": Vector3(30.3, 9.0, 30.3), "color": Color(0.90, 0.89, 0.85)},
	"farmhouse_stone": {"size": Vector3(30.3, 6.0, 15.3), "color": Color(0.66, 0.58, 0.46)},
	"bunker_military": {"size": Vector3(15.3, 3.7, 15.2), "color": Color(0.30, 0.36, 0.28)},
	"tower_sniper": {"size": Vector3(15.3, 13.0, 15.3), "color": Color(0.46, 0.44, 0.40)},
}

## Named Battle Royale POIs on Rannbhoomi (aligned 1:1 with assets/ui/rannbhoomi_minimap.png)
const POI_ZONES := [
	{"name": "SHAHI MAHAL", "center": Vector2(0.0, 0.0), "radius": 125.0},
	{"name": "ARAVALLI GHAT", "center": Vector2(-350.0, -360.0), "radius": 135.0},
	{"name": "MILITARY BASE", "center": Vector2(336.0, -350.0), "radius": 145.0},
	{"name": "VEERGRAM", "center": Vector2(-322.0, 350.0), "radius": 145.0},
	{"name": "BAZAAR", "center": Vector2(336.0, 350.0), "radius": 145.0},
	{"name": "SOUTH GATE", "center": Vector2(0.0, 175.0), "radius": 85.0},
	{"name": "NORTH DHANI", "center": Vector2(0.0, -175.0), "radius": 85.0},
]

## Curated non-overlapping placements covering ALL 11 modular building models across POIs
const POI_BUILDING_PLACEMENTS := [
	# --- POI 1: VEERGRAM VILLAGE (South-West) ---
	{"id": "school_yellow", "poi": "VEERGRAM", "pos": Vector3(-322.0, 0.0, 295.0), "yaw_deg": 0.0},
	{"id": "house_blue", "poi": "VEERGRAM", "pos": Vector3(-378.0, 0.0, 352.0), "yaw_deg": 90.0},
	{"id": "villa_white", "poi": "VEERGRAM", "pos": Vector3(-268.0, 0.0, 352.0), "yaw_deg": -90.0},
	{"id": "shop_row", "poi": "VEERGRAM", "pos": Vector3(-345.0, 0.0, 405.0), "yaw_deg": 180.0},
	{"id": "cabin_wood", "poi": "VEERGRAM", "pos": Vector3(-280.0, 0.0, 405.0), "yaw_deg": 180.0},

	# --- POI 2: MILITARY BASE (North-East) ---
	{"id": "warehouse_metal", "poi": "MILITARY BASE", "pos": Vector3(312.0, 0.0, -392.0), "yaw_deg": 0.0},
	{"id": "bunker_military", "poi": "MILITARY BASE", "pos": Vector3(382.0, 0.0, -390.0), "yaw_deg": -90.0},
	{"id": "bunker_military", "poi": "MILITARY BASE", "pos": Vector3(276.0, 0.0, -332.0), "yaw_deg": 90.0},
	{"id": "tower_sniper", "poi": "MILITARY BASE", "pos": Vector3(392.0, 0.0, -330.0), "yaw_deg": 180.0},
	{"id": "apartment_green", "poi": "MILITARY BASE", "pos": Vector3(336.0, 0.0, -300.0), "yaw_deg": 180.0},

	# --- POI 3: PURANA BAZAAR (South-East) ---
	{"id": "apartment_green", "poi": "BAZAAR", "pos": Vector3(285.0, 0.0, 312.0), "yaw_deg": 0.0},
	{"id": "shop_row", "poi": "BAZAAR", "pos": Vector3(352.0, 0.0, 305.0), "yaw_deg": 0.0},
	{"id": "ruined_building", "poi": "BAZAAR", "pos": Vector3(382.0, 0.0, 365.0), "yaw_deg": -90.0},
	{"id": "villa_white", "poi": "BAZAAR", "pos": Vector3(288.0, 0.0, 378.0), "yaw_deg": 90.0},
	{"id": "farmhouse_stone", "poi": "BAZAAR", "pos": Vector3(345.0, 0.0, 412.0), "yaw_deg": 180.0},

	# --- POI 4: CENTRAL PLATEAU RAMP OUTPOSTS (Immediate mid-range action around Shahi Mahal!) ---
	{"id": "house_blue", "poi": "SOUTH GATE", "pos": Vector3(-52.0, 0.0, 168.0), "yaw_deg": 180.0},
	{"id": "shop_row", "poi": "SOUTH GATE", "pos": Vector3(52.0, 0.0, 165.0), "yaw_deg": 180.0},
	{"id": "farmhouse_stone", "poi": "NORTH DHANI", "pos": Vector3(-48.0, 0.0, -168.0), "yaw_deg": 0.0},
	{"id": "cabin_wood", "poi": "NORTH DHANI", "pos": Vector3(46.0, 0.0, -168.0), "yaw_deg": 0.0},
	{"id": "tower_sniper", "poi": "WEST OUTPOST", "pos": Vector3(-165.0, 0.0, -42.0), "yaw_deg": 90.0},
	{"id": "ruined_building", "poi": "EAST OUTPOST", "pos": Vector3(168.0, 0.0, 46.0), "yaw_deg": -90.0},
]

static var _shape_cache: Dictionary = {}
static var _scene_cache: Dictionary = {}
static var _grass_material_cache: StandardMaterial3D = null
static var _rock_material_cache: StandardMaterial3D = null


static func clear_caches() -> void:
	_shape_cache.clear()
	_scene_cache.clear()
	_grass_material_cache = null
	_rock_material_cache = null


## Assemble the entire Rannbhoomi land map under `world_root` and return metadata summary.
static func build_world(world_root: Node3D, arena_size: float = 2000.0) -> Dictionary:
	var summary := {
		"mahal_real": false,
		"aravalli_real": false,
		"terrain_real": false,
		"modular_unique_ids": {},
		"modular_count": 0,
		"trimesh_colliders": 0,
		"building_spots": [],
		"hill_spots": [],
	}

	# 1. Remove any legacy debug grid Ground node if present
	var legacy_ground := world_root.get_node_or_null("Ground")
	if legacy_ground != null:
		world_root.remove_child(legacy_ground)
		legacy_ground.free()

	# 2. Grass Terrain across full 2000x2000m land area + ocean safety floor
	var terrain_root := Node3D.new()
	terrain_root.name = "GrassTerrain"
	world_root.add_child(terrain_root)
	var grass_info := _build_grass_terrain(terrain_root, arena_size)
	summary["terrain_real"] = grass_info["real"]
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(grass_info["colliders"])

	# 3. Central 200x200x15m Plateau with 4 walk-up ramps so center is exact Y = 15.0
	var plateau_info := _build_central_plateau(terrain_root)
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(plateau_info["colliders"])

	# 4. Scenic dirt road network connecting Center Mahal <-> all 4 corner POIs
	_build_dirt_roads(terrain_root)

	# 5. Grand Rajasthani Mahal at exact center (0, 15, 0)
	var mahal_info := _build_mahal(world_root)
	summary["mahal_real"] = mahal_info["real"]
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(mahal_info["colliders"])
	summary["building_spots"].append({
		"pos": MAHAL_CENTER_POS,
		"half": Vector2(30.0, 28.0),
		"radius": 42.0,
		"max_half": 30.0,
	})

	# 6. Aravalli Mountain (terrain_aravalli_switchback / terrain_mount_abu) in North-West zone
	var aravalli_info := _build_aravalli_mountain(world_root)
	summary["aravalli_real"] = aravalli_info["real"]
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(aravalli_info["colliders"])
	summary["hill_spots"].append({"pos": ARAVALLI_NW_POS, "radius": 84.0})

	# Flanking Aravalli foothills for a dramatic NW mountain skyline
	var hills_info := _build_flanking_hills(terrain_root)
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(hills_info["colliders"])
	for hs in hills_info["spots"]:
		summary["hill_spots"].append(hs)

	# 7. All 11 Modular Buildings organized into POIs with Trimesh StaticBody3D collision
	var buildings_container := Node3D.new()
	buildings_container.name = "Buildings"
	world_root.add_child(buildings_container)

	var mod_info := _build_modular_pois(buildings_container)
	summary["modular_count"] = mod_info["count"]
	summary["modular_unique_ids"] = mod_info["kinds"]
	summary["trimesh_colliders"] = int(summary["trimesh_colliders"]) + int(mod_info["colliders"])
	for spot in mod_info["spots"]:
		summary["building_spots"].append(spot)

	var total_buildings := int(summary["modular_count"]) + 1
	print("RANNBHOOMI: grass_real=%s mahal_real=%s aravalli_real=%s unique_modular=%d trimesh_colliders=%d" % [
		str(summary["terrain_real"]),
		str(summary["mahal_real"]),
		str(summary["aravalli_real"]),
		(summary["modular_unique_ids"] as Dictionary).size(),
		int(summary["trimesh_colliders"]),
	])
	print("Buildings: %d placed %s" % [total_buildings, summary["modular_unique_ids"]])
	return summary


## Load Elite Cargo Plane model (real synced GLB or high-detail stealth dropship fallback).
static func load_cargo_plane() -> Node3D:
	var wrapper := Node3D.new()
	wrapper.name = "CargoPlane"
	var loaded := _instantiate_first(CARGO_PLANE_PATHS)
	if loaded != null:
		loaded.name = "CargoPlaneModel"
		# In plane_cargo_elite.glb, nose faces +Z and open rear cargo ramp faces -Z.
		# Rotate 180 deg around Y so nose points along -Z (standard Godot look_at forward)
		# and open rear cargo ramp faces +Z trailing behind the flight path!
		loaded.rotation.y = PI
		_set_shadows_recursive(loaded, false)
		wrapper.add_child(loaded)
		wrapper.set_meta("real_glb", true)
		return wrapper

	var fallback := _make_fallback_cargo_plane()
	fallback.name = "CargoPlaneFallback"
	wrapper.add_child(fallback)
	wrapper.set_meta("real_glb", false)
	return wrapper


## Analytical fast ground elevation estimate (used before physics flush or for fast prop scatter).
static func sample_ground_height(x: float, z: float) -> float:
	# 1. Central 200x200m Plateau (-100..+100): flat 120x120m top (-60..+60) at Y = 15.0,
	#    sloped ramps out to +-100m.
	var ax := absf(x)
	var az := absf(z)
	if ax <= 100.0 and az <= 100.0:
		if ax <= 60.0 and az <= 60.0:
			return 15.0
		var edge := maxf(ax, az)
		var t := clampf((edge - 60.0) / 40.0, 0.0, 1.0)
		return lerpf(15.0, 0.0, t)

	# 2. North-West Aravalli Mountain (-350, -360), 150x150m tile (-75..+75), summit r<=30 at Y=25m
	var dx := x - ARAVALLI_NW_POS.x
	var dz := z - ARAVALLI_NW_POS.z
	if absf(dx) <= 75.0 and absf(dz) <= 75.0:
		var r := Vector2(dx, dz).length()
		if r <= 30.0:
			return 25.0
		if r >= 70.0:
			return 0.0
		var u := clampf((r - 30.0) / 40.0, 0.0, 1.0)
		return 25.0 * (1.0 - u * u * (3.0 - 2.0 * u))

	return 0.0


## Named POI lookup for HUD minimap readout.
static func poi_name_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	for zone in POI_ZONES:
		var c: Vector2 = zone["center"]
		if p.distance_to(c) <= float(zone["radius"]):
			return String(zone["name"])
	return "RANNBHOOMI"


## Convert 3D world (x, z) into normalized (0..1, 0..1) UV coordinates on rannbhoomi_minimap.png.
static func world_to_minimap_uv(x: float, z: float) -> Vector2:
	return Vector2(
		clampf(0.5 + x / MAP_MINIMAP_SPAN, 0.02, 0.98),
		clampf(0.5 + z / MAP_MINIMAP_SPAN, 0.02, 0.98)
	)


# ============================================================ GRASS TERRAIN ===

static func _build_grass_terrain(parent: Node3D, arena_size: float) -> Dictionary:
	var colliders := 0
	var real_used := false
	var grass_mat := _get_grass_material(26.0)
	var tile_offsets := [
		Vector3(-500.0, -0.03, -500.0),
		Vector3(500.0, -0.03, -500.0),
		Vector3(-500.0, -0.03, 500.0),
		Vector3(500.0, -0.03, 500.0),
	]

	for i in tile_offsets.size():
		var tile := _instantiate_first(TERRAIN_GROUND_PATHS)
		if tile != null:
			real_used = true
			tile.name = "GrassTile_%d" % i
			tile.position = tile_offsets[i]
			_upgrade_grass_meshes_if_needed(tile, grass_mat)
			_set_shadows_recursive(tile, false)
			parent.add_child(tile)
			colliders += ensure_trimesh_collision(tile)
		else:
			var fallback_tile := _make_grass_tile_mesh("GrassTile_%d" % i, 1000.0, grass_mat)
			fallback_tile.position = tile_offsets[i]
			parent.add_child(fallback_tile)
			colliders += ensure_trimesh_collision(fallback_tile)

	# Outer apron if arena_size > 2000m + wide ocean catch-collider so skydivers never fall forever
	var safety_body := StaticBody3D.new()
	safety_body.name = "LandAndOceanSafetyCollider"
	safety_body.collision_layer = 1
	safety_body.collision_mask = 1
	var safety_shape := CollisionShape3D.new()
	var safety_box := BoxShape3D.new()
	safety_box.size = Vector3(maxf(arena_size * 2.0, 4200.0), 1.0, maxf(arena_size * 2.0, 4200.0))
	safety_shape.shape = safety_box
	safety_shape.position = Vector3(0.0, -0.95, 0.0)
	safety_body.add_child(safety_shape)
	parent.add_child(safety_body)

	return {"real": real_used, "colliders": colliders}


static func _build_central_plateau(parent: Node3D) -> Dictionary:
	var plateau := _instantiate_first(TERRAIN_PLATEAU_PATHS)
	if plateau != null:
		plateau.name = "CentralMahalPlateau"
		# -0.02m keeps top deck at 14.98m cleanly beneath Mahal's 15.00m sandstone floor slab
		plateau.position = Vector3(0.0, -0.02, 0.0)
		parent.add_child(plateau)
		var cols := ensure_trimesh_collision(plateau)
		return {"real": true, "colliders": cols}

	var proc_plateau := _make_procedural_plateau()
	proc_plateau.name = "CentralMahalPlateau"
	proc_plateau.position = Vector3(0.0, -0.02, 0.0)
	parent.add_child(proc_plateau)
	var fallback_cols := ensure_trimesh_collision(proc_plateau)
	return {"real": false, "colliders": fallback_cols}


static func _build_mahal(world_root: Node3D) -> Dictionary:
	var mahal := _instantiate_first(MAHAL_PATHS)
	var is_real := mahal != null
	if mahal == null:
		mahal = _make_procedural_mahal()
	mahal.name = "RajasthaniMahal"
	mahal.position = MAHAL_CENTER_POS
	mahal.set_meta("real_glb", is_real)
	world_root.add_child(mahal)
	var cols := ensure_trimesh_collision(mahal)
	return {"real": is_real, "colliders": cols}


static func _build_aravalli_mountain(world_root: Node3D) -> Dictionary:
	var mountain := _instantiate_first(ARAVALLI_PATHS)
	var is_real := mountain != null
	if mountain == null:
		mountain = _make_procedural_aravalli()
	mountain.name = "AravalliMountain"
	mountain.position = ARAVALLI_NW_POS
	mountain.set_meta("real_glb", is_real)
	world_root.add_child(mountain)

	# Build exact 1:1 Trimesh StaticBody3D colliders directly on every visual mesh of AravalliMountain
	# so visual terrain, boulders, and switchback road share identical world transforms.
	var cols := ensure_trimesh_collision(mountain)
	return {"real": is_real, "colliders": cols}


static func _build_flanking_hills(parent: Node3D) -> Dictionary:
	var hill_positions := [
		{"pos": Vector3(-468.0, 0.0, -292.0), "yaw": 0.4, "scale": Vector3(1.15, 0.92, 1.15)},
		{"pos": Vector3(-282.0, 0.0, -478.0), "yaw": 1.9, "scale": Vector3(1.10, 0.85, 1.10)},
	]
	var spots: Array = []
	var cols := 0
	for i in hill_positions.size():
		var spec: Dictionary = hill_positions[i]
		var hill := _instantiate_first(TERRAIN_HILL_PATHS)
		if hill == null:
			hill = _make_procedural_hill()
		hill.name = "AravalliFoothill_%d" % i
		hill.position = spec["pos"]
		hill.rotation.y = float(spec["yaw"])
		hill.scale = spec["scale"]
		parent.add_child(hill)
		cols += ensure_trimesh_collision(hill)
		spots.append({"pos": spec["pos"], "radius": 48.0})
	return {"spots": spots, "colliders": cols}


static func _build_modular_pois(container: Node3D) -> Dictionary:
	var count := 0
	var colliders := 0
	var kinds := {}
	var spots: Array = []

	for i in POI_BUILDING_PLACEMENTS.size():
		var entry: Dictionary = POI_BUILDING_PLACEMENTS[i]
		var mod_id := String(entry["id"])
		var spec: Dictionary = MODULAR_SPECS.get(mod_id, {"size": Vector3(20.0, 6.0, 20.0), "color": Color(0.7, 0.65, 0.55)})
		var paths: Array[String] = [
			"res://assets/models/buildings_modular/%s.glb" % mod_id,
			"res://assets/models/%s.glb" % mod_id,
			"res://assets/downloaded_models/buildings_modular/%s.glb" % mod_id,
			"res://assets/downloaded_models/%s.glb" % mod_id,
		]
		var bldg := _instantiate_first(paths)
		var is_real := bldg != null
		if bldg == null:
			bldg = _make_procedural_modular_building(mod_id, spec["size"], spec["color"])

		bldg.name = "%s_%d" % [mod_id, i]
		bldg.position = entry["pos"]
		bldg.rotation_degrees.y = float(entry["yaw_deg"])
		bldg.set_meta("modular_id", mod_id)
		bldg.set_meta("poi", String(entry["poi"]))
		bldg.set_meta("real_glb", is_real)
		container.add_child(bldg)

		var c := ensure_trimesh_collision(bldg)
		colliders += c
		count += 1
		kinds[mod_id] = int(kinds.get(mod_id, 0)) + 1

		var sz: Vector3 = spec["size"]
		var swap_axes := int(roundf(absf(float(entry["yaw_deg"])) / 90.0)) % 2 == 1
		var half := Vector2(sz.z * 0.5, sz.x * 0.5) if swap_axes else Vector2(sz.x * 0.5, sz.z * 0.5)
		spots.append({
			"pos": entry["pos"],
			"half": half,
			"radius": half.length() + 2.0,
			"max_half": maxf(half.x, half.y),
		})

	return {
		"count": count,
		"colliders": colliders,
		"kinds": kinds,
		"spots": spots,
	}


static func _build_dirt_roads(parent: Node3D) -> void:
	var roads := Node3D.new()
	roads.name = "RoadNetwork"
	parent.add_child(roads)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.56, 0.37)
	mat.roughness = 0.96
	mat.metallic = 0.0

	var segments := [
		# 4 radial avenues from Central Plateau toes out to ring road
		[Vector2(0.0, 98.0), Vector2(0.0, 235.0), 11.0],
		[Vector2(0.0, -98.0), Vector2(0.0, -235.0), 11.0],
		[Vector2(-98.0, 0.0), Vector2(-235.0, 0.0), 11.0],
		[Vector2(98.0, 0.0), Vector2(235.0, 0.0), 11.0],
		# Scenic ring road + diagonal spokes to POIs (matching rannbhoomi_minimap.png!)
		[Vector2(0.0, -235.0), Vector2(250.0, -295.0), 10.0],
		[Vector2(250.0, -295.0), Vector2(235.0, 0.0), 10.0],
		[Vector2(235.0, 0.0), Vector2(265.0, 285.0), 10.0],
		[Vector2(265.0, 285.0), Vector2(0.0, 235.0), 10.0],
		[Vector2(0.0, 235.0), Vector2(-265.0, 285.0), 10.0],
		[Vector2(-265.0, 285.0), Vector2(-235.0, 0.0), 10.0],
		[Vector2(-235.0, 0.0), Vector2(-288.0, -338.0), 10.0],
		[Vector2(-288.0, -338.0), Vector2(0.0, -235.0), 10.0],
	]

	for i in segments.size():
		var seg: Array = segments[i]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var width := float(seg[2])
		var delta := b - a
		var length := delta.length() + width * 0.5
		var mid := (a + b) * 0.5
		var strip := MeshInstance3D.new()
		strip.name = "Road_%d" % i
		var quad := PlaneMesh.new()
		quad.size = Vector2(width, length)
		quad.material = mat
		strip.mesh = quad
		strip.position = Vector3(mid.x, 0.025, mid.y)
		strip.rotation.y = atan2(delta.x, delta.y)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roads.add_child(strip)


# =============================================== TRIMESH COLLISION GENERATOR ==

## Walk `root` recursively and ensure every MeshInstance3D has a StaticBody3D child
## using a ConcavePolygonShape3D (Trimesh) collider. Deduplicates shapes by Mesh RID.
static func ensure_trimesh_collision(root: Node, collision_layer_bits: int = 1) -> int:
	var created := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null and not _has_static_body_child(mi):
			var shape := _get_or_create_trimesh(mi.mesh)
			if shape != null:
				var body := StaticBody3D.new()
				body.name = mi.name + "_StaticBody3D"
				body.collision_layer = collision_layer_bits
				body.collision_mask = collision_layer_bits
				var col := CollisionShape3D.new()
				col.name = "TrimeshCollisionShape3D"
				col.shape = shape
				body.add_child(col)
				mi.add_child(body)
				created += 1

	for child in root.get_children():
		created += ensure_trimesh_collision(child, collision_layer_bits)
	return created


static func _get_or_create_trimesh(mesh: Mesh) -> ConcavePolygonShape3D:
	var key := mesh.get_rid()
	if _shape_cache.has(key):
		return _shape_cache[key] as ConcavePolygonShape3D
	var shape := mesh.create_trimesh_shape()
	if shape != null:
		shape.backface_collision = true
		_shape_cache[key] = shape
	return shape


static func _has_static_body_child(node: Node) -> bool:
	for child in node.get_children():
		if child is StaticBody3D:
			return true
	return false


# ===================================================== RESOURCE / MATERIAL ====

static func _instantiate_first(paths: Array[String]) -> Node3D:
	for path in paths:
		var packed := _load_packed_scene_quiet(path)
		if packed != null:
			var inst := packed.instantiate()
			if inst is Node3D:
				return inst as Node3D
			var wrap := Node3D.new()
			wrap.add_child(inst)
			return wrap
	return null


static func _load_packed_scene_quiet(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res is PackedScene:
		_scene_cache[path] = res
		return res as PackedScene
	return null


static func _get_grass_material(uv_repeat: float = 24.0) -> StandardMaterial3D:
	if _grass_material_cache != null:
		return _grass_material_cache
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = null
	for p in GRASS_TEXTURE_PATHS:
		if ResourceLoader.exists(p):
			var loaded := ResourceLoader.load(p)
			if loaded is Texture2D:
				tex = loaded as Texture2D
				break
	if tex == null:
		tex = _make_procedural_grass_texture()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.92, 0.98, 0.88)
	mat.uv1_scale = Vector3(uv_repeat, uv_repeat, uv_repeat)
	mat.roughness = 0.95
	mat.metallic = 0.0
	_grass_material_cache = mat
	return mat


static func _get_rock_material() -> StandardMaterial3D:
	if _rock_material_cache != null:
		return _rock_material_cache
	var mat := StandardMaterial3D.new()
	for p in ROCK_TEXTURE_PATHS:
		if ResourceLoader.exists(p):
			var loaded := ResourceLoader.load(p)
			if loaded is Texture2D:
				mat.albedo_texture = loaded as Texture2D
				break
	mat.albedo_color = Color(0.46, 0.43, 0.39)
	mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
	mat.roughness = 0.92
	_rock_material_cache = mat
	return mat


static func _make_procedural_grass_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 20261022
	noise.frequency = 0.055
	noise.fractal_octaves = 4
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	var lush_dark := Color(0.14, 0.31, 0.11)
	var lush_mid := Color(0.24, 0.46, 0.17)
	var warm_meadow := Color(0.36, 0.53, 0.22)
	for y in 128:
		for x in 128:
			var n := clampf(noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
			var c := lush_dark.lerp(lush_mid, clampf(n * 1.4, 0.0, 1.0))
			if n > 0.62:
				c = c.lerp(warm_meadow, (n - 0.62) / 0.38)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _upgrade_grass_meshes_if_needed(node: Node, fallback_mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var surf_mat := mi.mesh.surface_get_material(0)
			if surf_mat == null:
				mi.material_override = fallback_mat
	for c in node.get_children():
		_upgrade_grass_meshes_if_needed(c, fallback_mat)


static func _set_shadows_recursive(node: Node, enabled: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for c in node.get_children():
		_set_shadows_recursive(c, enabled)


# ============================================== FAIL-SOFT PROCEDURAL MESHES ==

static func _make_grass_tile_mesh(tile_name: String, tile_size: float, mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = tile_name
	var mi := MeshInstance3D.new()
	mi.name = "GrassMesh"
	var pm := PlaneMesh.new()
	pm.size = Vector2(tile_size, tile_size)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	pm.material = mat
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


static func _make_procedural_plateau() -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[float] = [-100.0, -60.0, 60.0, 100.0]
	for iz in range(grid.size() - 1):
		for ix in range(grid.size() - 1):
			var x0: float = grid[ix]
			var x1: float = grid[ix + 1]
			var z0: float = grid[iz]
			var z1: float = grid[iz + 1]
			var p00 := Vector3(x0, _plateau_vertex_h(x0, z0), z0)
			var p10 := Vector3(x1, _plateau_vertex_h(x1, z0), z0)
			var p11 := Vector3(x1, _plateau_vertex_h(x1, z1), z1)
			var p01 := Vector3(x0, _plateau_vertex_h(x0, z1), z1)
			st.set_uv(Vector2(x0 * 0.05, z0 * 0.05))
			st.add_vertex(p00)
			st.set_uv(Vector2(x1 * 0.05, z0 * 0.05))
			st.add_vertex(p10)
			st.set_uv(Vector2(x1 * 0.05, z1 * 0.05))
			st.add_vertex(p11)

			st.set_uv(Vector2(x0 * 0.05, z0 * 0.05))
			st.add_vertex(p00)
			st.set_uv(Vector2(x1 * 0.05, z1 * 0.05))
			st.add_vertex(p11)
			st.set_uv(Vector2(x0 * 0.05, z1 * 0.05))
			st.add_vertex(p01)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "PlateauMesh"
	mi.mesh = mesh
	mi.material_override = _get_grass_material(8.0)
	root.add_child(mi)
	return root


static func _plateau_vertex_h(x: float, z: float) -> float:
	if absf(x) <= 60.0 and absf(z) <= 60.0:
		return 15.0
	return 0.0


static func _make_procedural_mahal() -> Node3D:
	var root := Node3D.new()
	var sandstone := StandardMaterial3D.new()
	sandstone.albedo_color = Color(0.85, 0.75, 0.54)
	sandstone.roughness = 0.75

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.98, 0.84, 0.32)
	gold.metallic = 0.75
	gold.roughness = 0.30

	# Floor slab + open courtyard walls (leaving wide walkable gateway openings on all 4 sides)
	_add_mesh_box(root, "MahalFloor", Vector3(0.0, 0.1, 0.0), Vector3(50.0, 0.2, 40.0), sandstone)
	_add_mesh_box(root, "DarbarHallRoof", Vector3(0.0, 6.2, -14.0), Vector3(24.0, 0.4, 12.0), sandstone)
	_add_mesh_box(root, "WallWestA", Vector3(-24.0, 3.1, -12.0), Vector3(1.2, 6.0, 14.0), sandstone)
	_add_mesh_box(root, "WallWestB", Vector3(-24.0, 3.1, 12.0), Vector3(1.2, 6.0, 14.0), sandstone)
	_add_mesh_box(root, "WallEastA", Vector3(24.0, 3.1, -12.0), Vector3(1.2, 6.0, 14.0), sandstone)
	_add_mesh_box(root, "WallEastB", Vector3(24.0, 3.1, 12.0), Vector3(1.2, 6.0, 14.0), sandstone)
	_add_mesh_box(root, "GatewayLeft", Vector3(-12.0, 3.1, 19.0), Vector3(14.0, 6.0, 1.4), sandstone)
	_add_mesh_box(root, "GatewayRight", Vector3(12.0, 3.1, 19.0), Vector3(14.0, 6.0, 1.4), sandstone)
	_add_mesh_box(root, "GatewayLintel", Vector3(0.0, 7.2, 19.0), Vector3(12.0, 2.2, 1.6), sandstone)

	var dome_mi := MeshInstance3D.new()
	dome_mi.name = "MainGoldDome"
	var sphere := SphereMesh.new()
	sphere.radius = 4.6
	sphere.height = 7.0
	sphere.material = gold
	dome_mi.mesh = sphere
	dome_mi.position = Vector3(0.0, 9.5, -14.0)
	root.add_child(dome_mi)
	return root


static func _make_procedural_aravalli() -> Node3D:
	var root := Node3D.new()
	var steps := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in steps:
		var z0 := -75.0 + 150.0 * float(iz) / float(steps)
		var z1 := -75.0 + 150.0 * float(iz + 1) / float(steps)
		for ix in steps:
			var x0 := -75.0 + 150.0 * float(ix) / float(steps)
			var x1 := -75.0 + 150.0 * float(ix + 1) / float(steps)
			var p00 := Vector3(x0, _aravalli_local_h(x0, z0), z0)
			var p10 := Vector3(x1, _aravalli_local_h(x1, z0), z0)
			var p11 := Vector3(x1, _aravalli_local_h(x1, z1), z1)
			var p01 := Vector3(x0, _aravalli_local_h(x0, z1), z1)
			st.set_uv(Vector2(x0 * 0.04, z0 * 0.04))
			st.add_vertex(p00)
			st.set_uv(Vector2(x1 * 0.04, z0 * 0.04))
			st.add_vertex(p10)
			st.set_uv(Vector2(x1 * 0.04, z1 * 0.04))
			st.add_vertex(p11)

			st.set_uv(Vector2(x0 * 0.04, z0 * 0.04))
			st.add_vertex(p00)
			st.set_uv(Vector2(x1 * 0.04, z1 * 0.04))
			st.add_vertex(p11)
			st.set_uv(Vector2(x0 * 0.04, z1 * 0.04))
			st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "AravalliMesaMesh"
	mi.mesh = st.commit()
	mi.material_override = _get_rock_material()
	root.add_child(mi)
	return root


static func _aravalli_local_h(dx: float, dz: float) -> float:
	var r := Vector2(dx, dz).length()
	if r <= 30.0:
		return 25.0
	if r >= 70.0:
		return 0.0
	var u := clampf((r - 30.0) / 40.0, 0.0, 1.0)
	return 25.0 * (1.0 - u * u * (3.0 - 2.0 * u))


static func _make_procedural_hill() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "HillMesh"
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 38.0
	cyl.top_radius = 8.0
	cyl.height = 36.0
	cyl.radial_segments = 12
	cyl.material = _get_rock_material()
	mi.mesh = cyl
	mi.position.y = 18.0
	root.add_child(mi)
	return root


static func _make_procedural_modular_building(mod_id: String, sz: Vector3, wall_col: Color) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wall_col
	mat.roughness = 0.85

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = wall_col.darkened(0.35)
	roof_mat.roughness = 0.9

	var w := sz.x
	var h := sz.y
	var d := sz.z
	var door_w := 3.2
	var side_w := maxf(1.5, (w - door_w) * 0.5)

	_add_mesh_box(root, mod_id + "_Floor", Vector3(0.0, 0.1, 0.0), Vector3(w, 0.2, d), roof_mat)
	_add_mesh_box(root, mod_id + "_Roof", Vector3(0.0, h - 0.15, 0.0), Vector3(w, 0.3, d), roof_mat)
	_add_mesh_box(root, mod_id + "_Back", Vector3(0.0, h * 0.5, -d * 0.5 + 0.15), Vector3(w, h, 0.3), mat)
	_add_mesh_box(root, mod_id + "_Left", Vector3(-w * 0.5 + 0.15, h * 0.5, 0.0), Vector3(0.3, h, d), mat)
	_add_mesh_box(root, mod_id + "_Right", Vector3(w * 0.5 - 0.15, h * 0.5, 0.0), Vector3(0.3, h, d), mat)
	_add_mesh_box(root, mod_id + "_FrontL", Vector3(-(door_w + side_w) * 0.5, h * 0.5, d * 0.5 - 0.15), Vector3(side_w, h, 0.3), mat)
	_add_mesh_box(root, mod_id + "_FrontR", Vector3((door_w + side_w) * 0.5, h * 0.5, d * 0.5 - 0.15), Vector3(side_w, h, 0.3), mat)
	return root


static func _make_fallback_cargo_plane() -> Node3D:
	var root := Node3D.new()
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.18, 0.20, 0.24)
	hull_mat.metallic = 0.55
	hull_mat.roughness = 0.45

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.13, 0.90, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.13, 0.90, 1.0)
	glow_mat.emission_energy_multiplier = 2.5

	_add_mesh_box(root, "FuselageFloor", Vector3(0.0, 2.6, 0.0), Vector3(5.2, 0.25, 28.0), hull_mat, false)
	_add_mesh_box(root, "FuselageRoof", Vector3(0.0, 5.4, -1.0), Vector3(5.2, 0.25, 26.0), hull_mat, false)
	_add_mesh_box(root, "FuselageWallL", Vector3(-2.5, 4.0, -1.0), Vector3(0.25, 2.8, 26.0), hull_mat, false)
	_add_mesh_box(root, "FuselageWallR", Vector3(2.5, 4.0, -1.0), Vector3(0.25, 2.8, 26.0), hull_mat, false)
	_add_mesh_box(root, "Wings", Vector3(0.0, 4.5, -1.5), Vector3(44.0, 0.35, 7.5), hull_mat, false)
	_add_mesh_box(root, "CargoRamp", Vector3(0.0, 1.9, 15.2), Vector3(4.8, 0.2, 4.5), hull_mat, false)
	_add_mesh_box(root, "WingStrip", Vector3(0.0, 4.72, -1.5), Vector3(43.0, 0.08, 0.3), glow_mat, false)
	return root


static func _add_mesh_box(
	parent: Node3D,
	box_name: String,
	pos: Vector3,
	sz: Vector3,
	mat: Material,
	cast_shadows: bool = true
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(mi)
	return mi
