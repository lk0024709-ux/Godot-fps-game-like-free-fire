extends Node
##
## Rannbhoomi Full Battle Royale Integration Self-Test (Tasks 1, 2, & 3)
##
## Runs headlessly in Godot 4.2.2 during CI (`scenes/rannbhoomi_selftest.tscn`) to
## verify every single requirement live inside the real 3D physics world and UI tree:
##
##   Task 1:
##     - No legacy debug grid `Ground`; real `GrassTerrain` (`grass_1k.png`) placed.
##     - `RajasthaniMahal` placed at exact `Vector3(0, 15, 0)` with Trimesh `StaticBody3D`.
##     - All 11 unique `buildings_modular/*.glb` models placed across named POIs with
##       Trimesh `StaticBody3D` concave collisions.
##     - `AravalliMountain` placed in North-West zone (`x < 0, z < 0`) with Trimesh collision.
##
##   Task 2:
##     - `CargoPlane` (`plane_cargo_elite`) spawned at `Y = 300m` at NW edge, flying straight
##       at exact `50.0 m/s`.
##     - Player locked inside plane initially (`IN_PLANE`), moving with plane.
##     - Prominent `"EJECT"` button visible & functional (`IN_PLANE -> FREEFALL`), PLUS
##       verified `15.0s` automatic force-eject if player does not press `"EJECT"`.
##     - Free-fall skydiving -> auto-deploy 3D parachute at `Y <= 50.0m` -> descent rate
##       reduced to `5.0 m/s`.
##     - Landing on solid ground removes parachute (`has_parachute() == false`) and restores
##       normal FPS movement & shooting (`LANDED`).
##
##   Task 3:
##     - Top-Left `MinimapPanel/MinimapView` with `rannbhoomi_minimap.png` + rotating `PlayerArrow`.
##     - Top-Center `CompassBar` updating live bearing (`N / E / S / W`) as player rotates.
##     - Bottom-Left dynamic `Joystick` + `BackpackButton` + `HealButton`.
##     - Bottom-Center `EPBar` + `HealthBar`.
##     - Bottom-Right large `FireButton` + `AimButton`, `JumpButton`, `CrouchButton`, `ReloadButton`.
##     - Every non-interactive `Control` strictly has `mouse_filter == MOUSE_FILTER_IGNORE`.
##     - Simultaneous multi-touch (moving via `Joystick` + shooting via `FireButton` + ADS via
##       `AimButton` simultaneously on independent touch indices).
##

const MAIN_SCENE := preload("res://scenes/main.tscn")
const RannbhoomiBuilder := preload("res://scripts/rannbhoomi_builder.gd")

const DT: float = 1.0 / 60.0

var _main: Node3D = null
var _frame: int = 0
var _checks: int = 0
var _failures: Array[String] = []
var _done: bool = false


func _ready() -> void:
	print("==================== RANNBHOOMI SELFTEST START ====================")
	_main = MAIN_SCENE.instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	# Wait 3 physics ticks so all StaticBody3D shapes register in PhysicsServer3D
	if _frame < 4:
		return
	_done = true
	_run_all_verifications()


func _run_all_verifications() -> void:
	_verify_task1_land_map()
	_verify_task2_plane_drop()
	_verify_task3_hud_and_multitouch()
	_finish_report()


# ===================================================== TASK 1 VERIFICATION ====

