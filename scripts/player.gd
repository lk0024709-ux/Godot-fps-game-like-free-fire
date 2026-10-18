extends CharacterBody3D
##
## Player (FPS) + weapon holder
## PC   : WASD chalna, mouse se dekhna, left-click firing, Space jump
##        Q = pichhla gun, E = agla gun, R = reload, 1-9 = seedha gun select,
##        mouse wheel se bhi gun badal sakte ho
## Mobile: left joystick chalna, right half pe swipe se dekhna,
##        FIRE / JUMP / RELOAD / SWAP / GUNS buttons HUD se aate hain
##
## Firing ka poora hisaab weapon_manager.gd ke paas hai (ammo, reload, damage,
## auto/semi, pellets). Player sirf trigger dabaya gaya hai ya nahi wo dekhta hai
## aur bullet spawn karta hai.
##
## APNA BODY (Phase 4): character_data.gd se character chuno -> downloaded OBJ model
## se poora humanoid banta hai. Body render layer 2 pe hai aur camera use nahi dekhta
## (spec: FPS me apna body invisible). Neeche dekhne pe apne
## kapde/arm dikhte hain. Sirf SAR chhupaya jata hai (camera usi ke andar hai).
## Model na mile to kuch nahi lagta — pehle jaisa invisible body (koi error nahi).
##

signal health_changed(health: int)
signal died
## PLANE DROP (Battle Royale start): plane se kudne ke signals
signal ejected                ## plane se kud gaya (free-fall shuru)
signal parachute_opened       ## 50m pe chhatri khul gayi
signal landed                 ## zameen pe land — normal FPS wapas

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const WEAPON_MANAGER := preload("res://scripts/weapon_manager.gd")
const ASSETS := preload("res://scripts/assets.gd")
const CHARACTERS := preload("res://scripts/character_data.gd")

@export_group("Movement")
@export var move_speed: float = 6.0           ## m/s
@export var jump_velocity: float = 4.8
@export var gravity: float = 18.0

@export_group("Sprint")
## PC: Shift dabaye rakho. Mobile: HUD ka SPRINT button (joystick ke paas).
## Sprint me speed 6.0 -> 10.0 m/s, camera FOV 75 -> 85 (smooth lerp), aur
## weapon me halka bob (tezi ka ehsaas).
@export var sprint_speed: float = 10.0        ## sprint me itni speed (normal 6.0)
@export var sprint_fov: float = 85.0          ## sprint me camera FOV (normal 75)
@export var fov_lerp_speed: float = 6.0       ## FOV kitni jaldi smooth badle

@export_group("Plane Drop")
## Battle Royale start: match 300m upar plane me shuru hota hai. Player kudta hai
## (ya 10s me auto-eject), free-fall me steering karta hai, 50m pe chhatri khud
## khul jati hai (fall speed 5 m/s) aur zameen pe land karke normal FPS mil jata hai.
@export var base_fov: float = 75.0            ## normal camera FOV
@export var parachute_height: float = 50.0    ## is height pe parachute khud khulta hai
@export var parachute_fall_speed: float = 5.0 ## parachute ke saath itni dheere girega
@export var parachute_steer_speed: float = 8.0   ## parachute me left/right steering
@export var parachute_decel: float = 60.0     ## chute khulte hi fall speed kitni jaldi kam ho
@export var freefall_terminal: float = 55.0   ## free-fall ki max speed (terminal velocity)
@export var freefall_steer_speed: float = 14.0   ## hawa me gliding steering ki speed
@export var freefall_fov: float = 86.0        ## free-fall me thoda wide FOV (speed feel)
@export var parachute_fov: float = 78.0       ## parachute me halka wide FOV

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var touch_sensitivity: float = 0.005
@export var pitch_limit_deg: float = 85.0
## Camera kitni door tak dekhega (Camera3D.far). Map 2000x2000m hai, isliye
## 3000 rakha hai taaki ek kinare se doosra kinara + samundar dikhe.
@export var camera_far: float = 3000.0

@export_group("Body")
@export var character_index: int = 0          ## kaunsa character (character_data.gd ka index)
@export var show_body: bool = true            ## apna body dikhana hai? (false = invisible FPS body)
@export var name_tag: bool = true             ## sar ke upar naam dikhana hai?

