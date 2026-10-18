extends Control
##
## Home — splash + loading ke baad ka lobby (Indus : Battle Royale).
##
## Layers (neeche se upar):
##   1. Background  : TextureRect -> assets/ui/home_bg.png
##                    EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_COVERED (poori screen)
##   2. Scrim       : halka black gradient (buttons/text ke peeche, image zinda rehti hai)
##   3. Top-left    : logo (assets/ui/home_logo.png; na mile to icon.svg + text lockup)
##   4. Top-right   : Coins, Gems, Settings, Notifications (translucent dark chips)
##   5. Left        : MISSIONS / INVENTORY / WEAPONS (dark blue + cyan border)
##   6. Bottom-left : mode select (SOLO / SQUAD)
##   7. Bottom-right: START BATTLE (gold 300x80) -> scenes/main.tscn
##
## Sab anchors + containers se banta hai (1280x720 base, canvas_items stretch),
## isliye har phone/tablet landscape me fit hota hai.
##
## Fail-soft: background/logo missing -> procedural fallback, kabhi crash nahi.
##

const MAIN_SCENE := "res://scenes/main.tscn"
const BG_PATH := "res://assets/ui/home_bg.png"
const LOGO_PATH := "res://assets/ui/home_logo.png"
const FALLBACK_LOGO := "res://icon.svg"

const GOLD := Color(1.0, 0.80, 0.25)
const GOLD_TEXT := Color(0.13, 0.08, 0.0)
const CYAN := Color(0.35, 0.85, 0.95)
## semi-transparent dark blue (left menu)
const PANEL_BG := Color(0.04, 0.10, 0.22, 0.72)
## semi-transparent dark (top-right chips / mode buttons)
const CHIP_BG := Color(0.03, 0.05, 0.09, 0.68)

## Currency (abhi 0 — economy aage aayegi to yahin se aayega)
var coins: int = 0
var gems: int = 0

var _dialog: AcceptDialog = null
var _start_button: Button = null
var _starting: bool = false
var _mode: String = "SOLO"
var _bg_ok: bool = false
var _logo_ok: bool = false


func _ready() -> void:
	_build_ui()
	_build_dialog()
	_fade_in()

	print("HOME: ready (bg %s, logo %s)" % [
		"mila" if _bg_ok else "NAHI mila -> gradient",
		"mila" if _logo_ok else "NAHI mila -> text lockup",
	])

	# CI smoke test (step 8f): `-- --ui-test` ke saath START BATTLE khud dab jata hai,
	# taaki splash -> loading -> home -> main poora flow headless test ho sake.
	# Normal game me ye kabhi nahi chalta.
	if OS.get_cmdline_user_args().has("--ui-test"):
		print("HOME: --ui-test -> START BATTLE auto-press")
		await get_tree().create_timer(0.6).timeout
		_on_start_battle()


# ------------------------------------------------------------------- UI ------

func _build_ui() -> void:
	add_child(_make_background())
	add_child(_make_scrim())
	add_child(_make_top_bar())
	add_child(_make_left_menu())
	add_child(_make_mode_bar())
	add_child(_make_start_button_anchored())
	add_child(_make_version_label())


## Background: assets/ui/home_bg.png (cover). Missing -> purana gradient.
func _make_background() -> Control:
	var tex := _load_texture(BG_PATH)
	_bg_ok = tex != null
	if _bg_ok:
		print("HOME: bg loaded -> %s" % BG_PATH)
	else:
		print("HOME: bg MISSING -> %s" % BG_PATH)

	if tex != null:
		var rect := TextureRect.new()
		rect.name = "HomeBackground"
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	# ---- fallback: procedural gradient (koi image nahi) ----
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.06, 0.09, 0.15, 1.0))
	gradient.set_color(1, Color(0.01, 0.015, 0.025, 1.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = gradient
	gtex.fill_from = Vector2(0.0, 0.0)
	gtex.fill_to = Vector2(0.0, 1.0)
	gtex.width = 64
	gtex.height = 256

	var rect := TextureRect.new()
	rect.name = "HomeBackgroundFallback"
	rect.texture = gtex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Halke black gradients — left menu aur bottom buttons ko background se alag dikhate
## hain, par image ko poora dim nahi karte.
func _make_scrim() -> Control:
	var holder := Control.new()
	holder.name = "Scrim"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := TextureRect.new()
	left.texture = _gradient_texture(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), false)
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 0
	left.offset_top = 0
	left.offset_right = 430
	left.offset_bottom = 0
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(left)

	var bottom := TextureRect.new()
	bottom.texture = _gradient_texture(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.62), true)
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 0
	bottom.offset_top = -240
	bottom.offset_right = 0
	bottom.offset_bottom = 0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bottom)
	return holder