func _verify_task1_land_map() -> void:
	var land := _main.get_node_or_null("RannbhoomiLand") as Node3D
	_assert_true(land != null, "Task1: RannbhoomiLand root exists")
	if land == null:
		return

	# 1. Old debug grid removed & GrassTerrain active without shader grid
	_assert_true(_main.get_node_or_null("Ground") == null, "Task1: legacy debug grid Ground removed")
	var grass := land.get_node_or_null("GrassTerrain") as Node3D
	_assert_true(grass != null and grass.get_child_count() == 4,
		"Task1: 4 GrassTerrain tiles placed (got %d)" % (grass.get_child_count() if grass != null else 0))
	if grass != null:
		var has_shader_mat := _contains_shader_material(grass)
		_assert_true(not has_shader_mat, "Task1: GrassTerrain uses textured StandardMaterial3D (no debug ShaderMaterial)")
		_assert_true(_count_trimesh_colliders(grass) >= 4, "Task1: GrassTerrain tiles have Trimesh StaticBody3D colliders")

	# 2. Grand Rajasthani Mahal placed at exact (0, 15, 0) with Trimesh collision
	var mahal := land.get_node_or_null("RajasthaniMahal") as Node3D
	_assert_true(mahal != null, "Task1: RajasthaniMahal placed")
	if mahal != null:
		_assert_true(
			mahal.global_position.distance_to(Vector3(0.0, 15.0, 0.0)) < 0.01,
			"Task1: RajasthaniMahal at exact (0, 15, 0) -> got %s" % str(mahal.global_position)
		)
		_assert_true(_count_meshes(mahal) >= 1, "Task1: RajasthaniMahal has 3D mesh geometry")
		_assert_true(_count_trimesh_colliders(mahal) >= 1, "Task1: RajasthaniMahal has Trimesh StaticBody3D collider")

	var plateau := land.get_node_or_null("CentralMahalPlateau") as Node3D
	_assert_true(plateau != null and _count_trimesh_colliders(plateau) >= 1,
		"Task1: CentralMahalPlateau (Y=15m) has Trimesh StaticBody3D collider")

	# Live raycast check at center (0, z) confirming solid ground at Y >= 15.0m
	var space := _main.get_world_3d().direct_space_state
	var center_hit := _raycast_down(space, Vector2(0.0, 26.0), 90.0)
	_assert_true(
		not center_hit.is_empty() and float(center_hit["position"].y) >= 14.9,
		"Task1: Center plateau raycast hits solid ground at Y=%.2fm" % (
			float(center_hit["position"].y) if not center_hit.is_empty() else -999.0
		)
	)

	# 3. All 11 Modular Buildings placed in named POIs with Trimesh StaticBody3D colliders
	var summary: Dictionary = _main._world_summary
	var placed_mods: Dictionary = summary.get("placed_modular", {})
	for model_id in RannbhoomiBuilder.REQUIRED_MODULAR_BUILDINGS:
		_assert_true(
			placed_mods.has(model_id),
			"Task1: modular building '%s' placed in POI" % model_id
		)

	var poi_count := 0
	var bldg_count := 0
	var bldg_with_trimesh := 0
	for poi_name in ["MilitaryBase", "VeergramVillage", "RannbhoomiBazaar", "AravalliOutpost"]:
		var poi_node := land.get_node_or_null(poi_name) as Node3D
		if poi_node != null:
			poi_count += 1
			for b in poi_node.get_children():
				bldg_count += 1
				if _count_trimesh_colliders(b) >= 1:
					bldg_with_trimesh += 1

	_assert_true(poi_count == 4, "Task1: all 4 named POIs created (%d/4)" % poi_count)
	_assert_true(bldg_count >= 11, "Task1: >=11 POI buildings placed (%d placed)" % bldg_count)
	_assert_true(
		bldg_with_trimesh == bldg_count,
		"Task1: every placed POI building has Trimesh StaticBody3D (%d/%d)" % [bldg_with_trimesh, bldg_count]
	)

	# 4. Aravalli Mountain placed in North-West zone with Trimesh collision
	var mountain := land.get_node_or_null("AravalliMountain") as Node3D
	_assert_true(mountain != null, "Task1: AravalliMountain placed")
	if mountain != null:
		_assert_true(
			mountain.global_position.x < -200.0 and mountain.global_position.z < -200.0,
			"Task1: AravalliMountain in North-West zone (%s)" % str(mountain.global_position)
		)
		_assert_true(
			_count_trimesh_colliders(mountain) >= 1,
			"Task1: AravalliMountain has Trimesh StaticBody3D collider"
		)
		var m_hit := _raycast_down(
			space,
			Vector2(mountain.global_position.x, mountain.global_position.z),
			90.0
		)
		_assert_true(
			not m_hit.is_empty() and float(m_hit["position"].y) > 10.0,
			"Task1: AravalliMountain raycast confirms elevated peak collider (Y=%.2fm)" % (
				float(m_hit["position"].y) if not m_hit.is_empty() else -999.0
			)
		)


# ===================================================== TASK 2 VERIFICATION ====