@export_group("Combat")
@export var max_health: int = 100             ## spec: start 100 HP
@export var gun_kick: float = 0.05            ## firing pe gun ka chhota kickback
@export var muzzle_flash_time: float = 0.05

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder

var weapon_manager: Node = null               ## weapon_manager.gd (neeche banta hai)
var health: int = 100
var is_dead: bool = false
var is_firing: bool = false

## PLANE DROP ka state machine (Battle Royale):
##   GROUND    = normal FPS gameplay (chalna/goli)
##   PLANE     = 300m upar plane ke andar — sirf dekh sakte ho, koi movement/shooting
##   FREEFALL  = kud gaye — gravity + horizontal steering (gliding), shooting band
##   PARACHUTE = 50m pe chhatri khuli — fall speed 5 m/s + dheemi steering
enum DropState { GROUND, PLANE, FREEFALL, PARACHUTE }
var drop_state: DropState = DropState.GROUND

var _sprint_requested: bool = false   ## HUD ke SPRINT button se (mobile)
var _is_sprinting_now: bool = false   ## is frame me sach me sprint chal raha hai?
var _bob_phase: float = 0.0           ## weapon bob ka chakkar (sprint me)
var _bob_amount: float = 0.0          ## bob kitna dikhe (0 = band, 1 = pura sprint)
var _parachute: Node3D = null         ## parachute ka procedural mesh (land pe hat jata hai)

# main.gd ye do set karta hai (HUD + bullets ka parent node)
var hud = null
var bullet_parent = null

var _pitch: float = 0.0
var _recoil: float = 0.0
var _kick: float = 0.0
var _holder_base: Vector3 = Vector3.ZERO
var _fire_timer: float = 0.0
var _trigger_ready: bool = true                ## semi-auto: naya press chahiye
var _flash_timer: float = 0.0
var _jump_requested: bool = false
var _look_touch: int = -1
var _is_mobile: bool = false


func _ready() -> void:
	add_to_group("player")
	_setup_input()
	camera.far = camera_far        # bada BR map: horizon door tak dikhe (player.tscn me bhi 3000)
	camera.fov = base_fov          # sprint/drop me ye smooth badlega (sprint_fov etc.)
	health = max_health
	_is_mobile = OS.has_feature("mobile")
	_holder_base = weapon_holder.position

	# apna body (downloaded character model) — camera ke neeche, isliye dekhne pe dikhta hai
	_build_body()

	# WeaponManager banao aur usko apna holder de do
	weapon_manager = WEAPON_MANAGER.new()
	weapon_manager.name = "WeaponManager"
	add_child(weapon_manager)
	weapon_manager.set_holder(weapon_holder)

	# PC pe mouse ko capture karo (ESC se free hota hai)
	if not _is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ------------------------------------------------------------- apna body -----

## Character ka visible body banao (3rd person me bhi kaam aayega).
## Fail-soft: model na mile to kuch nahi hota (body invisible — pehle jaisa game).
func _build_body() -> void:
	if not show_body:
		return
	var data: Dictionary = CHARACTERS.get_character(character_index)
	if data.is_empty():
		return

	var model := ASSETS.build_character_model(
			String(data.get("model", "male_1")),
			data.get("body", Color(0.25, 0.45, 0.70)),
			data.get("accent", Color(0.14, 0.16, 0.22)))
	if model == null:
		return          # asset nahi mila -> procedural fallback = invisible body

	model.name = "Body"
	# NOTE: body me koi collision shape nahi hota (sirf dikhta hai) — player ki apni
	# capsule hi takkar handle karti hai.
	add_child(model)

	if name_tag:
		_add_name_tag(model, CHARACTERS.display_name(character_index))

	# ---- FPS invisibility (spec) ----
	# Body + naam ka tag render layer 2 pe bhejo, aur apne camera ka cull_mask se
	# layer 2 hata do. Matlab: apni body khud ko nahi dikhti (koi first-person me
	# apna sar/chest nahi dekhna chahta), par light/shadow pe asar rehta hai aur
	# koi doosra camera (future third-person) use dekh sakta hai.
	ASSETS.set_render_layer(model, CHARACTERS.PLAYER_BODY_LAYER)
	camera.cull_mask = camera.cull_mask & ~(1 << (CHARACTERS.PLAYER_BODY_LAYER - 1))