## Top bar: logo (left) + spacer + coins/gems/settings/notifications (right).
func _make_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 26
	bar.offset_top = 20
	bar.offset_right = -26
	bar.offset_bottom = 120
	bar.add_theme_constant_override("separation", 12)

	bar.add_child(_make_logo(Vector2(250, 100)))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	bar.add_child(_make_currency_chip(IconGlyph.Kind.COIN, GOLD, coins))
	bar.add_child(_make_currency_chip(IconGlyph.Kind.GEM, CYAN, gems))
	bar.add_child(_make_icon_button("SETTINGS", IconGlyph.Kind.GEAR, CYAN))
	bar.add_child(_make_icon_button("NOTIFICATIONS", IconGlyph.Kind.BELL,
			Color(0.90, 0.93, 1.0)))
	return bar


## Left menu: MISSIONS / INVENTORY / WEAPONS (vertical).
func _make_left_menu() -> Control:
	var box := VBoxContainer.new()
	box.name = "LeftMenu"
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 26
	box.offset_top = 168
	box.offset_right = 296
	box.offset_bottom = 168 + 3 * 56 + 2 * 12
	box.add_theme_constant_override("separation", 12)

	var items := ["MISSIONS", "INVENTORY", "WEAPONS"]
	for item in items:
		var text: String = item
		var button := _make_menu_button(text)
		button.pressed.connect(_on_coming_soon.bind(text))
		box.add_child(button)
	return box


## Bottom-left: MODE + SOLO / SQUAD toggle.
func _make_mode_bar() -> Control:
	var row := HBoxContainer.new()
	row.name = "ModeBar"
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 26
	row.offset_top = -92
	row.offset_right = 430
	row.offset_bottom = -26
	row.add_theme_constant_override("separation", 10)

	var caption := Label.new()
	caption.text = "MODE"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92, 0.9))
	_apply_bold(caption)
	row.add_child(caption)

	var group := ButtonGroup.new()
	group.allow_unpress = false

	var solo := _make_mode_button("SOLO", group)
	var squad := _make_mode_button("SQUAD", group)
	solo.button_pressed = true          # default mode; connect se pehle set
	solo.toggled.connect(_on_mode_toggled.bind("SOLO"))
	squad.toggled.connect(_on_mode_toggled.bind("SQUAD"))
	row.add_child(solo)
	row.add_child(squad)
	return row


## Bottom-right: huge gold START BATTLE (300x80).
func _make_start_button_anchored() -> Control:
	_start_button = _make_start_button()
	_start_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_start_button.offset_left = -326
	_start_button.offset_top = -106
	_start_button.offset_right = -26
	_start_button.offset_bottom = -26
	return _start_button


func _make_start_button() -> Button:
	var button := Button.new()
	button.name = "StartBattleButton"
	button.text = "START BATTLE"
	button.custom_minimum_size = Vector2(300, 80)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 30)
	_apply_bold(button)
	button.add_theme_color_override("font_color", GOLD_TEXT)
	button.add_theme_color_override("font_hover_color", GOLD_TEXT)
	button.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.0))
	button.add_theme_color_override("font_disabled_color", Color(0.28, 0.22, 0.10))

	var normal := _panel_style(GOLD, GOLD.lightened(0.35), 2, 14)
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 12
	normal.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("normal", normal)

	var hover := _panel_style(GOLD.lightened(0.12), Color(1.0, 0.95, 0.70), 2, 14)
	hover.shadow_color = Color(0, 0, 0, 0.55)
	hover.shadow_size = 14
	hover.shadow_offset = Vector2(0, 4)
	button.add_theme_stylebox_override("hover", hover)

	button.add_theme_stylebox_override("pressed",
			_panel_style(GOLD.darkened(0.12), GOLD, 2, 14))
	button.add_theme_stylebox_override("disabled",
			_panel_style(GOLD.darkened(0.35), GOLD.darkened(0.20), 2, 14))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_on_start_battle)
	return button


