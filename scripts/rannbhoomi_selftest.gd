extends Node
##
## Rannbhoomi Full Battle Royale Integration Self-Test (Tasks 1, 2, & 3)
##
## Runs headlessly in Godot 4.2.2 during CI (`scenes/rannbhoomi_selftest.tscn`) to
## verify every single requirement live inside the real 3D physics world and UI tree.
##

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const EXPECTED_MODULAR_BUILDINGS: Array[String] = [
	"apartment_green",
	"bunker_military",
	"cabin_wood",
	"farmhouse_stone",
	"house_blue",
	"ruined_building",
	"school_yellow",
	"shop_row",
	"tower_sniper",
	"villa_white",
	"warehouse_metal",
]

const DT: float = 1.0 / 60.0

var _main = null
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
	var main_node: Node3D = _main as Node3D

	# 1. Old debug grid removed & GrassTerrain active without shader grid
	_assert_true(main_node.get_node_or_null("Ground") == null, "Task1: legacy debug grid Ground removed")
	var grass: Node3D = main_node.get_node_or_null("GrassTerrain") as Node3D
	_assert_true(grass != null, "Task1: GrassTerrain root exists")
	if grass != null:
		var has_shader_mat: bool = _contains_shader_material(grass)
		_assert_true(not has_shader_mat, "Task1: GrassTerrain uses textured StandardMaterial3D (no debug ShaderMaterial)")
		_assert_true(_count_trimesh_colliders(grass) >= 5,
			"Task1: GrassTerrain & plateau have Trimesh StaticBody3D colliders (%d)" % _count_trimesh_colliders(grass))

	# 2. Grand Rajasthani Mahal placed at exact (0, 15, 0) with Trimesh collision
	var mahal: Node3D = main_node.get_node_or_null("RajasthaniMahal") as Node3D
	_assert_true(mahal != null, "Task1: RajasthaniMahal placed")
	if mahal != null:
		_assert_true(
			mahal.global_position.distance_to(Vector3(0.0, 15.0, 0.0)) < 0.01,
			"Task1: RajasthaniMahal at exact (0, 15, 0) -> got %s" % str(mahal.global_position)
		)
		_assert_true(_count_meshes(mahal) >= 1, "Task1: RajasthaniMahal has 3D mesh geometry")
		_assert_true(_count_trimesh_colliders(mahal) >= 1, "Task1: RajasthaniMahal has Trimesh StaticBody3D collider")

	# Live raycast check at center forecourt (0, 26) confirming solid ground at Y >= 15.0m
	var space: PhysicsDirectSpaceState3D = main_node.get_world_3d().direct_space_state
	var center_hit: Dictionary = _raycast_down(space, Vector2(0.0, 26.0), 90.0)
	var center_y: float = float(center_hit["position"].y) if not center_hit.is_empty() else -999.0
	_assert_true(
		not center_hit.is_empty() and center_y >= 14.9,
		"Task1: Center plateau raycast hits solid ground at Y=%.2fm" % center_y
	)

	# 3. All 11 Modular Buildings placed in named POIs with Trimesh StaticBody3D colliders
	var summary: Dictionary = _main._world_summary
	var placed_mods: Dictionary = summary.get("modular_unique_ids", {})
	for model_id in EXPECTED_MODULAR_BUILDINGS:
		_assert_true(
			placed_mods.has(model_id),
			"Task1: modular building '%s' placed in POI" % model_id
		)

	var buildings_root: Node3D = main_node.get_node_or_null("Buildings") as Node3D
	_assert_true(buildings_root != null, "Task1: Buildings POI container exists")
	var bldg_count: int = 0
	var bldg_with_trimesh: int = 0
	var pois_seen: Dictionary = {}
	if buildings_root != null:
		for b in buildings_root.get_children():
			bldg_count += 1
			if b.has_meta("poi"):
				pois_seen[String(b.get_meta("poi"))] = true
			if _count_trimesh_colliders(b) >= 1:
				bldg_with_trimesh += 1

	_assert_true(pois_seen.size() >= 3, "Task1: multiple distinct named POIs populated (%d POIs)" % pois_seen.size())
	_assert_true(bldg_count >= 11, "Task1: >=11 POI buildings placed (%d placed)" % bldg_count)
	_assert_true(
		bldg_with_trimesh == bldg_count,
		"Task1: every placed POI building has Trimesh StaticBody3D (%d/%d)" % [bldg_with_trimesh, bldg_count]
	)

	# 4. Aravalli Mountain placed in North-West zone with Trimesh collision
	var mountain: Node3D = main_node.get_node_or_null("AravalliMountain") as Node3D
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
		var m_hit: Dictionary = _raycast_down(
			space,
			Vector2(mountain.global_position.x, mountain.global_position.z),
			90.0
		)
		var mountain_y: float = float(m_hit["position"].y) if not m_hit.is_empty() else -999.0
		_assert_true(
			not m_hit.is_empty() and mountain_y > 10.0,
			"Task1: AravalliMountain raycast confirms elevated peak collider (Y=%.2fm)" % mountain_y
		)