## Sar ke upar chhota naam (Label3D) — apne body pe bhi lagta hai taaki agar
## kabhi third-person camera aaye to naam dikhe.
func _add_name_tag(parent: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color(0.95, 0.96, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.06, 0.10, 0.9)
	label.position = Vector3(0.0, ASSETS.CHARACTER_HEIGHT + 0.28, 0.0)
	parent.add_child(label)


## Character badlo (HUD / character-select screen isko call kar sakta hai)
func set_character(index: int) -> void:
	character_index = index
	var old := get_node_or_null("Body")
	if old != null:
		old.queue_free()
	_build_body()


# ------------------------------------------------------------- input setup ---

## Q / E / R / 1-9 / mouse-wheel ko code se hi register karte hain, taaki tumhe
## project.godot me lamba InputMap block copy karne ki zaroorat na pade.
## (Dhyaan do: pehle action banao, phir event add karo — warna event chhoot jayega.)
func _setup_input() -> void:
	_add_key("prev_weapon", KEY_Q)
	_add_key("next_weapon", KEY_E)
	_add_key("reload", KEY_R)
	_add_key("weapon_menu", KEY_G)
	_add_key("sprint", KEY_SHIFT)              # PC sprint (mobile: HUD ka SPRINT button)
	_add_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	for i in 9:
		_add_key("weapon_slot_%d" % (i + 1), KEY_1 + i)


func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ input ----

func _unhandled_input(event: InputEvent) -> void:
	# ---------- PC: mouse se dekhna ----------
	if event is InputEventMouseMotion and not _is_mobile:
		if not is_dead and not _menu_open():
			_rotate_view(event.relative * mouse_sensitivity)
		return

	# ---------- Mobile: screen ke right half pe swipe = look ----------
	if event is InputEventScreenTouch:
		var half_width: float = get_viewport().get_visible_rect().size.x * 0.5
		if event.pressed:
			if not is_dead and not _menu_open() and _look_touch == -1 and event.position.x > half_width:
				_look_touch = event.index
		elif event.index == _look_touch:
			_look_touch = -1
	elif event is InputEventScreenDrag:
		if not is_dead and not _menu_open() and event.index == _look_touch:
			_rotate_view(event.relative * touch_sensitivity)

	# ---------- PC: ESC = mouse free, click = wapas capture ----------
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and not _is_mobile:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			# mouse wapas capture hua to gun-picker band kar do (warna click kaam nahi karega)
			if hud != null and hud.has_method("close_weapon_menu"):
				hud.close_weapon_menu()


## Gun-picker khula hai? Tab firing/look band rehta hai
func _menu_open() -> bool:
	return hud != null and hud.has_method("is_menu_open") and hud.is_menu_open()


func _rotate_view(delta_vec: Vector2) -> void:
	rotate_y(-delta_vec.x)   # left/right -> body ghumti hai
	var limit := deg_to_rad(pitch_limit_deg)
	_pitch = clampf(_pitch - delta_vec.y, -limit, limit)   # up/down -> sir ghumta hai


# ---------------------------------------------------------------- physics ----

func _physics_process(delta: float) -> void:
	_apply_look(delta)

	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# ---- PLANE DROP SEQUENCE (Battle Royale) ----
	# In states me normal movement/firing band hai — alag physics loop chalta hai.
	match drop_state:
		DropState.PLANE:
			velocity = Vector3.ZERO        # plane ke andar — main.gd position set karta hai
			return
		DropState.FREEFALL:
			_process_freefall(delta)
			return
		DropState.PARACHUTE:
			_process_parachute(delta)
			return
		_:
			pass                           # GROUND — neeche purana gameplay loop

	_handle_weapon_input()
	_handle_firing(delta)

	# ---- movement input (keyboard + joystick) ----
	var input_dir := _read_move_input()

	# ---- sprint: Shift (PC) ya SPRINT button (mobile) — zameen pe chalte waqt ----
	var want_sprint: bool = Input.is_action_pressed("sprint") or _sprint_requested
	_is_sprinting_now = want_sprint and is_on_floor() and input_dir.length() > 0.2 \
			and not _menu_open()

	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	# ---- gravity + jump ----
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") or _jump_requested:
		velocity.y = jump_velocity
	_jump_requested = false

	var speed := move_speed
	if _is_sprinting_now:
		speed = sprint_speed               # 6.0 -> 10.0 m/s
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


## Keyboard + joystick ka movement input — ground aur drop dono me use hota hai
func _read_move_input() -> Vector2:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_forward", "move_backward")

	if hud != null:
		var stick: Vector2 = hud.get_move_vector()
		if stick.length_squared() > input_dir.length_squared():
			input_dir = stick
	if input_dir.length() < 0.15:      # dead-zone
		input_dir = Vector2.ZERO
	return input_dir.limit_length(1.0)


# ----------------------------------------------------- plane drop physics ----

## Plane se kudne ke baad ka free-fall: gravity + sirf horizontal steering
func _process_freefall(delta: float) -> void:
	# gravity, par terminal velocity se aage nahi
	velocity.y = maxf(velocity.y - gravity * delta, -freefall_terminal)

	# gliding: WASD / joystick se hawa me idhar-udhar
	var input_dir := _read_move_input()
	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var blend := minf(1.0, delta * 3.0)
	velocity.x = lerpf(velocity.x, direction.x * freefall_steer_speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * freefall_steer_speed, blend)

	move_and_slide()

	if global_position.y <= parachute_height:
		_deploy_parachute()
	elif is_on_floor():
		_land()                            # parachute ke bina hi zameen mil gayi — phir bhi safe


## Parachute khula: fall speed 5 m/s + dheemi steering, zameen pe land
func _process_parachute(delta: float) -> void:
	# tez girte hue chute khuli -> fall speed smooth ho kar 5 m/s pe settle
	velocity.y = move_toward(velocity.y, -parachute_fall_speed, parachute_decel * delta)

	var input_dir := _read_move_input()
	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var blend := minf(1.0, delta * 4.0)
	velocity.x = lerpf(velocity.x, direction.x * parachute_steer_speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * parachute_steer_speed, blend)

	move_and_slide()
	_animate_parachute(delta)

	if is_on_floor():
		_land()


## Camera ka pitch + recoil har frame lagana
func _apply_look(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 1.6)
	var limit := deg_to_rad(pitch_limit_deg)
	head.rotation = Vector3(clampf(_pitch + _recoil, -limit, limit), 0.0, 0.0)

	# gun ka kickback (peeche + thoda upar + muzzle upar uthta hai)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	weapon_holder.position = _holder_base + Vector3(0.0, 0.012 * _kick, gun_kick * _kick)
	weapon_holder.rotation = Vector3(deg_to_rad(-4.0 * _kick), 0.0, 0.0)

	# muzzle flash on/off
	if _flash_timer > 0.0:
		_flash_timer -= delta
	if weapon_manager != null and is_instance_valid(weapon_manager) and weapon_manager.muzzle != null:
		weapon_manager.muzzle.visible = _flash_timer > 0.0

	_update_camera_fov(delta)
	_update_weapon_bob(delta)


## Camera FOV smooth lerp: sprint me 75 -> 85, rukte hi wapas 75.
## Free-fall/parachute me bhi thoda wide FOV (speed ka feel).
func _update_camera_fov(delta: float) -> void:
	var target := base_fov
	match drop_state:
		DropState.FREEFALL:
			target = freefall_fov
		DropState.PARACHUTE:
			target = parachute_fov
		_:
			if _is_sprinting_now:
				target = sprint_fov
	camera.fov = lerpf(camera.fov, target, minf(1.0, delta * fov_lerp_speed))


## Sprint ke waqt weapon me halka bob/sway (tezi ka ehsaas), rukte hi shant
func _update_weapon_bob(delta: float) -> void:
	var bob_target := 1.0 if _is_sprinting_now else 0.0
	_bob_amount = move_toward(_bob_amount, bob_target, delta * 4.0)
	if _bob_amount <= 0.001:
		return
	_bob_phase += delta * 11.0
	var offset := Vector3(sin(_bob_phase) * 0.035, absf(cos(_bob_phase)) * -0.03, 0.0)
	weapon_holder.position += offset * _bob_amount                 # side-to-side + up-down
	weapon_holder.rotation.z = deg_to_rad(sin(_bob_phase) * 2.2) * _bob_amount   # halka tilt


# ----------------------------------------------- parachute (procedural) ------

## 50m pe chhatri khul gayi — wide cone + 4 ropes, sab EXTREMELY low-poly
## (8-side cone, koi texture nahi, shadow off — 4GB RAM perf ke liye).
func _deploy_parachute() -> void:
	if drop_state != DropState.FREEFALL:
		return
	drop_state = DropState.PARACHUTE
	_build_parachute()
	parachute_opened.emit()


func _build_parachute() -> void:
	_remove_parachute()
	var root := Node3D.new()
	root.name = "Parachute"

	# ---- canopy: ulta cone (top radius bada, niche patla) ----
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.85, 0.22, 0.16)   # Free Fire style lal chhatri
	canopy_mat.roughness = 1.0
	canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # niche se dekhne pe bhi dikhe
	var canopy := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 3.2
	cone.bottom_radius = 0.12
	cone.height = 1.5
	cone.radial_segments = 8        # low-poly: 8 side hi kaafi hain
	cone.rings = 0
	cone.material = canopy_mat
	canopy.mesh = cone
	canopy.position = Vector3(0.0, 3.6, 0.0)
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(canopy)

	# ---- 4 patli ropes: canopy se kandho tak ----
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.12, 0.12, 0.14)
	rope_mat.roughness = 1.0
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var rope := MeshInstance3D.new()
		var rope_box := BoxMesh.new()
		rope_box.size = Vector3(0.035, 1.7, 0.035)
		rope_box.material = rope_mat
		rope.mesh = rope_box
		rope.position = Vector3(dir.x * 1.35, 2.1, dir.z * 1.35)
		rope.rotation = Vector3(dir.z * 0.75, 0.0, -dir.x * 0.75)   # bahar ki taraf jhuka
		rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rope)

	# chhota se shuru hoga aur _animate_parachute me khulta dikhega (pop-in)
	root.scale = Vector3(0.25, 0.25, 0.25)
	add_child(root)
	_parachute = root


