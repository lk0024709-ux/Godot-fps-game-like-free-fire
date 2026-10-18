extends Node3D
##
## Terrain-only Battle Royale island generator.
##
## This scene intentionally creates terrain, its StaticBody collision, ocean, sky,
## fog, sun, and a lightweight cloud layer only. It does not spawn gameplay actors,
## weapons, buildings, or vehicles. The deterministic height function is shared by
## the mesh, collision, and terrain smoke test.
##

const ISLAND_RADIUS := 400.0
const RADIAL_STEP := 5.0
const ANGULAR_SEGMENTS := 320
const OCEAN_SIZE := 2000.0
const OCEAN_Y := -0.5
const PLATEAU_RADIUS := 120.0
const PLATEAU_HEIGHT := 15.0
const RAMP_END_RADIUS := 230.0
const RAMP_FADE_RADIUS := 310.0
const VALLEY_DEPTH := 14.0
const NEAR_SHADOW_RADIUS := 240.0
const SKY_TOP := Color(0.20, 0.40, 0.76)
const SKY_HORIZON := Color(0.63, 0.77, 0.91)
const GRASS := Color(0.20, 0.39, 0.16)
const SAND := Color(0.79, 0.67, 0.44)
const CONCRETE := Color(0.39, 0.43, 0.46)

var _height_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _ground_body: StaticBody3D


func _ready() -> void:
	_configure_noise()
	_create_atmosphere()
	_create_ocean()
	_create_island()
	_create_clouds()
	print(
		(
			"ISLAND: radius %.0fm, plateau %.0fm @ %.0fm, collision ready"
			% [ISLAND_RADIUS, PLATEAU_RADIUS, PLATEAU_HEIGHT]
		)
	)


## Public sample for terrain tests and later map-placement tools.
func sample_height(x: float, z: float) -> float:
	return _height_at(x, z)


func _configure_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.seed = 481203
	_height_noise.frequency = 0.006
	_height_noise.fractal_octaves = 3
	_height_noise.fractal_gain = 0.48
	_height_noise.fractal_lacunarity = 2.0

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = 92271
	_detail_noise.frequency = 0.018
	_detail_noise.fractal_octaves = 2
	_detail_noise.fractal_gain = 0.42
	_detail_noise.fractal_lacunarity = 2.1


func _create_atmosphere() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.sky_curve = 0.18
	sky_material.ground_bottom_color = Color(0.20, 0.25, 0.27)
	sky_material.ground_horizon_color = SKY_HORIZON.darkened(0.12)
	sky_material.ground_curve = 0.10
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_light_color = SKY_HORIZON
	environment.fog_density = 0.0011
	environment.fog_aerial_perspective = 0.22
	environment.fog_sky_affect = 0.85

	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.87)
	sun.light_energy = 1.15
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	add_child(sun)


func _create_ocean() -> void:
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.035, 0.25, 0.43, 0.70)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.22
	water_material.metallic = 0.04
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var plane := PlaneMesh.new()
	plane.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	plane.material = water_material

	var water := MeshInstance3D.new()
	water.name = "Ocean_2000m"
	water.mesh = plane
	water.position.y = OCEAN_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _create_island() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var ring_count := int(roundf(ISLAND_RADIUS / RADIAL_STEP))

	vertices.append(Vector3(0.0, PLATEAU_HEIGHT, 0.0))
	colors.append(_color_at(0.0, 0.0, PLATEAU_HEIGHT))

	for ring in range(1, ring_count + 1):
		var radius := float(ring) * RADIAL_STEP
		for segment in ANGULAR_SEGMENTS:
			var angle := TAU * float(segment) / float(ANGULAR_SEGMENTS)
			var x := radius * cos(angle)
			var z := radius * sin(angle)
			var height := _height_at(x, z)
			vertices.append(Vector3(x, height, z))
			colors.append(_color_at(x, z, height))

	# Center fan, wound upward (+Y).
	var first_ring_start := 1
	for segment in ANGULAR_SEGMENTS:
		var next_segment := (segment + 1) % ANGULAR_SEGMENTS
		indices.append(0)
		indices.append(first_ring_start + next_segment)
		indices.append(first_ring_start + segment)

	# Concentric quads keep the island circular and put a mesh ring exactly at 120m.
	for ring in range(1, ring_count):
		var inner_start := 1 + (ring - 1) * ANGULAR_SEGMENTS
		var outer_start := 1 + ring * ANGULAR_SEGMENTS
		for segment in ANGULAR_SEGMENTS:
			var next_segment := (segment + 1) % ANGULAR_SEGMENTS
			var inner_a := inner_start + segment
			var inner_b := inner_start + next_segment
			var outer_a := outer_start + segment
			var outer_b := outer_start + next_segment
			indices.append(inner_a)
			indices.append(inner_b)
			indices.append(outer_b)
			indices.append(inner_a)
			indices.append(outer_b)
			indices.append(outer_a)

	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	var faces := PackedVector3Array()
	var near_indices := PackedInt32Array()
	var far_indices := PackedInt32Array()

	for offset in range(0, indices.size(), 3):
		var i0 := indices[offset]
		var i1 := indices[offset + 1]
		var i2 := indices[offset + 2]
		var v0 := vertices[i0]
		var v1 := vertices[i1]
		var v2 := vertices[i2]
		var face_normal := (v1 - v0).cross(v2 - v0)
		normals[i0] = normals[i0] + face_normal
		normals[i1] = normals[i1] + face_normal
		normals[i2] = normals[i2] + face_normal
		faces.append(v0)
		faces.append(v1)
		faces.append(v2)

		var centroid_x := (v0.x + v1.x + v2.x) / 3.0
		var centroid_z := (v0.z + v1.z + v2.z) / 3.0
		if Vector2(centroid_x, centroid_z).length() <= NEAR_SHADOW_RADIUS:
			near_indices.append(i0)
			near_indices.append(i1)
			near_indices.append(i2)
		else:
			far_indices.append(i0)
			far_indices.append(i1)
			far_indices.append(i2)

	for i in normals.size():
		normals[i] = normals[i].normalized()

	var terrain_material := StandardMaterial3D.new()
	terrain_material.albedo_color = Color.WHITE
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 1.0
	terrain_material.metallic = 0.0

	var near_instance := MeshInstance3D.new()
	near_instance.name = "Terrain_Near_Casts_Shadows"
	near_instance.mesh = _mesh_from_arrays(
		vertices, normals, colors, near_indices, terrain_material
	)
	near_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(near_instance)

	var far_instance := MeshInstance3D.new()
	far_instance.name = "Terrain_Distant_Hills_No_Shadows"
	far_instance.mesh = _mesh_from_arrays(vertices, normals, colors, far_indices, terrain_material)
	far_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_instance)

	_ground_body = StaticBody3D.new()
	_ground_body.name = "IslandGround_ConcaveCollision"
	_ground_body.collision_layer = 1
	_ground_body.collision_mask = 1
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "IslandGroundShape"
	collision.shape = concave
	_ground_body.add_child(collision)
	add_child(_ground_body)


