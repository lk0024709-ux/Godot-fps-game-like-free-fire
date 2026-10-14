extends CanvasLayer
##
## HUD
## - Crosshair (beech me), Health bar (upar baayein), Score (upar daayein)
## - Weapon name (font 26) + ammo "12 / 30" (font 40) bottom-right
## - Mobile touch controls: joystick (bottom-left), FIRE / JUMP / RELOAD / SWAP / GUNS
## - GUNS button se poora weapon-picker khulta hai (28 guns, skin colour ke saath)
## - Game over panel + "TAP TO RESTART"
##
## HUD khud shooting nahi karta — weapon ka kaam weapon_manager.gd dekhta hai,
## HUD sirf uske signals sunta hai aur dikhata hai.
##

signal fire_pressed
signal fire_released
signal jump_pressed
signal restart_pressed

const DATA := preload("res://scripts/weapon_data.gd")

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var score_label: Label = $ScoreLabel
@onready var hint_label: Label = $HintLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var touch_controls: Control = $TouchControls
@onready var joystick = $TouchControls/Joystick          # joystick.gd wala
@onready var fire_button: Control = $TouchControls/FireButton        # touch_button.gd wala
@onready var jump_button: Control = $TouchControls/JumpButton        # touch_button.gd wala
@onready var reload_button: Control = $TouchControls/ReloadButton    # touch_button.gd wala
@onready var swap_button: Control = $TouchControls/SwapButton        # touch_button.gd wala
@onready var guns_button: Control = $TouchControls/GunsButton        # touch_button.gd wala
@onready var weapon_panel: Control = $WeaponPanel
@onready var weapon_grid: GridContainer = $WeaponPanel/WeaponGrid
@onready var panel_title: Label = $WeaponPanel/PanelTitle
@onready var close_button: Button = $WeaponPanel/CloseButton
@onready var game_over_panel: Control = $GameOverPanel
@onready var dim: ColorRect = $GameOverPanel/Dim
@onready var final_score_label: Label = $GameOverPanel/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/RestartButton
@onready var damage_flash: ColorRect = $DamageFlash

var weapon_manager: Node = null          ## main.gd bind_weapon_manager() se set karta hai

var _restarting: bool = false
var _ammo_max: int = 0
var _weapon_buttons: Array[Button] = []