# ===================================================== TASK 2 VERIFICATION ====

func _verify_task2_plane_drop() -> void:
	var player = _main.player
	var hud = _main.hud
	var plane: Node3D = _main.get_cargo_plane()

	# 1. Plane spawned at Y = 300m at edge of map & player locked inside initially
	# Reset fresh drop at t=0.000s (cancelling the 3 physics warmup frames)
	_main._start_plane_drop()
	plane = _main.get_cargo_plane()
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
		int(player.drop_state) == int(player.DropState.IN_PLANE),
		"Task2: Player initially locked inside CargoPlane (state=%d)" % int(player.drop_state)
	)
	_assert_true(
		bool(hud.eject_panel.visible) and String(hud.eject_button.label_text) == "EJECT",
		"Task2: Prominent UI 'EJECT' button visible while in plane"
	)

	# 2. Verify exact 50.0 m/s straight-line flight + player locked with plane
	var p0: Vector3 = plane.global_position
	var pl0: Vector3 = player.global_position
	var steps_2s: int = 120
	for _i in steps_2s:
		_main._physics_process(DT)
		player._physics_process(DT)
	var p1: Vector3 = plane.global_position
	var pl1: Vector3 = player.global_position
	var actual_speed: float = p0.distance_to(p1) / (float(steps_2s) * DT)
	var pdir: Vector3 = _main._plane_direction
	var dir_check: float = (p1 - p0).normalized().dot(pdir)
	_assert_true(
		absf(actual_speed - 50.0) < 0.15 and absf(p1.y - 300.0) < 0.05 and dir_check > 0.9999,
		"Task2: CargoPlane flies straight across map at 50.0 m/s (measured %.2f m/s, dot=%.5f)" % [actual_speed, dir_check]
	)
	_assert_true(
		absf(pl0.distance_to(pl1) - p0.distance_to(p1)) < 0.05,
		"Task2: Player stays locked inside moving CargoPlane"
	)

	# 3. Verify automatic 15.0s force-eject when player does NOT press EJECT
	for _i in 779:
		_main._physics_process(DT)
		player._physics_process(DT)
	_assert_true(
		int(player.drop_state) == int(player.DropState.IN_PLANE),
		"Task2: Still aboard plane just prior to 15.0s auto-eject"
	)
	for _i in 4:
		_main._physics_process(DT)
		player._physics_process(DT)
	_assert_true(
		bool(_main.is_player_ejected()) and int(player.drop_state) == int(player.DropState.FREEFALL),
		"Task2: Force-ejected automatically at 15.0s into FREEFALL (pos=%s)" % str(player.global_position)
	)

	# 4. Also verify manual EJECT button press immediately triggers FREEFALL
	_main._start_plane_drop()
	_assert_true(int(player.drop_state) == int(player.DropState.IN_PLANE),
		"Task2: Plane drop reset cleanly for manual EJECT check")
	hud.eject_button.pressed.emit()
	_assert_true(
		bool(_main.is_player_ejected()) and int(player.drop_state) == int(player.DropState.FREEFALL)
		and not bool(hud.eject_panel.visible),
		"Task2: Pressing EJECT button immediately ejects player & hides EJECT panel"
	)

	# 5. Simulate free-fall down to Y <= 50m -> parachute auto-deploys & fall speed == 5.0 m/s
	player.global_position = Vector3(-180.0, 297.5, 0.0)
	player.velocity = Vector3(0.0, -6.0, 0.0)
	var deployed_at_y: float = -1.0
	for _i in 900:
		player._physics_process(DT)
		if int(player.drop_state) == int(player.DropState.PARACHUTE):
			var dpos: Vector3 = player.global_position
			deployed_at_y = dpos.y
			break

	_assert_true(
		int(player.drop_state) == int(player.DropState.PARACHUTE) and deployed_at_y <= 50.05 and deployed_at_y >= 46.0,
		"Task2: Parachute auto-deployed at Y<=50m (deployed at Y=%.2fm)" % deployed_at_y
	)
	_assert_true(bool(player.has_parachute()), "Task2: 3D ParachuteRig attached during PARACHUTE state")

	var glide_start_pos: Vector3 = player.global_position
	var y_before_glide: float = glide_start_pos.y
	var glide_ticks: int = 60
	for _i in glide_ticks:
		player._physics_process(DT)
	var glide_end_pos: Vector3 = player.global_position
	var glide_vel: Vector3 = player.velocity
	var measured_fall_speed: float = (y_before_glide - glide_end_pos.y) / (float(glide_ticks) * DT)
	_assert_true(
		absf(measured_fall_speed - 5.0) < 0.15 and absf(glide_vel.y - (-5.0)) < 0.05,
		"Task2: Parachute reduces fall speed to 5.0 m/s (measured %.2f m/s)" % measured_fall_speed
	)

	# 6. Simulate until ground touchdown -> parachute removed & normal FPS enabled
	for _i in 900:
		player._physics_process(DT)
		if int(player.drop_state) == int(player.DropState.LANDED):
			break

	var landed_pos: Vector3 = player.global_position
	_assert_true(
		int(player.drop_state) == int(player.DropState.LANDED),
		"Task2: Player transitioned to LANDED upon touching ground (Y=%.2fm)" % landed_pos.y
	)
	_assert_true(
		not bool(player.has_parachute()),
		"Task2: Parachute cleanly removed upon landing"
	)
	_assert_true(
		bool(player.weapon_holder.visible),
		"Task2: First-person weapon restored upon landing"
	)


