extends CanvasLayer
##
## HUD
## - Crosshair (beech me)
## - Health bar (upar baayein) + Score (upar daayein)
## - Game over panel + "TAP TO RESTART" button
## - Mobile touch controls: joystick (bottom-left), FIRE + JUMP (bottom-right)
##
## HUD khud kuch nahi karta — sirf signals bhejta hai aur values dikhata hai.

signal fire_pressed
signal fire_released
signal jump_pressed
signal restart_pressed

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var score_label: Label = $ScoreLabel
@onready var hint_label: Label = $HintLabel
@onready var touch_controls: Control = $TouchControls
@onready var joystick = $TouchControls/Joystick          # joystick.gd wala
@onready var fire_button: Button = $TouchControls/FireButton
@onready var jump_button: Button = $TouchControls/JumpButton
@onready var game_over_panel: Control = $GameOverPanel
@onready var dim: ColorRect = $GameOverPanel/Dim
@onready var final_score_label: Label = $GameOverPanel/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/RestartButton
@onready var damage_flash: ColorRect = $DamageFlash

var _restarting: bool = false


func _ready() -> void:
	health_bar.max_value = 100.0
	set_health(100)
	set_score(0)
	game_over_panel.visible = false

	damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Touch controls sirf touch-screen (mobile) pe dikhao
	touch_controls.visible = DisplayServer.is_touchscreen_available()

	# Touch buttons ke signals (ye custom control hai jo raw touch handle karta hai)
	fire_button.pressed.connect(_on_fire_button_down)
	fire_button.released.connect(_on_fire_button_up)
	jump_button.pressed.connect(_on_jump_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)

	# Game over panel pe kahin bhi tap karo -> restart (touch pe pakka kaam karta hai)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input)

	# 8 second baad hint hata do
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(hint_label, "modulate:a", 0.0, 1.5)


# ------------------------------------------------------------ values dikhana --

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
	final_score_label.text = "SCORE: %d" % final_score
	game_over_panel.visible = true
	touch_controls.visible = false     # marne ke baad controls hata do
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ------------------------------------------------------- mobile ke liye API --

## player.gd isko har physics frame padhta hai
func get_move_vector() -> Vector2:
	if not touch_controls.visible:
		return Vector2.ZERO
	return joystick.output


func is_touch_ui_visible() -> bool:
	return touch_controls.visible


# ------------------------------------------------------------------ signals --

func _on_fire_button_down() -> void:
	fire_pressed.emit()


func _on_fire_button_up() -> void:
	fire_released.emit()


func _on_jump_button_pressed() -> void:
	jump_pressed.emit()


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