func _ready() -> void:
	health_bar.max_value = 100.0
	set_health(100)
	set_score(0)
	game_over_panel.visible = false
	weapon_panel.visible = false

	damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	weapon_label.text = "—"
	ammo_label.text = "— / —"

	# Touch controls sirf touch-screen (mobile) pe dikhao
	touch_controls.visible = DisplayServer.is_touchscreen_available()

	# Touch buttons ke signals (ye custom control hai jo raw touch handle karta hai)
	fire_button.pressed.connect(_on_fire_button_down)
	fire_button.released.connect(_on_fire_button_up)
	jump_button.pressed.connect(_on_jump_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	swap_button.pressed.connect(_on_swap_button_pressed)
	guns_button.pressed.connect(_on_guns_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	close_button.pressed.connect(close_weapon_menu)

	# Game over panel pe kahin bhi tap karo -> restart (touch pe pakka kaam karta hai)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input)

	# 8 second baad hint hata do
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(hint_label, "modulate:a", 0.0, 1.5)


# ==================================================== weapon system se jodna ==

## main.gd isko call karta hai: hud.bind_weapon_manager(player.weapon_manager)
func bind_weapon_manager(manager: Node) -> void:
	weapon_manager = manager
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return

	weapon_manager.weapon_changed.connect(_on_weapon_changed)
	weapon_manager.ammo_changed.connect(_on_ammo_changed)
	weapon_manager.reload_started.connect(_on_reload_started)
	weapon_manager.reload_finished.connect(_on_reload_finished)
	weapon_manager.index_changed.connect(_on_weapon_index_changed)

	_build_weapon_grid()
	_on_weapon_changed(weapon_manager.get_current_name(), weapon_manager.current_ammo,
			weapon_manager.get_ammo_max())


func _on_weapon_changed(weapon_name: String, ammo: int, ammo_max: int) -> void:
	_ammo_max = ammo_max
	weapon_label.text = weapon_name
	ammo_label.modulate = Color(1, 1, 1)
	ammo_label.text = "%d / %d" % [ammo, ammo_max]


func _on_ammo_changed(ammo: int) -> void:
	ammo_label.text = "%d / %d" % [ammo, _ammo_max]


func _on_reload_started(_reload_time: float) -> void:
	ammo_label.modulate = Color(1.0, 0.75, 0.35)
	ammo_label.text = "RELOADING"


func _on_reload_finished() -> void:
	ammo_label.modulate = Color(1, 1, 1)
	if weapon_manager != null and is_instance_valid(weapon_manager):
		ammo_label.text = "%d / %d" % [weapon_manager.current_ammo, _ammo_max]


func _on_weapon_index_changed(index: int) -> void:
	for i in _weapon_buttons.size():
		if i == index:
			_weapon_buttons[i].modulate = Color(1.0, 0.95, 0.55)     # current gun highlight
		else:
			_weapon_buttons[i].modulate = Color(0.72, 0.72, 0.72)


# ==================================================== gun-picker (28 guns) ==

func _build_weapon_grid() -> void:
	for child in weapon_grid.get_children():
		weapon_grid.remove_child(child)
		child.queue_free()
	_weapon_buttons.clear()
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return

	var list: Array = weapon_manager.weapons
	for i in list.size():
		var weapon: Dictionary = list[i]
		var button := Button.new()
		var tag := DATA.short_tag(String(weapon.get("shape", "rifle")))
		button.text = "[%s] %s" % [tag, String(weapon.get("name", "?"))]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(210, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)

		# Skin colour ko button ke background me dikhao (koi image nahi, sirf StyleBoxFlat)
		var body_color: Color = weapon.get("body", Color(0.2, 0.2, 0.2))
		var accent_color: Color = weapon.get("accent", Color(0.6, 0.6, 0.6))
		var style := StyleBoxFlat.new()
		style.bg_color = body_color.darkened(0.45)
		style.border_color = accent_color
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.content_margin_left = 10.0
		style.content_margin_top = 6.0
		button.add_theme_stylebox_override("normal", style)

		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = hover.bg_color.lightened(0.15)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_color_override("font_color", Color(1, 1, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1))

		button.pressed.connect(_on_weapon_button_pressed.bind(i))
		weapon_grid.add_child(button)
		_weapon_buttons.append(button)

	panel_title.text = "WEAPONS  (%d)  —  tap to equip" % list.size()


## Gun-picker khula hai? (player.gd isse firing/look rok deta hai)
func is_menu_open() -> bool:
	return weapon_panel != null and weapon_panel.visible


func open_weapon_menu() -> void:
	weapon_panel.visible = true
	if is_firing_ui():
		_on_fire_button_up()          # menu khulta waqt firing band kar do
	if weapon_manager != null and is_instance_valid(weapon_manager):
		_on_weapon_index_changed(weapon_manager.current_index)
	if not DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_weapon_menu() -> void:
	weapon_panel.visible = false


func toggle_weapon_menu() -> void:
	if is_menu_open():
		close_weapon_menu()
	else:
		open_weapon_menu()


func is_firing_ui() -> bool:
	return fire_button != null and fire_button.get("is_down") == true


func _on_guns_button_pressed() -> void:
	toggle_weapon_menu()


func _on_weapon_button_pressed(index: int) -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.switch_weapon(index)
	close_weapon_menu()


# ============================================================ values dikhana ==

func set_health(value: int) -> void:
	health_bar.value = value
	health_label.text = "HP: %d" % value
	# HP kam hone pe rang badal jaye
	if value > 60:
		health_bar.modulate = Color(0.6, 1.0, 0.6)
	elif value > 30:
		health_bar.modulate = Color(1.0, 0.85, 0.4)
	else:
		health_bar.modulate = Color(1.0, 0.45, 0.4)


func set_score(value: int) -> void:
	score_label.text = "SCORE: %d" % value


## player.gd (har bar damage lene pe) isko call karta hai
func flash_damage() -> void:
	damage_flash.color = Color(0.8, 0.05, 0.05, 0.35)
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.35)


func show_game_over(final_score: int) -> void:
	close_weapon_menu()
	final_score_label.text = "SCORE: %d" % final_score
	game_over_panel.visible = true
	touch_controls.visible = false     # marne ke baad controls hata do
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ======================================================= mobile ke liye API ===

## player.gd isko har physics frame padhta hai
func get_move_vector() -> Vector2:
	if not touch_controls.visible:
		return Vector2.ZERO
	return joystick.output


func is_touch_ui_visible() -> bool:
	return touch_controls.visible


# ================================================================== signals ===

func _on_fire_button_down() -> void:
	fire_pressed.emit()


func _on_fire_button_up() -> void:
	fire_released.emit()


func _on_jump_button_pressed() -> void:
	jump_pressed.emit()


func _on_reload_button_pressed() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.start_reload()


func _on_swap_button_pressed() -> void:
	if weapon_manager != null and is_instance_valid(weapon_manager):
		weapon_manager.next_weapon()


func _on_restart_button_pressed() -> void:
	_restart_once()


## Game over panel ke dim area pe tap -> restart
func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_restart_once()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_restart_once()


func _restart_once() -> void:
	if _restarting:
		return
	_restarting = true
	restart_pressed.emit()