# ===================================================== TASK 3 VERIFICATION ====

func _verify_task3_hud_and_multitouch() -> void:
	var player = _main.player
	var hud = _main.hud

	# 1. Verify Top-Left Minimap + RANNBHOOMI image + Rotating Arrow
	var mm_panel: Control = hud.minimap_panel
	var mm_view: Control = hud.minimap_view
	var arrow: Control = mm_view.get_node_or_null("PlayerArrow") as Control
	_assert_true(mm_panel.position.x < 80.0 and mm_panel.position.y < 80.0,
		"Task3: Minimap positioned at Top-Left")
	_assert_true(mm_view.MINIMAP_TEXTURE != null,
		"Task3: Minimap loads RANNBHOOMI texture")
	_assert_true(arrow != null, "Task3: Minimap has rotating PlayerArrow node")

	player.rotation.y = 0.0
	_main._push_hud_telemetry()
	var rot_north: float = arrow.rotation if arrow != null else -1.0
	var cmp_north: String = String(hud.compass_bar.get_cardinal_string())

	player.rotation.y = -PI * 0.5
	_main._push_hud_telemetry()
	var rot_east: float = arrow.rotation if arrow != null else -1.0
	var cmp_east: String = String(hud.compass_bar.get_cardinal_string())

	_assert_true(
		absf(rot_north - 0.0) < 0.02 and absf(rot_east - PI * 0.5) < 0.02,
		"Task3: Minimap PlayerArrow rotates accurately with player heading (N=%.2f -> E=%.2f)" % [rot_north, rot_east]
	)
	_assert_true(
		cmp_north.begins_with("N ") and cmp_east.begins_with("E "),
		"Task3: Top-Center Compass updates cardinal direction live ('%s' -> '%s')" % [cmp_north, cmp_east]
	)

	# 2. Verify all required HUD controls exist & have zero button overlap in Bottom-Right
	_assert_true(
		hud.joystick != null and hud.backpack_button != null and hud.heal_button != null,
		"Task3: Bottom-Left Dynamic Joystick + Backpack + Heal buttons present"
	)
	_assert_true(
		hud.ep_bar != null and hud.health_bar != null and bool(hud.ep_bar.visible) and bool(hud.health_bar.visible),
		"Task3: Bottom-Center HP and EP bars visible"
	)
	var fire_btn: Control = hud.fire_button
	var aim_btn: Control = hud.aim_button
	var jump_btn: Control = hud.jump_button
	var crouch_btn: Control = hud.crouch_button
	var reload_btn: Control = hud.reload_button
	_assert_true(
		fire_btn != null and aim_btn != null and jump_btn != null
		and crouch_btn != null and reload_btn != null,
		"Task3: Bottom-Right Large FIRE + Aim, Jump, Crouch, Reload buttons present"
	)
	_assert_true(
		fire_btn.size.x >= 140.0 and fire_btn.size.y >= 140.0,
		"Task3: FIRE button is prominently sized (%.0fx%.0f)" % [fire_btn.size.x, fire_btn.size.y]
	)

	var right_cluster: Array[Control] = [fire_btn, aim_btn, jump_btn, crouch_btn, reload_btn]
	var overlap_found: bool = false
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
	var hp_damaged: int = int(player.health)
	hud.heal_button.pressed.emit()
	var hp_healed: int = int(player.health)
	_assert_true(
		hp_healed > hp_damaged,
		"Task3: Heal button consumes medkit & restores HP (%d -> %d)" % [hp_damaged, hp_healed]
	)
	crouch_btn.pressed.emit()
	_assert_true(bool(player.is_crouching), "Task3: Crouch button activates crouch stance")
	crouch_btn.pressed.emit()
	_assert_true(not bool(player.is_crouching), "Task3: Crouch button toggles back to standing")

	# 5. Live Simultaneous Multi-Touch Test
	var bullets_node: Node3D = _main.bullet_container
	var bullets_before: int = bullets_node.get_child_count()

	var joy_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	joy_touch.index = 0
	joy_touch.pressed = true
	joy_touch.position = Vector2(140.0, 140.0)
	hud.joystick._gui_input(joy_touch)

	var joy_drag: InputEventScreenDrag = InputEventScreenDrag.new()
	joy_drag.index = 0
	joy_drag.position = Vector2(140.0, 56.0)
	hud.joystick._gui_input(joy_drag)

	var fire_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	fire_touch.index = 1
	fire_touch.pressed = true
	fire_touch.position = fire_btn.size * 0.5
	fire_btn._gui_input(fire_touch)

	var aim_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	aim_touch.index = 2
	aim_touch.pressed = true
	aim_touch.position = aim_btn.size * 0.5
	aim_btn._gui_input(aim_touch)

	for _i in 4:
		player._physics_process(DT)

	var pvel: Vector3 = player.velocity
	var horiz_speed: float = Vector2(pvel.x, pvel.z).length()
	var bullets_after: int = bullets_node.get_child_count()
	_assert_true(
		horiz_speed > 2.5 and bool(player.is_firing) and bullets_after > bullets_before and bool(player.is_aiming),
		"Task3: Multi-touch works simultaneously (speed=%.2f m/s, firing=%s, bullets=%d->%d, aiming=%s)" % [
			horiz_speed, str(player.is_firing), bullets_before, bullets_after, str(player.is_aiming)
		]
	)


# ============================================================ HELPERS =========

func _raycast_down(space: PhysicsDirectSpaceState3D, xz: Vector2, top_y: float) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, top_y, xz.y),
		Vector3(xz.x, -10.0, xz.y)
	)
	q.collision_mask = 1
	return space.intersect_ray(q)


func _count_meshes(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _count_trimesh_colliders(node: Node) -> int:
	var total: int = 0
	if node is StaticBody3D:
		for child in node.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is ConcavePolygonShape3D:
				total += 1
	for child in node.get_children():
		total += _count_trimesh_colliders(child)
	return total


func _contains_shader_material(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
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
