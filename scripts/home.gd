extends Control
##
## Home — splash + loading ke baad ka main menu (Indus : Battle Royale).
##
## Screen pe kya hai:
##   * dark gradient background (GradientTexture2D — koi image nahi)
##   * top-center: logo (res://icon.svg, 150x150)
##   * title: "INDUS : BATTLE ROYALE" (gold #FFD700, 48)
##   * bada BATTLE button (green, corner 10, bold) -> main.tscn
##   * uske neeche GUNS + SETTINGS (grey, corner 8) -> "Coming Soon" popup
##   * top-right: coins + gems chip
##
## Sab kuch anchors + containers (VBox/HBox/Margin/Center) se bana hai, isliye
## mobile landscape (aur kisi bhi aspect ratio) pe theek scale hota hai.
##
## NOTE: emoji (🪙 / 💎) har platform ke default font me nahi hote. Isliye pehle
## Font.has_char() se check hota hai; na ho to wahi rang ka chhota procedural icon
## (gold circle / cyan gem) lag jata hai — screen kabhi tofu boxes nahi dikhati.
##

const MAIN_SCENE := "res://scenes/main.tscn"
const LOGO_PATH := "res://icon.svg"

const GOLD := Color(1.0, 0.843, 0.0)          # #FFD700
const GREEN := Color(0.2, 0.8, 0.3)           # spec: BATTLE button
const GREY := Color(0.3, 0.3, 0.3)            # spec: baaki buttons
const CYAN := Color(0.35, 0.85, 0.95)

## Currency (abhi 0 — aage economy aayegi to yahan se aayega)
var coins: int = 0
var gems: int = 0

var _dialog: AcceptDialog = null
var _starting: bool = false


func _ready() -> void:
	print("HOME: ready (logo %s)" % ("mila" if _load_logo() != null else "NAHI mila -> emblem"))
	_build_ui()
	_build_dialog()
	_fade_in()

	# CI smoke test (step 8f): `-- --ui-test` ke saath BATTLE khud dab jata hai, taaki
	# splash -> loading -> home -> main poora flow headless test ho sake.
	# Normal game me ye kabhi nahi chalta.
	if OS.get_cmdline_user_args().has("--ui-test"):
		print("HOME: --ui-test -> BATTLE auto-press")
		await get_tree().create_timer(0.6).timeout
		_on_battle_pressed()


# ------------------------------------------------------------------- UI ------

func _build_ui() -> void:
	add_child(_make_background())
	add_child(_make_top_bar())

	# ---- beech ka stack (logo + title + buttons) ----
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var box := VBoxContainer.new()
	box.name = "HomeBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	# logo (150x150)
	box.add_child(_make_logo(150))

	# title (gold)
	var title := Label.new()
	title.name = "Title"
	title.text = "INDUS : BATTLE ROYALE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", GOLD)
	_apply_bold(title)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(title)

	# tagline
	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.text = "SURVIVE · LOOT · WIN"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82, 1.0))
	box.add_child(tagline)

	box.add_child(_spacer(26))

	# BATTLE (bada green button)
	var battle := _make_button("BATTLE", 50, GREEN, 10, Vector2(420, 110))
	battle.name = "BattleButton"
	battle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	battle.pressed.connect(_on_battle_pressed)
	box.add_child(battle)

	box.add_child(_spacer(18))

	# GUNS + SETTINGS
	var row := HBoxContainer.new()
	row.name = "SubRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)

	var guns := _make_button("GUNS", 26, GREY, 8, Vector2(200, 64))
	guns.name = "GunsButton"
	guns.pressed.connect(_on_coming_soon.bind("GUNS"))
	row.add_child(guns)

	var settings := _make_button("SETTINGS", 26, GREY, 8, Vector2(200, 64))
	settings.name = "SettingsButton"
	settings.pressed.connect(_on_coming_soon.bind("SETTINGS"))
	row.add_child(settings)

	# ---- bottom-left: version ----
	var version := Label.new()
	version.name = "Version"
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 24
	version.offset_top = -38
	version.offset_right = 420
	version.offset_bottom = -12
	version.text = "Indus : Battle Royale  ·  v1.2.0"
	version.add_theme_font_size_override("font_size", 14)
	version.add_theme_color_override("font_color", Color(0.55, 0.60, 0.66, 1.0))
	add_child(version)


## Dark gradient background (GradientTexture2D — poora procedural, koi image nahi)
func _make_background() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.07, 0.10, 0.16, 1.0))      # upar: neela-ish
	gradient.set_color(1, Color(0.015, 0.02, 0.03, 1.0))     # neeche: almost black

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 64
	tex.height = 256

	var rect := TextureRect.new()
	rect.name = "Background"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Top-right: coins + gems (spec)
func _make_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_top = 18
	bar.offset_right = -24
	bar.offset_bottom = 74
	bar.add_theme_constant_override("separation", 12)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	bar.add_child(_make_currency_chip("🪙", 0x1FA99, "●", 0x25CF, GOLD, coins))
	bar.add_child(_make_currency_chip("💎", 0x1F48E, "◆", 0x25C6, CYAN, gems))
	return bar