func _verify_task2_plane_drop() -> void:
	var player = _main.player
	var hud = _main.hud
	var plane: Node3D = _main.get_cargo_plane()

	# 1. Plane spawned at Y = 300m at edge of map & player locked inside initially
	_assert_true(plane != null and is_instance_valid(plane), "Task2: CargoPlane spawned")
	if plane == null:
		return

	_assert_true(
		absf(plane.global_position.y - 300.0) < 0.05,
		"Task2: CargoPlane altitude is Y=300m (got %.2fm)" % plane.global_position.y
	)
	_assert_true(
		Vector2(plane.global_position.x, plane.global_position.z).length() > 700.0,
		"Task2: CargoPlane starts at map edge (%s)" % str(plane.global_position)
	)
	_assert_true(
		player.drop_state == player.DropState.IN_PLANE,
		"Task2: Player initially locked inside CargoPlane (state=%d)" % player.drop_state
	)
	_assert_true(
		hud.eject_panel.visible and hud.eject_button.label_text == "EJECT",
		"Task2: Prominent UI 'EJECT' button visible while in plane"
	)

	# 2. Verify exact 50.0 m/s straight-line flight + player locked with plane
	var p0 := plane.global_position
	var pl0: Vector3 = player.global_position
	var steps_2s := 120
	for _i in steps_2s:
		_main._physics_process(DT)
		player._physics_process(DT)
	var p1 := plane.global_position
	var pl1: Vector3 = player.global_position
	var actual_speed := p0.distance_to(p1) / (float(steps_2s) * DT)
	var dir_check := (p1 - p0).normalized().dot(_main._plane_direction)
	_assert_true(
		absf(actual_speed - 50.0) < 0.15 and absf(p1.y - 300.0) < 0.05 and dir_check > 0.9999,
		"Task2: CargoPlane flies straight across map at 50.0 m/s (measured %.2f m/s, dot=%.5f)" % [actual_speed, dir_check]
	)
	_assert_true(
		absf(pl0.distance_to(pl1) - p0.distance_to(p1)) < 0.05,
		"Task2: Player stays locked inside moving CargoPlane"
	)

	# 3. Verify automatic 15.0s force-eject when player does NOT press EJECT
	for _i in 779: # Total elapsed = (120 + 779)/60 = 14.983s -> still IN_PLANE!
		_main._physics_process(DT)
		player._physics_process(DT)
	_assert_true(
		player.drop_state == player.DropState.IN_PLANE,
		"Task2: Still aboard plane just prior to 15.0s auto-eject"
	)
	for _i in 4: # Crosses 15.00s -> must auto force-eject!
		_main._physics_process(DT)
		player._physics_process(DT)
	_assert_true(
		_main.is_player_ejected() and player.drop_state == player.DropState.FREEFALL,
		"Task2: Force-ejected automatically at 15.0s into FREEFALL (pos=%s)" % str(player.global_position)
	)

	# 4. Also verify manual EJECT button press immediately triggers FREEFALL
	_main._start_plane_drop()
	_assert_true(player.drop_state == player.DropState.IN_PLANE, "Task2: Plane drop reset cleanly for manual EJECT check")
	hud.eject_button.pressed.emit()
	_assert_true(
		_main.is_player_ejected() and player.drop_state == player.DropState.FREEFALL and not hud.eject_panel.visible,
		"Task2: Pressing EJECT button immediately ejects player & hides EJECT panel"
	)

	# 5. Simulate free-fall down to Y <= 50m -> parachute auto-deploys & fall speed == 5.0 m/s
	# Place over open grass field (x=-180, z=0 -> ground Y=0.0m) so full Y=50m -> Y=0m glide runs cleanly
	player.global_position = Vector3(-180.0, 297.5, 0.0)
	player.velocity = Vector3(0.0, -6.0, 0.0)
	var deployed_at_y := -1.0
	for _i in 900:
		player._physics_process(DT)
		if player.drop_state == player.DropState.PARACHUTE:
			deployed_at_y = player.global_position.y
			break

	_assert_true(
		player.drop_state == player.DropState.PARACHUTE and deployed_at_y <= 50.05 and deployed_at_y >= 46.0,
		"Task2: Parachute auto-deployed at Y<=50m (deployed at Y=%.2fm)" % deployed_at_y
	)
	_assert_true(player.has_parachute(), "Task2: 3D ParachuteRig attached during PARACHUTE state")

	# Measure exact descent rate during PARACHUTE state
	var y_before_glide: float = player.global_position.y
	var glide_ticks := 60 # 1.00 second
	for _i in glide_ticks:
		player._physics_process(DT)
	var measured_fall_speed := (y_before_glide - player.global_position.y) / (float(glide_ticks) * DT)
	_assert_true(
		absf(measured_fall_speed - 5.0) < 0.15 and absf(player.velocity.y - (-5.0)) < 0.05,
		"Task2: Parachute reduces fall speed to 5.0 m/s (measured %.2f m/s)" % measured_fall_speed
	)

	# 6. Simulate until ground touchdown -> parachute removed & normal FPS enabled
	for _i in 900:
		player._physics_process(DT)
		if player.drop_state == player.DropState.LANDED:
			break

	_assert_true(
		player.drop_state == player.DropState.LANDED,
		"Task2: Player transitioned to LANDED upon touching ground (Y=%.2fm)" % player.global_position.y
	)
	_assert_true(
		not player.has_parachute(),
		"Task2: Parachute cleanly removed upon landing"
	)
	_assert_true(
		player.weapon_holder.visible,
		"Task2: First-person weapon restored upon landing"
	)