func _mesh_from_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	mesh_indices: PackedInt32Array,
	material: Material
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = mesh_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _height_at(x: float, z: float) -> float:
	var radius := Vector2(x, z).length()
	var broad_noise := _height_noise.get_noise_2d(x, z)
	var detail := _detail_noise.get_noise_2d(x, z)
	var base_height := 1.4 + broad_noise * 2.2 + detail * 0.65
	var height := base_height

	# A broken-edged 30-50m high mountain ring, tapering toward the 20m beach.
	var ridge_weight := _ridge_weight(radius)
	var angle := atan2(z, x)
	var angular_peaks := sin(angle * 7.0 + 0.45) * 5.0 + cos(angle * 13.0 - 0.8) * 2.8
	var ridge_peak := clampf(39.0 + angular_peaks + broad_noise * 3.0, 30.0, 50.0)
	height = lerpf(base_height, ridge_peak, ridge_weight)

	# Exact central 120m-radius plateau. The four cardinal lanes ease down over 110m;
	# the surrounding escarpment falls more quickly, so the ramps read clearly.
	if radius <= PLATEAU_RADIUS:
		height = PLATEAU_HEIGHT
	else:
		var general_fall := smoothstep(PLATEAU_RADIUS, 160.0, radius)
		height = lerpf(PLATEAU_HEIGHT, height, general_fall)
		var ramp_weight := _ramp_weight(x, z)
		var ramp_fall := smoothstep(PLATEAU_RADIUS, RAMP_END_RADIUS, radius)
		var ramp_height := lerpf(PLATEAU_HEIGHT, base_height, ramp_fall)
		var ramp_region := 1.0 - smoothstep(RAMP_END_RADIUS, RAMP_FADE_RADIUS, radius)
		height = lerpf(height, ramp_height, ramp_weight * ramp_region)

	# A meandering 14m cut runs SW-to-NE through the outer mountain ring, clear of
	# the four ramp approaches; confining it to the ridge keeps its floor above the sea.
	var valley_distance := _valley_distance(x, z)
	var valley_weight := (
		(1.0 - smoothstep(12.0, 58.0, valley_distance))
		* smoothstep(155.0, 190.0, radius)
		* ridge_weight
	)
	height -= VALLEY_DEPTH * valley_weight

	# A flat concrete apron in the eastern quadrant; its rounded rectangle leaves the
	# east ramp lane clear and does not flatten the central plateau.
	var industrial_weight := _industrial_weight(x, z)
	industrial_weight *= 1.0 - _ramp_weight(x, z) * 0.9
	height = lerpf(height, 4.0, industrial_weight)

	# Lower the outer 20m beach gradually below sea level so it meets the ocean plane.
	if radius > 360.0:
		height = lerpf(height, 0.5, smoothstep(360.0, 382.0, radius))
	if radius > 380.0:
		height = lerpf(height, -2.0, smoothstep(380.0, ISLAND_RADIUS, radius))
	return height


