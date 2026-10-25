extends CanvasLayer
##
## HUD — Pro Battle Royale Mobile Interface ("Rannbhoomi" Edition)
##
## Layout:
##   - Top-Left:     `MinimapPanel` (`rannbhoomi_minimap.png` + rotating `PlayerArrow` + live POI)
##   - Top-Center:   `CompassBar` (`N / NE / E / SE / S / SW / W / NW` + degree bearing)
##   - Top-Right:    `ScoreLabel` + equipped `WeaponLabel` / `AmmoLabel` + `SwapButton` / `GunsButton`
##   - Bottom-Left:  Dynamic `Joystick` + `BackpackButton` + `HealButton` + `SprintButton`
##   - Bottom-Center: Stacked `EPBar` (`EPLabel`) + `HealthBar` (`HealthLabel`)
##   - Bottom-Right: Large `FireButton` + `AimButton`, `JumpButton`, `CrouchButton`, `ReloadButton`
##   - Drop Overlay: Prominent `EjectPanel/EjectButton` + 15.0s countdown + live altitude banner
##
## Every non-interactive Control node strictly enforces `Control.MOUSE_FILTER_IGNORE` so
## multi-touch works simultaneously across movement, shooting, aiming, crouching, and camera drag.
##

signal fire_pressed
signal fire_released
signal jump_pressed
signal aim_toggled(active: bool)
signal crouch_toggled(active: bool)
signal sprint_changed(active: bool)
signal heal_pressed
signal eject_pressed
signal restart_pressed

const FULL_MAP_TEXTURE: Texture2D = preload("res://assets/ui/rannbhoomi_minimap.png")

@export var show_touch_controls_on_desktop: bool = true

@onready var hit_flash: ColorRect = $HitFlash
@onready var crosshair: Control = $Crosshair

# Top-Left: RANNBHOOMI Minimap + Rotating Arrow
@onready var minimap_panel: Control = $MinimapPanel
@onready var minimap_view: Control = $MinimapPanel/MinimapView
@onready var minimap_zone_label: Label = $MinimapPanel/MinimapZoneLabel

# Top-Center: Compass
@onready var compass_bar: Control = $CompassBar
@onready var drop_status_banner: ColorRect = $DropStatusBanner
@onready var drop_status_label: Label = $DropStatusBanner/DropStatusLabel

# Top-Right: Score & Weapon readout
@onready var score_label: Label = $ScoreLabel
@onready var alive_label: Label = $AliveLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var ammo_label: Label = $AmmoLabel

# Bottom-Center: EP & HP Bars
@onready var ep_bar: ProgressBar = $EPBar
@onready var ep_label: Label = $EPLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel

# Touch Controls (Bottom-Left + Bottom-Right + Top-Right quick swap)
@onready var touch_controls: Control = $TouchControls
@onready var joystick: Control = $TouchControls/Joystick
@onready var backpack_button: Control = $TouchControls/BackpackButton
@onready var heal_button: Control = $TouchControls/HealButton
@onready var sprint_button: Control = $TouchControls/SprintButton
@onready var fire_button: Control = $TouchControls/FireButton
@onready var aim_button: Control = $TouchControls/AimButton
@onready var jump_button: Control = $TouchControls/JumpButton
@onready var reload_button: Control = $TouchControls/ReloadButton
@onready var crouch_button: Control = $TouchControls/CrouchButton
@onready var swap_button: Control = $TouchControls/SwapButton
@onready var guns_button: Control = $TouchControls/GunsButton
@onready var map_expand_button: Control = $TouchControls/MapExpandButton

# Drop Eject UI
@onready var eject_panel: Control = $EjectPanel
@onready var eject_countdown_label: Label = $EjectPanel/EjectCountdownLabel
@onready var eject_button: Control = $EjectPanel/EjectButton

# Game Over
@onready var game_over_panel: Control = $GameOverPanel
@onready var game_over_title: Label = $GameOverPanel/Box/Title
@onready var final_score_label: Label = $GameOverPanel/Box/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/Box/RestartButton