# ===================================================== TASK 3 VERIFICATION ====

func _verify_task3_hud_and_multitouch() -> void:
	var player = _main.player
	var hud = _main.hud

	# 1. Verify Top-Left Minimap + RANNBHOOMI image + Rotating Arrow
	var arrow := hud.minimap_view.get_node_or_null("PlayerArrow") as Control
	_assert_true(hud.minimap_panel.position.x < 80.0 and hud.minimap_panel.position.y < 80.0,
		"Task3: Minimap positioned at Top-Left")
	_assert_true(hud.minimap_view.MINIMAP_TEXTURE != null,
		"Task3: Minimap loads RANNBHOOMI texture")
	_assert_true(arrow != null, "Task3: Minimap has rotating PlayerArrow node")

	# Rotate player East (-PI/2) and verify BOTH PlayerArrow.rotation AND Top-Center Compass bearing == 90 deg ("E")
	player.rotation.y = 0.0
	_main._push_hud_telemetry()
	var rot_north: float = arrow.rotation if arrow != null else -1.0
	var cmp_north: String = hud.compass_bar.get_cardinal_string()

	player.rotation.y = -PI * 0.5
	_main._push_hud_telemetry()
	var rot_east: float = arrow.rotation if arrow != null else -1.0
	var cmp_east: String = hud.compass_bar.get_cardinal_string()

	_assert_true(
		absf(rot_north - 0.0) < 0.02 and absf(rot_east - PI * 0.5) < 0.02,
		"Task3: Minimap PlayerArrow rotates accurately with player heading (N=%.2f -> E=%.2f)" % [rot_north, rot_east]
	)
	_assert_true(
		cmp_north.begins_with("N ") and cmp_east.begins_with("E "),
		"Task3: Top-Center Compass updates cardinal direction live ('%s' -> '%s')" % [cmp_north, cmp_east]
	)

	# 2. Verify all required HUD controls exist & have zero button overlap in Bottom-Right & Bottom-Left
	_assert_true(
		hud.joystick != null and hud.backpack_button != null and hud.heal_button != null,
		"Task3: Bottom-Left Dynamic Joystick + Backpack + Heal buttons present"
	)
	_assert_true(
		hud.ep_bar != null and hud.health_bar != null and hud.ep_bar.visible and hud.health_bar.visible,
		"Task3: Bottom-Center HP and EP bars visible"
	)
	_assert_true(
		hud.fire_button != null and hud.aim_button != null and hud.jump_button != null
		and hud.crouch_button != null and hud.reload_button != null,
		"Task3: Bottom-Right Large FIRE + Aim, Jump, Crouch, Reload buttons present"
	)
	_assert_true(
		hud.fire_button.size.x >= 140.0 and hud.fire_button.size.y >= 140.0,
		"Task3: FIRE button is prominently sized (%.0fx%.0f)" % [hud.fire_button.size.x, hud.fire_button.size.y]
	)

	var right_cluster: Array[Control] = [
		hud.fire_button, hud.aim_button, hud.jump_button, hud.crouch_button, hud.reload_button
	]
	var overlap_found := false
	for i in right_cluster.size():
		for j in range(i + 1, right_cluster.size()):
			if right_cluster[i].get_global_rect().intersects(right_cluster[j].get_global_rect()):
				overlap_found = true
	_assert_true(not overlap_found, "Task3: Zero overlap among Bottom-Right combat buttons")

	# 3. Verify mouse_filter == MOUSE_FILTER_IGNORE on non-interactive UI elements
	var non_interactive_check: Array[Control] = [
		hud.hit_flash, hud.crosshair, hud.minimap_panel, hud.minimap_view,
		hud.minimap_zone_label, hud.compass_bar, hud.score_label,
		hud.weapon_label, hud.ammo_label, hud.ep_bar, hud.ep_label,
		hud.health_bar, hud.health_label, hud.touch_controls, hud.drop_status_banner,
	]
	if arrow != null:
		non_interactive_check.append(arrow)
	var bad_filters: Array[String] = []
	for ctrl in non_interactive_check:
		if ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad_filters.append("%s(%d)" % [ctrl.name, ctrl.mouse_filter])
	_assert_true(
		bad_filters.is_empty(),
		"Task3: Non-interactive HUD nodes use MOUSE_FILTER_IGNORE (violations: %s)" % str(bad_filters)
	)

	# 4. Verify Heal button restores HP + EP and Crouch button toggles stance
	player.take_damage(50)
	var hp_damaged: int = player.health
	hud.heal_button.pressed.emit()
	_assert_true(
		player.health > hp_damaged,
		"Task3: Heal button consumes medkit & restores HP (%d -> %d)" % [hp_damaged, player.health]
	)
	hud.crouch_button.pressed.emit()
	_assert_true(player.is_crouching, "Task3: Crouch button activates crouch stance")
	hud.crouch_button.pressed.emit()
	_assert_true(not player.is_crouching, "Task3: Crouch button toggles back to standing")

	# 5. Live Simultaneous Multi-Touch Test:
	# Finger #0 drags Dynamic Virtual Joystick forward WHILE Finger #1 holds FIRE button
	# WHILE Finger #2 taps AIM button — all active at the exact same moment!
	var bullets_before: int = _main.bullet_container.get_child_count()

	var joy_touch := InputEventScreenTouch.new()
	joy_touch.index = 0
	joy_touch.pressed = true
	joy_touch.position = Vector2(140.0, 140.0)
	hud.joystick._gui_input(joy_touch)

	var joy_drag := InputEventScreenDrag.new()
	joy_drag.index = 0
	joy_drag.position = Vector2(140.0, 56.0) # Full push forward (-Y)
	hud.joystick._gui_input(joy_drag)

	var fire_touch := InputEventScreenTouch.new()
	fire_touch.index = 1
	fire_touch.pressed = true
	fire_touch.position = hud.fire_button.size * 0.5
	hud.fire_button._gui_input(fire_touch)

	var aim_touch := InputEventScreenTouch.new()
	aim_touch.index = 2
	aim_touch.pressed = true
	aim_touch.position = hud.aim_button.size * 0.5
	hud.aim_button._gui_input(aim_touch)

	for _i in 4:
		player._physics_process(DT)

	var horiz_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var bullets_after: int = _main.bullet_container.get_child_count()
	_assert_true(
		horiz_speed > 2.5 and player.is_firing and bullets_after > bullets_before and player.is_aiming,
		"Task3: Multi-touch works simultaneously (speed=%.2f m/s, firing=%s, bullets=%d->%d, aiming=%s)" % [
			horiz_speed, str(player.is_firing), bullets_before, bullets_after, str(player.is_aiming)
		]
	)


