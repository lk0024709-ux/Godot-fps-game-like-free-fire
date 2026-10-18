extends Node
##
## Drop selftest — Battle Royale ka poora plane-drop loop automatic check
## (CI me headless chalta hai, 8d/8e jaisa hi step).
##
## Kya check hota hai (har phase fail hone pe exit code 1):
##   1. Match sky-dive se shuru hota hai — player ~300m upar plane me
##   2. Drop ke dauran sun shadows BAND hain (4GB perf)
##   3. Eject ke baad FREEFALL state + gravity
##   4. ~50m pe parachute khud khulta hai (mesh lagta hai)
##   5. Zameen pe land -> GROUND state, chhatri hati, gun wapas
##   6. Sprint: Shift daba ke speed ~10 m/s + FOV badhta hai, chhodte hi wapas
##
## Chalane ka tarika (GitHub Actions step "8h"):
##     godot --headless --path . --fixed-fps 60 --quit-after 900 scenes/drop_selftest.tscn
## Exit code 0 = PASS, 1 = FAIL.
##

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _main: Node3D = null
var _player: CharacterBody3D = null
var _phase: int = 0
var _frames_in_phase: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	print("==================== DROP SELFTEST START ====================")

	_main = MAIN_SCENE.instantiate()
	# test jaldi khatam karne ke liye: 1s me eject, plane bhi map ke andar se
	# (warna turant eject zameen ke bahar gira deta — ocean catch-floor hai par
	# land check map ke andar hi sabse saaf rehta hai)
	_main.auto_eject_time = 1.0
	_main.plane_start = Vector3(-500.0, 300.0, 0.0)
	add_child(_main)
	_player = _main.get_node_or_null("Player")

	_check(_player != null, "player scene me mila")
	if _player == null:
		_finish()
		return
	_check(_player.is_dropping(), "match sky-dive se shuru hota hai (zameen pe nahi)")
	_check(_player.global_position.y > 250.0,
			"player 300m ke aas-paas spawn hua (y=%.1f)" % _player.global_position.y)
	_check(_main.sun != null and not _main.sun.shadow_enabled,
			"drop ke dauran sun shadows band hain (4GB perf)")
	_check(_main.hud != null and _main.hud.drop_panel.visible,
			"HUD pe JUMP OUT drop UI dikh raha hai")

	_set_phase(1)


func _set_phase(p: int) -> void:
	_phase = p
	_frames_in_phase = 0


func _physics_process(_delta: float) -> void:
	_frames_in_phase += 1
	# har phase ka timeout — kuch ataka to RED (kabhi hang nahi)
	if _frames_in_phase > 60 * 20:
		_check(false, "phase %d timeout ho gaya" % _phase)
		_finish()
		return

	match _phase:
		1:  # plane me flight — kuch frame baad eject karo (button wala rasta)
			if _frames_in_phase > 20:
				_check(_player.is_in_plane(), "eject se pehle player plane me hai")
				_check(_player.global_position.y > 250.0, "plane flight me unchaii bani hui hai")
				_main._eject_player()
				_set_phase(2)
		2:  # freefall — chute height ke thoda upar le jao (deploy jaldi trigger ho)
			if _player.is_dropping() and not _player.is_in_plane():
				if _frames_in_phase == 1:
					print("  [INFO] freefall shuru, y=%.1f" % _player.global_position.y)
				if _frames_in_phase > 5:
					_check(not _player.is_in_plane(), "eject ke baad plane ke bahar")
					_check(_player.velocity.y < 0.0, "free-fall me gravity se neeche gir raha hai")
					_player.global_position.y = 52.0   # chute (50m) ke thoda upar
					_set_phase(3)
		3:  # chute deploy ka intezaar
			if _player.drop_state == _player.DropState.PARACHUTE:
				_check(_player.get_node_or_null("Parachute") != null,
						"50m pe parachute mesh lag gaya")
				_player.global_position.y = 14.0       # landing jaldi karao
				_set_phase(4)
		4:  # zameen pe land hone ka intezaar
			if _player.drop_state == _player.DropState.GROUND:
				_check(_player.is_on_floor(), "land karne pe player floor pe hai")
				_check(_player.get_node_or_null("Parachute") == null,
						"land karne pe chhatri hat gayi")
				_check(_player.weapon_holder.visible, "land karne pe gun wapas dikh rahi hai")
				_check(_main.sun.shadow_enabled, "land karne pe shadows wapas on")
				_check(_main.spawn_timer.time_left > 0.0,
						"land karne ke baad dushman spawn shuru")
				Input.action_press("sprint")
				Input.action_press("move_forward")
				_set_phase(5)
		5:  # sprint 50 frames — speed ~10 + FOV upar
			if _frames_in_phase > 50:
				var flat_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
				_check(flat_speed > 8.5, "sprint me speed 10 ke aas-paas hai (%.1f m/s)" % flat_speed)
				_check(_player.camera.fov > 78.0, "sprint me FOV badha hai (%.1f)" % _player.camera.fov)
				Input.action_release("sprint")
				_set_phase(6)
		6:  # sprint chhoda — speed/FOV wapas normal
			if _frames_in_phase > 50:
				var flat_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
				_check(flat_speed < 7.5, "sprint chhodne pe wapas walk speed (%.1f m/s)" % flat_speed)
				_check(_player.camera.fov < 79.0, "sprint chhodne pe FOV wapas normal (%.1f)" % _player.camera.fov)
				Input.action_release("move_forward")
				_finish()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  [PASS] " + label)
	else:
		_failures.append(label)
		print("  [FAIL] " + label)
		push_error("DROP SELFTEST: " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("==================== DROP SELFTEST PASS ====================")
		get_tree().quit(0)
	else:
		print("==================== DROP SELFTEST FAIL (%d) ====================" % _failures.size())
		for f in _failures:
			print("  - " + f)
		get_tree().quit(1)