func _remove_parachute() -> void:
	if _parachute != null and is_instance_valid(_parachute):
		_parachute.queue_free()
	_parachute = null


## Chhatri ka chhota pop-in + hawa me halka sway
func _animate_parachute(delta: float) -> void:
	if _parachute == null or not is_instance_valid(_parachute):
		return
	var s := lerpf(_parachute.scale.x, 1.0, minf(1.0, delta * 6.0))
	_parachute.scale = Vector3(s, s, s)
	var t := Time.get_ticks_msec() / 1000.0
	_parachute.rotation = Vector3(cos(t * 1.7) * 0.05, 0.0, sin(t * 2.1) * 0.06)


## Zameen pe land: chhatri hatao, normal FPS (shooting + movement) wapas
func _land() -> void:
	if drop_state == DropState.GROUND:
		return
	drop_state = DropState.GROUND
	velocity.y = 0.0
	_remove_parachute()
	weapon_holder.visible = true
	_is_sprinting_now = false
	landed.emit()


# -------------------------------------------------------------- weapon keys --

func _handle_weapon_input() -> void:
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return
	if Input.is_action_just_pressed("next_weapon"):
		weapon_manager.next_weapon()
	if Input.is_action_just_pressed("prev_weapon"):
		weapon_manager.prev_weapon()
	if Input.is_action_just_pressed("reload"):
		weapon_manager.start_reload()
	if Input.is_action_just_pressed("weapon_menu") and hud != null and hud.has_method("toggle_weapon_menu"):
		hud.toggle_weapon_menu()
	for i in 9:                                  # 1-9 = seedha weapon select
		if Input.is_action_just_pressed("weapon_slot_%d" % (i + 1)):
			weapon_manager.switch_weapon(i)