func _color_at(x: float, z: float, height: float) -> Color:
	var radius := Vector2(x, z).length()
	var detail := _detail_noise.get_noise_2d(x, z)
	var grass := GRASS.lerp(Color(0.30, 0.46, 0.19), 0.20 + detail * 0.11)
	var hill_amount := clampf((height - 8.0) / 45.0, 0.0, 0.65)
	grass = grass.lerp(Color(0.30, 0.35, 0.20), hill_amount)

	var ramp_color_weight := (
		_ramp_weight(x, z)
		* smoothstep(120.0, 137.0, radius)
		* (1.0 - smoothstep(218.0, 235.0, radius))
	)
	grass = grass.lerp(Color(0.39, 0.45, 0.30), ramp_color_weight * 0.72)

	var valley_distance := _valley_distance(x, z)
	var valley_color_weight := (
		(1.0 - smoothstep(16.0, 58.0, valley_distance))
		* smoothstep(155.0, 190.0, radius)
		* _ridge_weight(radius)
	)
	grass = grass.lerp(Color(0.16, 0.29, 0.22), valley_color_weight * 0.80)
	var river_weight := (1.0 - smoothstep(5.0, 12.0, valley_distance)) * valley_color_weight
	grass = grass.lerp(Color(0.19, 0.34, 0.36), river_weight * 0.85)

	var industrial_weight := _industrial_weight(x, z) * (1.0 - _ramp_weight(x, z) * 0.9)
	grass = grass.lerp(CONCRETE, industrial_weight)

	var snow_weight := (
		_ridge_weight(radius)
		* (1.0 - smoothstep(72.0, 145.0, absf(x)))
		* smoothstep(255.0, 305.0, -z)
	)
	grass = grass.lerp(Color(0.82, 0.88, 0.91), snow_weight * 0.92)

	var beach_weight := smoothstep(375.0, 384.0, radius)
	grass = grass.lerp(SAND, beach_weight)
	return Color(
		clampf(grass.r, 0.0, 1.0), clampf(grass.g, 0.0, 1.0), clampf(grass.b, 0.0, 1.0), 1.0
	)


func _ridge_weight(radius: float) -> float:
	# A wide, walkable 30-50m ridge belt; taper fully before the beach shelf.
	return smoothstep(205.0, 275.0, radius) * (1.0 - smoothstep(295.0, 365.0, radius))


func _ramp_weight(x: float, z: float) -> float:
	# min(|x|, |z|) identifies the four cardinal lines without creating diagonal lanes.
	return 1.0 - smoothstep(14.0, 31.0, minf(absf(x), absf(z)))


func _valley_distance(x: float, z: float) -> float:
	var meander := 25.0 * sin(x * 0.006)
	return absf(x + z - meander) / 1.41421356


func _industrial_weight(x: float, z: float) -> float:
	var rectangle_distance := maxf(absf((x - 245.0) / 66.0), absf((z + 70.0) / 46.0))
	return 1.0 - smoothstep(0.82, 1.0, rectangle_distance)


func _create_clouds() -> void:
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(0.94, 0.97, 1.0, 0.58)
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloud_material.roughness = 1.0

	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = cloud_material

	var cloud_transforms: Array[Transform3D] = [
		Transform3D(Basis.from_scale(Vector3(55.0, 8.0, 25.0)), Vector3(-430.0, 205.0, -370.0)),
		Transform3D(Basis.from_scale(Vector3(34.0, 7.0, 20.0)), Vector3(-350.0, 212.0, -350.0)),
		Transform3D(Basis.from_scale(Vector3(62.0, 9.0, 28.0)), Vector3(100.0, 225.0, -500.0)),
		Transform3D(Basis.from_scale(Vector3(38.0, 7.0, 22.0)), Vector3(180.0, 220.0, -470.0)),
		Transform3D(Basis.from_scale(Vector3(50.0, 8.0, 24.0)), Vector3(500.0, 215.0, -210.0)),
		Transform3D(Basis.from_scale(Vector3(66.0, 9.0, 27.0)), Vector3(420.0, 225.0, 300.0)),
		Transform3D(Basis.from_scale(Vector3(39.0, 6.0, 20.0)), Vector3(350.0, 215.0, 330.0)),
		Transform3D(Basis.from_scale(Vector3(57.0, 8.0, 24.0)), Vector3(-130.0, 230.0, 510.0)),
		Transform3D(Basis.from_scale(Vector3(43.0, 7.0, 21.0)), Vector3(-220.0, 220.0, 480.0)),
		Transform3D(Basis.from_scale(Vector3(60.0, 8.0, 26.0)), Vector3(-520.0, 215.0, 70.0)),
	]

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff
	multimesh.instance_count = cloud_transforms.size()
	for i in cloud_transforms.size():
		multimesh.set_instance_transform(i, cloud_transforms[i])

	var clouds := MultiMeshInstance3D.new()
	clouds.name = "LowPolyCloudBank"
	clouds.multimesh = multimesh
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)