var weapon_menu: Control = null
var full_map_modal: Control = null

var _weapon_manager = null
var _weapon_buttons: Array[Button] = []
var _bag_summary_label: Label = null
var _flash_alpha: float = 0.0
var _flash_color: Color = Color(0.92, 0.12, 0.12)
var _landed_banner_timer: float = 0.0

var _max_health: int = 200
var _cur_health: int = 200
var _max_ep: int = 100
var _cur_ep: int = 100
var _medkits: int = 5
var _drop_state: int = 3
var _drop_countdown: float = 15.0
var _aim_active: bool = false
var _crouch_active: bool = false
var _sprint_active: bool = false
var _player_altitude: float = 16.0


func _ready() -> void:
	var has_touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch_controls.visible = has_touch or show_touch_controls_on_desktop

	# Bottom-Right Combat Buttons
	fire_button.pressed.connect(func() -> void: fire_pressed.emit())
	fire_button.released.connect(func() -> void: fire_released.emit())
	jump_button.pressed.connect(func() -> void: jump_pressed.emit())
	aim_button.pressed.connect(_on_aim_button_pressed)
	crouch_button.pressed.connect(_on_crouch_button_pressed)
	reload_button.pressed.connect(_on_reload_pressed)

	# Bottom-Left Utility Buttons
	backpack_button.pressed.connect(toggle_weapon_menu)
	heal_button.pressed.connect(func() -> void: heal_pressed.emit())
	sprint_button.mouse_filter = Control.MOUSE_FILTER_STOP
	sprint_button.pivot_offset = sprint_button.size * 0.5
	sprint_button.pressed.connect(_on_run_button_pressed)
	set_sprint_active(false)

	# Quick Swap / Armory / Full Map / Eject / Restart
	swap_button.pressed.connect(_on_swap_pressed)
	guns_button.pressed.connect(toggle_weapon_menu)
	map_expand_button.pressed.connect(toggle_full_map)
	eject_button.pressed.connect(func() -> void: eject_pressed.emit())
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())

	game_over_panel.visible = false
	hit_flash.color.a = 0.0

	_build_full_map_modal()
	_enforce_non_interactive_mouse_filters()


func _process(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = move_toward(_flash_alpha, 0.0, delta * 1.6)
		hit_flash.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_alpha)

	if _landed_banner_timer > 0.0:
		_landed_banner_timer -= delta
		if _landed_banner_timer <= 0.0 and _drop_state == 3:
			drop_status_banner.visible = false


## Recursively guarantees every non-interactive Control node has MOUSE_FILTER_IGNORE
## so multi-touch controls never get blocked by decorative bars, labels, or frames.
func _enforce_non_interactive_mouse_filters() -> void:
	var interactive_nodes := {
		joystick: true,
		backpack_button: true,
		heal_button: true,
		sprint_button: true,
		fire_button: true,
		aim_button: true,
		jump_button: true,
		reload_button: true,
		crouch_button: true,
		swap_button: true,
		guns_button: true,
		map_expand_button: true,
		eject_button: true,
		restart_button: true,
	}
	for child in get_children():
		if child == weapon_menu or child == full_map_modal:
			continue
		if child is Control:
			_apply_mouse_filter_tree(child as Control, interactive_nodes)


func _apply_mouse_filter_tree(node: Control, interactive_nodes: Dictionary) -> void:
	if node == game_over_panel or node.name == "Shade":
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	elif interactive_nodes.has(node) or node is Button or node is ScrollContainer:
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():
		if child is Control:
			_apply_mouse_filter_tree(child as Control, interactive_nodes)


# ===================================================== LIVE TELEMETRY UPDATE ==