# ============================================================ HELPERS =========

func _raycast_down(space: PhysicsDirectSpaceState3D, xz: Vector2, top_y: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, top_y, xz.y),
		Vector3(xz.x, -10.0, xz.y)
	)
	q.collision_mask = 1
	return space.intersect_ray(q)


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _count_trimesh_colliders(node: Node) -> int:
	var total := 0
	if node is StaticBody3D:
		for child in node.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is ConcavePolygonShape3D:
				total += 1
	for child in node.get_children():
		total += _count_trimesh_colliders(child)
	return total


func _contains_shader_material(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			return true
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				if mi.get_active_material(s) is ShaderMaterial:
					return true
	for child in node.get_children():
		if _contains_shader_material(child):
			return true
	return false


func _assert_true(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] " + label)
		return
	_failures.append(label)
	push_error("RANNBHOOMI_SELFTEST FAIL: " + label)


func _finish_report() -> void:
	print("------------------------------------------------------------------")
	if _failures.is_empty():
		print("RANNBHOOMI_SELFTEST_PASS: %d/%d checks green" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print("RANNBHOOMI_SELFTEST_FAIL: %d/%d checks failed" % [_failures.size(), _checks])
		for f in _failures:
			print("  FAIL -> " + f)
		get_tree().quit(1)