# ---------------------------------------------------- bahar ke liye helpers --
# HUD / future systems inhe call kar sakte hain (poora kaam weapon_manager karta hai)

func switch_weapon_next() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.next_weapon()


# ------------------------------------------- plane drop (main.gd call karta) -

## Kya drop sequence chal raha hai (plane/freefall/parachute — zameen pe nahi)?
func is_dropping() -> bool:
	return drop_state != DropState.GROUND


## Player abhi plane ke andar hai?
func is_in_plane() -> bool:
	return drop_state == DropState.PLANE


## Match start: main.gd isko call karta hai — player 300m upar plane me baithta hai.
## Shooting aur ground movement band, sirf look-around chalta hai.
func begin_plane_drop() -> void:
	drop_state = DropState.PLANE
	velocity = Vector3.ZERO
	is_firing = false
	_is_sprinting_now = false
	_bob_amount = 0.0
	_remove_parachute()
	weapon_holder.visible = false          # skydive me gun chhupi rehti hai


## Plane se bahar kudo (JUMP OUT button / Space / auto-eject)
func eject_from_plane() -> void:
	if drop_state != DropState.PLANE:
		return
	drop_state = DropState.FREEFALL
	velocity = Vector3(0.0, -2.0, 0.0)
	_jump_requested = false
	ejected.emit()