func update_tactical_hud(
	player_xz: Vector2,
	player_yaw: float,
	altitude_y: float,
	poi_name: String,
	enemy_positions: Array[Vector2],
	has_plane: bool,
	plane_xz: Vector2,
	route_start: Vector2,
	route_end: Vector2
) -> void:
	_player_altitude = altitude_y
	if compass_bar != null and compass_bar.has_method("set_from_yaw"):
		compass_bar.set_from_yaw(player_yaw)

	if minimap_view != null and minimap_view.has_method("update_radar"):
		minimap_view.update_radar(
			player_xz,
			player_yaw,
			_drop_state == 0,
			enemy_positions,
			has_plane,
			plane_xz,
			route_start,
			route_end
		)

	if minimap_zone_label != null:
		minimap_zone_label.text = "RANNBHOOMI · %s" % poi_name

	_refresh_drop_banner()


func set_drop_state(state: int) -> void:
	_drop_state = state
	var in_plane := state == 0
	var airborne := state != 3

	eject_panel.visible = in_plane
	fire_button.visible = not airborne
	aim_button.visible = not airborne
	reload_button.visible = not airborne
	crouch_button.visible = not airborne
	crosshair.visible = not in_plane

	if state == 3:
		_landed_banner_timer = 2.4
		drop_status_banner.visible = true
		drop_status_label.text = "TOUCHDOWN · WELCOME TO RANNBHOOMI!"
	else:
		_landed_banner_timer = 0.0
		drop_status_banner.visible = true
		_refresh_drop_banner()


func set_drop_countdown(seconds_left: float) -> void:
	_drop_countdown = maxf(0.0, seconds_left)
	if eject_countdown_label != null:
		eject_countdown_label.text = "AUTO EJECT IN %.1fs" % _drop_countdown
	_refresh_drop_banner()


func _refresh_drop_banner() -> void:
	if drop_status_label == null or not drop_status_banner.visible:
		return
	match _drop_state:
		0:
			drop_status_label.text = "ELITE CARGO PLANE · ALT %.0fm · 50 m/s" % _player_altitude
		1:
			drop_status_label.text = "FREEFALL · ALT %.0fm (PARACHUTE @ 50m)" % _player_altitude
		2:
			drop_status_label.text = "PARACHUTE DEPLOYED · ALT %.0fm (5.0 m/s)" % _player_altitude


# ===================================================== VITALS & COMBAT STATE ==

func set_max_health(max_hp: int) -> void:
	_max_health = maxi(1, max_hp)
	health_bar.max_value = _max_health
	set_health(_cur_health)


func set_health(hp: int) -> void:
	_cur_health = clampi(hp, 0, _max_health)
	health_bar.value = _cur_health
	health_label.text = "HP  %d / %d" % [_cur_health, _max_health]
	var fill := health_bar.get("theme_override_styles/fill") as StyleBoxFlat
	if fill != null:
		if _cur_health > int(round(_max_health * 0.55)):
			fill.bg_color = Color(0.18, 0.88, 0.45, 0.96)
		elif _cur_health > int(round(_max_health * 0.28)):
			fill.bg_color = Color(0.96, 0.68, 0.16, 0.96)
		else:
			fill.bg_color = Color(0.94, 0.22, 0.20, 0.96)
	_refresh_backpack_summary()


func set_max_ep(max_ep_val: int) -> void:
	_max_ep = maxi(1, max_ep_val)
	ep_bar.max_value = _max_ep
	set_ep(_cur_ep)


func set_ep(ep_val: int) -> void:
	_cur_ep = clampi(ep_val, 0, _max_ep)
	ep_bar.value = _cur_ep
	ep_label.text = "EP  %d / %d" % [_cur_ep, _max_ep]
	_refresh_backpack_summary()


func set_medkits(count: int) -> void:
	_medkits = maxi(0, count)
	heal_button.set_badge(str(_medkits))
	_refresh_backpack_summary()


func set_aim_active(active: bool) -> void:
	_aim_active = active
	aim_button.set_active_highlight(active)
	crosshair.scale = Vector2(0.66, 0.66) if active else Vector2.ONE


func set_crouch_active(active: bool) -> void:
	_crouch_active = active
	crouch_button.set_active_highlight(active)


