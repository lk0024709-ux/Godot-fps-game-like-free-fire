extends Control
##
## Splash — game start hone pe SABSE PEHLI screen (Indus : Battle Royale).
##
## Flow:  splash.tscn  ->  loading.tscn  ->  home.tscn  ->  main.tscn (asli game)
##
## Screen pe kya hai:
##   * poori screen kaala background (ColorRect)
##   * beech me premium logo (res://assets/ui/home_logo.png, 300x300, aspect ratio bacha hua)
##   * logo ke neeche "AURA GAMES STUDIO PRESENTS"
##   * poora VBox fade-in (1s) -> 1.5s rukta hai -> fade-out (1s) -> loading.tscn
##
## LOGO FAIL-SOFT: agar premium logo import nahi hua / file hai hi nahi, to crash nahi —
## ek procedural emblem dikh jata hai. Isliye CI me bhi kabhi "missing resource" error nahi aata.
##
## Skip: mobile pe kahin bhi tap karo (ya PC pe koi bhi key/click) to seedha aage.
##

const NEXT_SCENE := "res://scenes/loading.tscn"
const LOGO_PATH := "res://assets/ui/home_logo.png"

## Animation ke seconds (spec: 1s fade-in, 1.5s hold, 1s fade-out)
const FADE_IN := 1.0
const HOLD := 1.5
const FADE_OUT := 1.0

var _box: VBoxContainer = null
var _done: bool = false


func _ready() -> void:
	var has_logo := _load_logo() != null
	print("SPLASH: ready (logo %s)" % ("mila" if has_logo else "NAHI mila -> procedural emblem"))
	_build_ui()
	_play()


# ------------------------------------------------------------------- UI ------

func _build_ui() -> void:
	# ---- background (pure black) ----
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	# ---- beech ka stack (yahi fade hota hai) ----
	_box = VBoxContainer.new()
	_box.name = "SplashBox"
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 22)
	_box.modulate.a = 0.0                     # tween isko 0 -> 1 -> 0 karta hai
	center.add_child(_box)

	_box.add_child(_make_logo(300))

	var presents := Label.new()
	presents.name = "Presents"
	presents.text = "AURA GAMES STUDIO PRESENTS"
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presents.add_theme_font_size_override("font_size", 24)
	presents.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_box.add_child(presents)


## logo ka 300x300 dabba (aspect bacha hua). Na mile to procedural emblem.
func _make_logo(size_px: int) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex := _load_logo()
	if tex != null:
		var rect := TextureRect.new()
		rect.name = "Logo"
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(size_px, size_px)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		holder.add_child(_make_placeholder(size_px))
	return holder


## Premium logo na mile to yahi dikhta hai (koi missing-resource error nahi).
func _make_placeholder(size_px: int) -> Control:
	var panel := PanelContainer.new()
	panel.name = "LogoPlaceholder"
	panel.custom_minimum_size = Vector2(size_px, size_px)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 1.0)
	style.border_color = Color(0.31, 0.94, 0.54, 1.0)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.corner_radius_top_left = 36
	style.corner_radius_top_right = 36
	style.corner_radius_bottom_left = 36
	style.corner_radius_bottom_right = 36
	panel.add_theme_stylebox_override("panel", style)

	var letters := Label.new()
	letters.text = "INDUS"
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letters.add_theme_font_size_override("font_size", 44)
	letters.add_theme_color_override("font_color", Color(0.31, 0.94, 0.54, 1.0))
	panel.add_child(letters)
	return panel


## res://assets/ui/home_logo.png -> Texture2D, ya null (file nahi / import nahi hua).
func _load_logo() -> Texture2D:
	if not ResourceLoader.exists(LOGO_PATH):
		return null
	var res: Resource = load(LOGO_PATH)
	if res is Texture2D:
		return res as Texture2D
	return null


# ------------------------------------------------------------- animation -----

func _play() -> void:
	var tween := create_tween()
	tween.tween_property(_box, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(_box, "modulate:a", 0.0, FADE_OUT)
	tween.finished.connect(_finish)


## Tap / key / click -> splash skip (mobile pe 3.5s wait karna zaroori nahi).
func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	print("SPLASH: done -> loading")
	get_tree().change_scene_to_file(NEXT_SCENE)