func _make_version_label() -> Control:
	var label := Label.new()
	label.name = "Version"
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_left = 0
	label.offset_top = -24
	label.offset_right = 0
	label.offset_bottom = -6
	label.text = "Indus : Battle Royale  ·  v1.2.0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.68, 0.76, 0.85, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ------------------------------------------------------------- widgets ------

## Logo: assets/ui/home_logo.png (250x100). Na mile to icon.svg + "INDUS" text
## lockup, aur wo bhi na mile to sirf text — screen kabhi khaali nahi rehti.
func _make_logo(logo_size: Vector2) -> Control:
	var custom := _load_texture(LOGO_PATH)
	if custom != null:
		_logo_ok = true
		var rect := TextureRect.new()
		rect.name = "Logo"
		rect.texture = custom
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = logo_size
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	var emblem := _load_texture(FALLBACK_LOGO)
	_logo_ok = emblem != null
	return _make_text_logo(logo_size, emblem)


func _make_text_logo(logo_size: Vector2, emblem: Texture2D) -> Control:
	var row := HBoxContainer.new()
	row.name = "LogoFallback"
	row.custom_minimum_size = logo_size
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 10)

	if emblem != null:
		var icon := TextureRect.new()
		icon.texture = emblem
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(88, 88)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)

	var title := Label.new()
	title.text = "INDUS"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	_apply_bold(title)
	words.add_child(title)

	var sub := Label.new()
	sub.text = "BATTLE ROYALE"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", CYAN)
	_apply_bold(sub)
	words.add_child(sub)
	return row


## Translucent dark chip: icon + number (coins / gems).
func _make_currency_chip(kind: int, tint: Color, value: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(104, 46)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _panel_style(
			CHIP_BG, Color(1, 1, 1, 0.14), 1, 14))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(IconGlyph.new(kind, tint))

	var count := Label.new()
	count.text = str(value)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 20)
	count.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))
	_apply_bold(count)
	row.add_child(count)
	return panel


## Square icon button (Settings / Notifications) — translucent dark, cyan icon.
func _make_icon_button(label: String, kind: int, tint: Color) -> Button:
	var button := Button.new()
	button.name = label.capitalize().replace(" ", "") + "Button"
	button.tooltip_text = label.capitalize()
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _panel_style(
			CHIP_BG, Color(1, 1, 1, 0.14), 1, 14))
	button.add_theme_stylebox_override("hover", _panel_style(
			CHIP_BG.lightened(0.12), Color(0.35, 0.85, 0.95, 0.55), 1, 14))
	button.add_theme_stylebox_override("pressed", _panel_style(
			CHIP_BG.darkened(0.20), CYAN, 1, 14))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_on_coming_soon.bind(label))

	var glyph := IconGlyph.new(kind, tint)
	glyph.anchor_left = 0.5
	glyph.anchor_top = 0.5
	glyph.anchor_right = 0.5
	glyph.anchor_bottom = 0.5
	glyph.offset_left = -11
	glyph.offset_top = -11
	glyph.offset_right = 11
	glyph.offset_bottom = 11
	button.add_child(glyph)
	return button


## Left menu ka ek button: semi-transparent dark blue + cyan border.
func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.name = text.capitalize().replace(" ", "") + "Button"
	button.text = text
	button.custom_minimum_size = Vector2(270, 56)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	_apply_bold(button)
	button.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", CYAN)

	var normal := _panel_style(PANEL_BG, Color(0.35, 0.85, 0.95, 0.85), 1, 8)
	normal.border_width_left = 4
	normal.content_margin_left = 22
	button.add_theme_stylebox_override("normal", normal)

	var hover := _panel_style(PANEL_BG.lightened(0.10),
			Color(0.45, 0.92, 1.0, 1.0), 1, 8)
	hover.border_width_left = 4
	hover.content_margin_left = 22
	button.add_theme_stylebox_override("hover", hover)

	var pressed := _panel_style(Color(0.10, 0.28, 0.45, 0.85), CYAN, 1, 8)
	pressed.border_width_left = 4
	pressed.content_margin_left = 22
	button.add_theme_stylebox_override("pressed", pressed)

	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