func set_sprint_active(active: bool) -> void:
	_sprint_active = active
	sprint_button.set_active_highlight(active)
	sprint_button.modulate = Color(0.80, 1.0, 0.55, 1.0) if active else Color.WHITE
	sprint_button.scale = Vector2(1.08, 1.08) if active else Vector2.ONE
	sprint_button.queue_redraw()


func set_score(score: int) -> void:
	score_label.text = "SCORE: %d" % score


func set_alive_players(count: int) -> void:
	alive_label.text = "PLAYERS ALIVE: %d" % count


func flash_damage() -> void:
	_flash_color = Color(0.92, 0.12, 0.10)
	_flash_alpha = 0.45
	hit_flash.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_alpha)


func flash_heal() -> void:
	_flash_color = Color(0.16, 0.92, 0.48)
	_flash_alpha = 0.30
	hit_flash.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_alpha)


func get_move_vector() -> Vector2:
	if not touch_controls.visible:
		return Vector2.ZERO
	return joystick.output


func _on_aim_button_pressed() -> void:
	aim_toggled.emit(not _aim_active)


func _on_crouch_button_pressed() -> void:
	crouch_toggled.emit(not _crouch_active)


func _on_run_button_pressed() -> void:
	# TouchButton.release only ends the finger press; RUN remains toggled until next tap.
	set_sprint_active(not _sprint_active)
	sprint_changed.emit(_sprint_active)


# ============================================================ WEAPONS & BAG ===

func bind_weapon_manager(wm) -> void:
	_weapon_manager = wm
	wm.weapon_changed.connect(_on_weapon_changed)
	wm.ammo_changed.connect(_on_ammo_changed)
	wm.reload_started.connect(_on_reload_started)
	wm.reload_finished.connect(_on_reload_finished)
	wm.index_changed.connect(_on_index_changed)

	_build_weapon_menu()

	var current: Dictionary = wm.get_current()
	if not current.is_empty():
		_on_weapon_changed(String(current.get("name", "")), wm.current_ammo, wm.get_ammo_max())
		_on_index_changed(wm.current_index)


func _on_weapon_changed(wname: String, ammo: int, ammo_max: int) -> void:
	weapon_label.text = wname.to_upper()
	ammo_label.text = "%d / %d" % [ammo, ammo_max]
	_refresh_backpack_summary()


func _on_index_changed(index: int) -> void:
	for i in _weapon_buttons.size():
		_weapon_buttons[i].button_pressed = (i == index)


func _on_ammo_changed(current: int) -> void:
	var mag := 30
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		mag = int(_weapon_manager.get_ammo_max())
	ammo_label.text = "%d / %d" % [current, mag]


func _on_reload_started(_duration: float) -> void:
	ammo_label.text = "RELOADING..."


func _on_reload_finished() -> void:
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		_on_ammo_changed(int(_weapon_manager.current_ammo))


func _on_swap_pressed() -> void:
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		_weapon_manager.next_weapon()


func _on_reload_pressed() -> void:
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		_weapon_manager.start_reload()


func is_menu_open() -> bool:
	var bag_open := weapon_menu != null and weapon_menu.visible
	var map_open := full_map_modal != null and full_map_modal.visible
	return bag_open or map_open


func toggle_weapon_menu() -> void:
	if weapon_menu == null:
		return
	if full_map_modal != null and full_map_modal.visible:
		full_map_modal.visible = false
	weapon_menu.visible = not weapon_menu.visible
	backpack_button.set_active_highlight(weapon_menu.visible)
	_sync_cursor_visibility()


func toggle_full_map() -> void:
	if full_map_modal == null:
		return
	if weapon_menu != null and weapon_menu.visible:
		weapon_menu.visible = false
		backpack_button.set_active_highlight(false)
	full_map_modal.visible = not full_map_modal.visible
	map_expand_button.set_active_highlight(full_map_modal.visible)
	_sync_cursor_visibility()