## Ek currency chip: icon (emoji / symbol / procedural) + number.
## Emoji support default font me nahi hota, isliye has_char() se check.
func _make_currency_chip(emoji: String, emoji_code: int, symbol: String, symbol_code: int,
		tint: Color, value: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(112, 46)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.80)
	style.border_color = Color(1, 1, 1, 0.12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# ---- icon ----
	var font := ThemeDB.fallback_font
	var glyph := ""
	if font != null:
		if font.has_char(emoji_code):
			glyph = emoji
		elif font.has_char(symbol_code):
			glyph = symbol

	if not glyph.is_empty():
		var icon := Label.new()
		icon.text = glyph
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 20)
		icon.add_theme_color_override("font_color", tint)
		row.add_child(icon)
	else:
		# default font me koi glyph nahi -> wahi rang ka chhota icon
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = tint
		dot_style.corner_radius_top_left = 8
		dot_style.corner_radius_top_right = 8
		dot_style.corner_radius_bottom_left = 8
		dot_style.corner_radius_bottom_right = 8
		dot.add_theme_stylebox_override("panel", dot_style)
		row.add_child(dot)

	# ---- number ----
	var count := Label.new()
	count.text = str(value)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 22)
	count.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))
	_apply_bold(count)
	row.add_child(count)
	return panel


## logo ka dabba (aspect bacha hua). Na mile to procedural emblem.
func _make_logo(size_px: int) -> Control:
	var tex := _load_logo()
	if tex != null:
		var rect := TextureRect.new()
		rect.name = "Logo"
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(size_px, size_px)
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	var panel := PanelContainer.new()
	panel.name = "LogoPlaceholder"
	panel.custom_minimum_size = Vector2(size_px, size_px)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 1.0)
	style.border_color = GREEN
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", style)
	var letters := Label.new()
	letters.text = "IBR"
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letters.add_theme_font_size_override("font_size", 28)
	_apply_bold(letters)
	letters.add_theme_color_override("font_color", GREEN)
	panel.add_child(letters)
	return panel


func _load_logo() -> Texture2D:
	if not ResourceLoader.exists(LOGO_PATH):
		return null
	var res: Resource = load(LOGO_PATH)
	if res is Texture2D:
		return res as Texture2D
	return null


# ------------------------------------------------------------- widgets ------

## Button banata hai (spec: green BATTLE corner 10, grey baaki corner 8, bold text)
func _make_button(text: String, font_size: int, bg: Color, radius: int,
		min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	_apply_bold(button)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.92, 0.95, 0.92, 1))
	button.add_theme_stylebox_override("normal", _button_style(bg, radius))
	button.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.10), radius))
	button.add_theme_stylebox_override("pressed", _button_style(bg.darkened(0.18), radius))
	button.add_theme_stylebox_override("disabled", _button_style(bg.darkened(0.35), radius))
	button.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0), radius,
			3, Color(1, 1, 1, 0.85)))
	return button


func _button_style(bg: Color, radius: int, border_width: int = 0,
		border_color: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


## Bold text — Godot ke DEFAULT font ka emboldened version (koi external font nahi).
## FontVariation = engine ka built-in wrapper; variation_embolden se wahi font mota
## dikhta hai. Agar ThemeDB abhi ready na ho (fallback_font null) to chup-chaap
## default font hi rehne dete hain — koi crash nahi.
func _apply_bold(control: Control) -> void:
	var base: Font = ThemeDB.fallback_font
	if base == null:
		return
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.6
	control.add_theme_font_override("font", bold)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _fade_in() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)


# --------------------------------------------------------------- actions ----

func _on_battle_pressed() -> void:
	if _starting:
		return
	_starting = true
	print("HOME: BATTLE -> main")
	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		# fail-soft: scene khul nahi paya to home pe hi raho (crash nahi)
		_starting = false
		push_error("HOME: main.tscn khul nahi paya (err %d)" % err)
		_show_coming_soon("Game load nahi ho paya — dobara try karo.")


## GUNS / SETTINGS -> "Coming Soon" popup
func _on_coming_soon(which: String) -> void:
	print("HOME: %s -> Coming Soon" % which)
	_show_coming_soon("Coming Soon")


func _show_coming_soon(text: String) -> void:
	if _dialog == null:
		return
	_dialog.dialog_text = text
	_dialog.popup_centered(Vector2i(420, 180))


func _build_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.name = "ComingSoonDialog"
	_dialog.title = "Indus : Battle Royale"
	_dialog.ok_button_text = "OK"
	_dialog.dialog_text = "Coming Soon"
	# default font se bada, padhne me aasan
	var label: Label = _dialog.get_label()
	if label != null:
		label.add_theme_font_size_override("font_size", 22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_dialog)


## PC pe test karna aasan ho: Enter / Space se bhi BATTLE
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_on_battle_pressed()