## SOLO / SQUAD toggle button (selected = cyan border + blue fill).
func _make_mode_button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(112, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	_apply_bold(button)
	button.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", CYAN)

	button.add_theme_stylebox_override("normal", _panel_style(
			CHIP_BG, Color(1, 1, 1, 0.12), 1, 10))
	button.add_theme_stylebox_override("hover", _panel_style(
			CHIP_BG.lightened(0.12), Color(0.45, 0.90, 1.0, 0.60), 1, 10))

	var selected := _panel_style(Color(0.06, 0.26, 0.40, 0.88), CYAN, 2, 10)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## Bold text — Godot ke DEFAULT font ka emboldened version (koi external font nahi).
func _apply_bold(control: Control) -> void:
	var base: Font = ThemeDB.fallback_font
	if base == null:
		return
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.6
	control.add_theme_font_override("font", bold)


func _gradient_texture(from: Color, to: Color, vertical: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 4 if vertical else 8
	tex.height = 256 if vertical else 4
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
	return tex


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Texture2D:
		return res as Texture2D
	return null


func _fade_in() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)


# --------------------------------------------------------------- actions ----

func _on_start_battle() -> void:
	if _starting:
		return
	_starting = true
	print("HOME: BATTLE -> main")
	if _start_button != null:
		_start_button.disabled = true

	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		# fail-soft: scene khul nahi paya to home pe hi raho (crash nahi)
		_starting = false
		if _start_button != null:
			_start_button.disabled = false
		push_error("HOME: main.tscn khul nahi paya (err %d)" % err)
		_show_coming_soon("Game load nahi ho paya — dobara try karo.")


## MISSIONS / INVENTORY / WEAPONS / SETTINGS / NOTIFICATIONS -> "Coming Soon"
func _on_coming_soon(which: String) -> void:
	print("HOME: %s -> Coming Soon" % which)
	_show_coming_soon("Coming Soon")


func _on_mode_toggled(is_on: bool, mode: String) -> void:
	if not is_on:
		return
	_mode = mode
	print("HOME: mode -> %s" % mode)


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
	var label: Label = _dialog.get_label()
	if label != null:
		label.add_theme_font_size_override("font_size", 22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_dialog)


## PC pe test karna aasan ho: Enter / Space se bhi START BATTLE
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_on_start_battle()


# ------------------------------------------------------ procedural icons ------

## Chhote icons (coin / gem / gear / bell) code se draw hote hain — default font me
## emoji nahi hote, aur external image/font ki zaroorat bhi nahi padti.
class IconGlyph extends Control:
	enum Kind { COIN, GEM, GEAR, BELL }

	var kind: int = Kind.COIN
	var tint: Color = Color.WHITE

	func _init(p_kind: int, p_tint: Color) -> void:
		kind = p_kind
		tint = p_tint
		custom_minimum_size = Vector2(20, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		match kind:
			Kind.COIN:
				draw_circle(c, r, tint)
				draw_circle(c, r * 0.55, tint.darkened(0.35))
			Kind.GEM:
				var points := PackedVector2Array([
					c + Vector2(0.0, -r),
					c + Vector2(r * 0.8, 0.0),
					c + Vector2(0.0, r),
					c + Vector2(-r * 0.8, 0.0),
				])
				draw_colored_polygon(points, tint)
			Kind.GEAR:
				draw_arc(c, r * 0.50, 0.0, TAU, 24, tint, 2.5)
				for i in 8:
					var angle := TAU * float(i) / 8.0
					var dir := Vector2(cos(angle), sin(angle))
					draw_line(c + dir * r * 0.50, c + dir * r * 0.95, tint, 2.5)
			Kind.BELL:
				draw_arc(c + Vector2(0.0, r * 0.10), r * 0.62, PI, TAU, 20, tint, 2.5)
				draw_line(c + Vector2(-r * 0.62, r * 0.10),
						c + Vector2(r * 0.62, r * 0.10), tint, 2.5)
				draw_circle(c + Vector2(0.0, r * 0.45), r * 0.18, tint)