## Mobile HUD: SPRINT button press/release yahan aata hai
func set_sprint_requested(active: bool) -> void:
	_sprint_requested = active


func switch_weapon_prev() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.prev_weapon()


func switch_weapon_idx(index: int) -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.switch_weapon(index)


func get_weapon_index() -> int:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		return weapon_manager.current_index
	return 0


# ---------------------------------------------------------------- shooting ---

func _handle_firing(delta: float) -> void:
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return

	if _menu_open():
		is_firing = false
		_trigger_ready = true
		return

	# PC: left click / Enter. Mobile: FIRE button (start_firing/stop_firing)
	var wants_fire: bool = is_firing
	if not _is_mobile:
		if Input.is_action_just_pressed("fire"):
			_trigger_ready = true
		if Input.is_action_pressed("fire"):
			wants_fire = true

	if not wants_fire:
		if not weapon_manager.is_auto():
			_fire_timer = 0.0        # semi-auto: naya press turant chalega
		return

	# auto weapon: dabaye rakhne pe lagatar. semi: har press pe ek goli.
	if not weapon_manager.is_auto() and not _trigger_ready:
		return

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		shoot()


func shoot() -> void:
	if is_dead or bullet_parent == null or not is_instance_valid(bullet_parent):
		return
	if drop_state != DropState.GROUND:     # plane/freefall/parachute me firing band
		return
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return

	if not weapon_manager.can_shoot():
		if not weapon_manager.reloading:
			weapon_manager.start_reload()     # magazine khali -> auto reload
		return

	var weapon: Dictionary = weapon_manager.get_current()
	var pellets: int = maxi(1, int(weapon.get("pellets", 1)))
	var damage: float = float(weapon.get("damage", 10.0))
	var speed: float = float(weapon.get("bullet_speed", 26.0))
	var spread: float = float(weapon.get("spread", 0.6))

	# Camera se aage ki direction
	var aim: Vector3 = -camera.global_transform.basis.z.normalized()
	for i in pellets:
		_spawn_bullet(aim, spread, damage, speed)   # shotgun -> ek saath kai goliyaan

	weapon_manager.consume_ammo()
	_fire_timer = weapon_manager.get_fire_delay()
	_trigger_ready = false

	# recoil (weapon ke hisaab se) + muzzle flash + halki vibration
	var recoil_deg: float = float(weapon.get("recoil", 1.0))
	_recoil += deg_to_rad(recoil_deg)
	_kick = minf(1.5, recoil_deg)
	_flash_timer = muzzle_flash_time
	Input.vibrate_handheld(25)


func _spawn_bullet(aim: Vector3, spread_deg: float, damage: float, speed: float) -> void:
	var dir := aim
	if spread_deg > 0.0:
		var spread := deg_to_rad(spread_deg)
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
		dir = dir.rotated(camera.global_transform.basis.x, randf_range(-spread, spread))
		dir = dir.normalized()

	var bullet = BULLET_SCENE.instantiate()
	bullet.direction = dir
	bullet.speed = speed
	bullet.damage = damage
	bullet.shooter = self
	bullet_parent.add_child(bullet)
	bullet.global_position = camera.global_position + dir * 0.9
	bullet.face_direction()


# ---------------------------------------------------- HUD se aane wale calls -

func start_firing() -> void:
	if is_dead or _menu_open():
		return
	if drop_state != DropState.GROUND:     # plane/freefall/parachute me firing band
		return
	is_firing = true
	_trigger_ready = true      # pehli goli turant (semi-auto ke liye zaroori)
	_fire_timer = 0.0


func stop_firing() -> void:
	is_firing = false


func request_jump() -> void:
	if not is_dead and drop_state == DropState.GROUND:
		_jump_requested = true


# ------------------------------------------------------------------ damage ---

func take_damage(amount: int) -> void:
	if is_dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health)
	Input.vibrate_handheld(80)
	if hud != null and hud.has_method("flash_damage"):
		hud.flash_damage()
	if health <= 0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_firing = false
	velocity = Vector3.ZERO
	_remove_parachute()
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.cancel_reload()
	if not _is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # restart button click ho sake
	died.emit()
