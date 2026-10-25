extends Node3D
## Live regression for independent NPC minds, NPC-vs-NPC combat, 50-player
## lobby accounting, no-respawn enforcement, performance culling, and victory.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LOOT_WEAPON := preload("res://scripts/loot_weapon.gd")

var _frame: int = 0
var _done: bool = false
var _checks: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	_make_box("Ground", Vector3(0.0, -0.5, 0.0), Vector3(600.0, 1.0, 600.0))
	# Already in the physics world before AI checks: used later as a vision blocker.
	_make_box("VisionBlocker", Vector3(20.0, 1.5, 0.0), Vector3(10.0, 3.0, 1.0))


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame < 6:
		return
	_done = true
	_run()


func _run() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.0, 10.0)

	var npc_a = ENEMY_SCENE.instantiate()
	npc_a.npc_id = 101
	add_child(npc_a)
	npc_a.set_physics_process(false)
	npc_a.global_position = Vector3.ZERO
	npc_a.aim_error = 0.0

	var npc_b = ENEMY_SCENE.instantiate()
	npc_b.npc_id = 102
	add_child(npc_b)
	npc_b.set_physics_process(false)
	npc_b.global_position = Vector3(5.0, 0.0, 0.0)
	npc_b.aim_error = 0.0

	var loot = LOOT_WEAPON.new()
	add_child(loot)
	loot.global_position = Vector3(1.0, 0.18, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(npc_a.state == npc_a.State.PARACHUTE, "AI: NPC starts in PARACHUTE")
	npc_a.complete_landing()
	_check(npc_a.state == npc_a.State.LOOTING, "AI: landing starts LOOTING")
	npc_a._update_looting(0.1)
	_check(npc_a.armed and loot.consumed and npc_a.state == npc_a.State.PATROLLING,
		"AI: reaching a real loot_weapon consumes it, equips a gun, and starts patrol")

	npc_b.complete_landing()
	npc_b._update_looting(10.1)
	_check(npc_b.armed and npc_b.weapon_name == "Generic Rifle",
		"AI: ten seconds without loot grants the generic fallback gun")

	# During the landing grace period, even an isolated visible human is ignored.
	npc_b.global_position = Vector3(60.0, 0.0, 0.0)
	npc_a._face_position(player.global_position)
	npc_a._landing_elapsed = 10.0
	npc_a.target = null
	npc_a._set_state(npc_a.State.PATROLLING)
	npc_a._think()
	_check(npc_a.target == null and npc_a.state != npc_a.State.COMBAT,
		"AI: first 30 seconds ignore the human instead of forcing combat")

	# Put only the NPC pair close together: target acquisition must choose NPC B.
	npc_b.global_position = Vector3(5.0, 0.0, 0.0)
	npc_a._face_position(npc_b.global_position)
	npc_a._landing_elapsed = 31.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	npc_a._think()
	if npc_a.target != npc_b:
		print("AI DEBUG: combatants=", get_tree().get_nodes_in_group("br_combatant").size(),
			" target=", npc_a.target, " LOS_B=", npc_a._has_line_of_sight(npc_b))
	_check(npc_a.target == npc_b and npc_a.state == npc_a.State.COMBAT,
		"AI: clear line of sight selects another NPC as a combat target")

	# A world collider between the same pair must block both perception and damage.
	npc_a.global_position = Vector3(20.0, 0.0, -5.0)
	npc_b.global_position = Vector3(20.0, 0.0, 5.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	npc_a.target = npc_b
	_check(not npc_a._has_line_of_sight(npc_b), "AI: walls block NPC vision")
	var hp_before_wall_shot: float = npc_b.health
	npc_a._shoot_at_target()
	_check(npc_b.health == hp_before_wall_shot, "AI: walls block NPC hitscan damage")

	# Restore clear LOS, then prove one NPC damages another with attacker attribution.
	npc_a.global_position = Vector3.ZERO
	npc_b.global_position = Vector3(5.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	npc_a.target = npc_b
	var hp_before_hit: float = npc_b.health
	npc_a._shoot_at_target()
	_check(npc_b.health == hp_before_hit - npc_a.npc_damage and npc_b.last_attacker == npc_a
		and npc_a.shots_hit >= 1,
		"AI: NPC shot damages another NPC and records the real attacker")

	npc_b.take_damage(160.0, npc_a)
	_check(npc_b.health <= npc_b.max_health * 0.20 and npc_b.state == npc_b.State.FLEEING,
		"AI: health below 20 percent triggers FLEEING and cover search")

	npc_a.target = null
	npc_a._set_state(npc_a.State.PATROLLING)
	var sound_position: Vector3 = npc_a.global_position + Vector3(10.0, 0.0, 0.0)
	npc_a.hear_gunshot(sound_position, npc_b)
	_check(npc_a.is_suspicious and npc_a.state == npc_a.State.PATROLLING
		and npc_a._sound_target.is_equal_approx(sound_position),
		"AI: nearby gunshot creates a suspicious patrol toward the sound")

	# Distance culling must skip brain/vision work, then resume near the human.
	npc_a.global_position = Vector3(100.0, 0.0, 100.0)
	player.global_position = Vector3(400.0, 0.0, 100.0)
	npc_a._set_state(npc_a.State.PATROLLING)
	npc_a._think_timer = 0.0
	npc_a.velocity = Vector3(5.0, 0.0, 5.0)
	var brain_before_cull: int = npc_a.brain_ticks
	var full_ticks_before: int = npc_a.full_ai_ticks
	npc_a._physics_process(0.1)
	_check(not npc_a.full_ai_active and npc_a.culled_ticks > 0
		and npc_a.brain_ticks == brain_before_cull and npc_a.full_ai_ticks == full_ticks_before
		and Vector2(npc_a.velocity.x, npc_a.velocity.z).length() < 0.01,
		"Performance: NPC beyond 150m freezes movement and skips complex AI")
	player.global_position = npc_a.global_position + Vector3(20.0, 0.0, 0.0)
	npc_a._think_timer = 0.0
	npc_a._physics_process(0.1)
	_check(npc_a.full_ai_active and npc_a.full_ai_ticks > full_ticks_before
		and npc_a.brain_ticks > brain_before_cull,
		"Performance: full independent AI resumes when the human gets closer")

	# Remove the isolated AI fixture before creating the real 50-player match.
	for fixture in [player, npc_a, npc_b]:
		if is_instance_valid(fixture):
			if fixture.get_parent() != null:
				fixture.get_parent().remove_child(fixture)
			fixture.queue_free()
	await get_tree().physics_frame

	var match_manager = MAIN_SCENE.instantiate()
	match_manager.plane_drop_enabled = false
	match_manager.npc_spawn_batch = 49
	add_child(match_manager)
	_check(match_manager.alive_players == 50 and match_manager._npc_spawned_total == 49
		and match_manager.active_npc_count() == 49,
		"Lobby: strict roster is exactly one human plus 49 active NPCs")
	_check(match_manager.hud.alive_label.text == "PLAYERS ALIVE: 50",
		"Lobby: HUD starts at Players Alive 50")

	var npcs: Array = match_manager.enemy_container.get_children().duplicate()
	var first_npc = npcs[0]
	var second_npc = npcs[1]
	first_npc.last_attacker = second_npc
	first_npc.die()
	_check(match_manager.alive_players == 49 and match_manager.kills == 0
		and match_manager.score == 0,
		"Lobby: NPC-vs-NPC death reduces Alive without rewarding the human")
	match_manager._on_spawn_timer_timeout()
	_check(match_manager._npc_spawned_total == 49 and match_manager.active_npc_count() == 48,
		"Lobby: dead NPCs are never replaced and the 49 NPC cap is strict")

	second_npc.take_damage(200.0, match_manager.player)
	_check(match_manager.alive_players == 48 and match_manager.kills == 1
		and match_manager.score == 10,
		"Lobby: a human kill updates Alive and human score exactly once")
	for npc in npcs:
		if is_instance_valid(npc) and not npc.is_dead:
			npc.last_attacker = null
			npc.die()
	_check(match_manager.alive_players == 1 and match_manager.game_over,
		"Lobby: Alive reaches one and ends the match")
	_check(match_manager.hud.game_over_panel.visible
		and match_manager.hud.game_over_title.text.replace("\n", " ") == "WINNER WINNER CHICKEN DINNER",
		"Victory: last human standing sees WINNER WINNER CHICKEN DINNER")
	match_manager.queue_free()
	_finish()


func _make_box(node_name: String, at_position: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at_position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + description)
	else:
		_failures.append(description)
		push_error("BATTLE_ROYALE_SELFTEST: " + description)


func _finish() -> void:
	print("BATTLE_ROYALE_SELFTEST checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("BATTLE_ROYALE_SELFTEST_PASS")
		get_tree().quit(0)
	else:
		print("BATTLE_ROYALE_SELFTEST_FAIL")
		get_tree().quit(1)
