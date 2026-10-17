extends Control
##
## Loading — splash ke baad, home se pehle.
##
## Kaam: main.tscn (asli game) ko BACKGROUND THREAD me load karta hai
## (ResourceLoader.load_threaded_request) taaki UI freeze na ho. Progress bar
## _process() me load_threaded_get_status() se update hoti hai.
##
## 100% hone pe 0.5s ruk kar home.tscn pe chala jata hai.
##
## Fail-soft (zaroori):
##   * threaded load fail ho jaye to ek normal load() try hota hai, aur
##   * kuch bhi na ho paye to bhi 0.5s baad home chala jata hai (game kabhi atakta nahi —
##     home ka BATTLE button main.tscn ko khud load kar lega).
##
## NOTE: loading screen kam se kam `MIN_SHOW` second dikhti hai, warna 60fps pe
## progress bar ka pata hi nahi chalta (scene load 0.05s me ho jata hai).
##

const MAIN_SCENE := "res://scenes/main.tscn"
const NEXT_SCENE := "res://scenes/home.tscn"

## Loading screen kam se kam itni der dikhe (seconds)
const MIN_SHOW := 1.2
## 100% hone ke baad itna ruk kar home pe jao (spec: 0.5s)
const DONE_DELAY := 0.5

var _bar: ProgressBar = null
var _bar_min_width: float = 220.0

var _requested: bool = false
var _pulled: bool = false
var _finished: bool = false
var _elapsed: float = 0.0
var _shown: float = 0.0            ## bar pe jo dikh raha hai (0..1, smooth)
var _target: float = 0.0           ## asli progress (0..1)
var _done_at: float = -1.0         ## jab target 1.0 hua (seconds)
var _progress: Array = []          ## load_threaded_get_status isko bharta hai


func _ready() -> void:
	_build_ui()
	_fit_bar()

	# ---- main.tscn ko thread me load karo ----
	var err: int = ResourceLoader.load_threaded_request(MAIN_SCENE)
	if err == OK:
		_requested = true
		print("LOADING: threaded request start (%s)" % MAIN_SCENE)
	else:
		# fail-soft: thread shuru na ho to seedha load (thoda block karega, par game chalega)
		push_warning("LOADING: threaded request fail (err %d) -> direct load try" % err)
		var res: Resource = load(MAIN_SCENE)
		_target = 1.0
		print("LOADING: direct load %s" % ("theek" if res != null else "FAIL (home se load hoga)"))


# ------------------------------------------------------------------- UI ------

func _build_ui() -> void:
	# ---- background (dark grey) ----
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.11, 0.12, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	var box := VBoxContainer.new()
	box.name = "LoadingBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	# ---- "LOADING..." ----
	var title := Label.new()
	title.name = "LoadingLabel"
	title.text = "LOADING..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var base_font: Font = ThemeDB.fallback_font
	if base_font != null:
		var bold := FontVariation.new()
		bold.base_font = base_font
		bold.variation_embolden = 0.6
		title.add_theme_font_override("font", bold)
	box.add_child(title)

	# ---- progress bar (green fill) ----
	_bar = ProgressBar.new()
	_bar.name = "ProgressBar"
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = true
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.custom_minimum_size = Vector2(_bar_min_width, 28.0)
	_bar.add_theme_stylebox_override("background", _make_bar_bg())
	_bar.add_theme_stylebox_override("fill", _make_bar_fill())
	_bar.add_theme_font_size_override("font_size", 15)
	_bar.add_theme_color_override("font_color", Color(0.92, 1.0, 0.94, 1.0))
	box.add_child(_bar)

	# ---- chhota hint ----
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "INDUS : BATTLE ROYALE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72, 1.0))
	box.add_child(hint)

	# window/screen ka size badle to bar ki width dobara set ho
	resized.connect(_fit_bar)


## Bar ki width = screen ki 60% (spec). Chhoti screen pe minimum 220px.
func _fit_bar() -> void:
	if _bar == null:
		return
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	_bar.custom_minimum_size = Vector2(maxf(_bar_min_width, viewport_width * 0.6), 28.0)


func _make_bar_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.95)
	style.border_color = Color(0.85, 0.85, 0.85, 0.25)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


func _make_bar_fill() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.80, 0.30, 1.0)      # spec: green
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


# -------------------------------------------------------------- loading -----

func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta

	# ---- thread ki halat dekho ----
	if _requested and not _pulled:
		var status: int = ResourceLoader.load_threaded_get_status(MAIN_SCENE, _progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_target = clampf(float(_progress[0]) if _progress.size() > 0 else 0.0, 0.0, 1.0)
			ResourceLoader.THREAD_LOAD_LOADED:
				_target = 1.0
				# load_theaded_get() call karna zaroori hai — isse thread band hota hai
				# aur scene ResourceLoader ke cache me chala jata hai (BATTLE turant khulega).
				var packed: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE)
				_pulled = true
				print("LOADING: main.tscn ready (%s)" %
						("PackedScene" if packed is PackedScene else "resource"))
			_:
				# THREAD_LOAD_FAILED / INVALID_RESOURCE
				_target = 1.0
				_pulled = true
				push_warning("LOADING: thread load fail (status %d) -> home se load hoga" % status)

	# ---- bar ko smooth chalao (seedha jump nahi) ----
	if _target >= 1.0:
		_shown = move_toward(_shown, 1.0, delta * 2.5)
	else:
		_shown = lerpf(_shown, _target, clampf(delta * 6.0, 0.0, 1.0))
	_bar.value = _shown * 100.0

	# ---- 100% -> 0.5s ruk kar home ----
	if _target >= 1.0:
		if _done_at < 0.0:
			_done_at = _elapsed
		if _elapsed >= maxf(_done_at + DONE_DELAY, MIN_SHOW):
			_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_bar.value = 100.0
	print("LOADING: done -> home")
	get_tree().change_scene_to_file(NEXT_SCENE)