func _sync_cursor_visibility() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name().contains("headless"):
		return
	if is_menu_open():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_backpack_summary() -> void:
	if _bag_summary_label == null:
		return
	var wname := weapon_label.text
	_bag_summary_label.text = "EQUIPPED: %s   |   MEDKITS: %d   |   HP: %d/%d   |   EP: %d/%d" % [
		wname, _medkits, _cur_health, _max_health, _cur_ep, _max_ep
	]


func _build_weapon_menu() -> void:
	if weapon_menu != null:
		weapon_menu.queue_free()
	_weapon_buttons.clear()

	weapon_menu = Control.new()
	weapon_menu.name = "WeaponMenu"
	weapon_menu.visible = false
	weapon_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(weapon_menu)
	move_child(weapon_menu, game_over_panel.get_index())

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.05, 0.09, 0.80)
	weapon_menu.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	weapon_menu.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	var title := Label.new()
	title.text = "BACKPACK & ARMORY (%d WEAPONS)" % _weapon_manager.get_weapon_count()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.36))
	header.add_child(title)

	var quick_heal := Button.new()
	quick_heal.text = "USE MEDKIT (+40 HP)"
	quick_heal.custom_minimum_size = Vector2(180, 42)
	quick_heal.pressed.connect(func() -> void: heal_pressed.emit())
	header.add_child(quick_heal)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(110, 42)
	close_btn.pressed.connect(toggle_weapon_menu)
	header.add_child(close_btn)

	_bag_summary_label = Label.new()
	_bag_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_summary_label.add_theme_font_size_override("font_size", 14)
	_bag_summary_label.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
	vbox.add_child(_bag_summary_label)
	_refresh_backpack_summary()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	for i in _weapon_manager.get_weapon_count():
		var w: Dictionary = _weapon_manager.weapons[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%d. %s\n[%s] DMG %.0f" % [
			i + 1,
			String(w.get("name", "")),
			String(w.get("category", "")).to_upper(),
			float(w.get("damage", 10.0)),
		]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 13)
		var slot: int = i
		btn.pressed.connect(func() -> void: _pick_weapon(slot))
		grid.add_child(btn)
		_weapon_buttons.append(btn)


func _build_full_map_modal() -> void:
	full_map_modal = Control.new()
	full_map_modal.name = "FullMapModal"
	full_map_modal.visible = false
	full_map_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(full_map_modal)
	move_child(full_map_modal, game_over_panel.get_index())

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.08, 0.86)
	full_map_modal.add_child(shade)

	var map_tex := TextureRect.new()
	map_tex.name = "RannbhoomiFullMap"
	map_tex.texture = FULL_MAP_TEXTURE
	map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_tex.set_anchors_preset(Control.PRESET_CENTER)
	map_tex.offset_left = -310.0
	map_tex.offset_top = -310.0
	map_tex.offset_right = 310.0
	map_tex.offset_bottom = 310.0
	map_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_map_modal.add_child(map_tex)

	var close_btn := Button.new()
	close_btn.text = "CLOSE MAP"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -164.0
	close_btn.offset_top = 24.0
	close_btn.offset_right = -28.0
	close_btn.offset_bottom = 66.0
	close_btn.pressed.connect(toggle_full_map)
	full_map_modal.add_child(close_btn)


func _pick_weapon(index: int) -> void:
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		_weapon_manager.switch_weapon(index)
	if weapon_menu != null:
		weapon_menu.visible = false
		backpack_button.set_active_highlight(false)
	_sync_cursor_visibility()


func show_game_over(score: int) -> void:
	if weapon_menu != null:
		weapon_menu.visible = false
	if full_map_modal != null:
		full_map_modal.visible = false
	eject_panel.visible = false
	drop_status_banner.visible = false
	game_over_title.text = "ELIMINATED"
	game_over_title.add_theme_font_size_override("font_size", 44)
	game_over_title.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	final_score_label.text = "FINAL SCORE: %d" % score
	game_over_panel.visible = true


func show_winner(score: int) -> void:
	show_game_over(score)
	game_over_title.text = "WINNER WINNER\nCHICKEN DINNER"
	game_over_title.add_theme_font_size_override("font_size", 32)
	game_over_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.24))
