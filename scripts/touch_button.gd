extends Control
##
## TouchButton — True Multi-Touch Tactical HUD Button
##
## Handles raw `InputEventScreenTouch` and `InputEventScreenDrag` per finger `index`
## (plus mouse fallback when testing on PC), calling `accept_event()` so pressing FIRE,
## AIM, JUMP, CROUCH, RELOAD, HEAL, BACKPACK, or EJECT works simultaneously alongside
## the Dynamic Virtual Joystick and camera swipe without blocking one another.
##

signal pressed
signal released

@export var label_text: String = "FIRE"
@export var badge_text: String = ""
@export var icon_kind: String = ""
@export var font_size: int = 20
@export var fill_color: Color = Color(0.08, 0.12, 0.18, 0.72)
@export var ring_color: Color = Color(0.85, 0.88, 0.95, 0.78)
@export var active_fill_color: Color = Color(0.95, 0.72, 0.18, 0.82)
@export var active_ring_color: Color = Color(1.0, 0.95, 0.68, 1.0)
@export var label_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var label_outline: bool = true

var is_down: bool = false
var is_toggled_active: bool = false

var _pointer: int = -1        ## -1 = idle, -2 = mouse, >= 0 = touch index
var _touch_device: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_device = DisplayServer.is_touchscreen_available()
	resized.connect(queue_redraw)


func set_active_highlight(active: bool) -> void:
	if is_toggled_active == active:
		return
	is_toggled_active = active
	queue_redraw()


func set_badge(text: String) -> void:
	if badge_text == text:
		return
	badge_text = text
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _pointer == -1:
				_pointer = touch.index
				accept_event()
				_set_down(true)
		elif touch.index == _pointer:
			accept_event()
			_set_down(false)
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer:
			accept_event()
			if drag.position.distance_to(size * 0.5) > maxf(size.x, size.y) * 0.85:
				_set_down(false)
		return

	if _touch_device:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer == -1:
				_pointer = -2
				accept_event()
				_set_down(true)
		elif _pointer == -2:
			accept_event()
			_set_down(false)


func _set_down(down: bool) -> void:
	if down:
		if is_down:
			return
		is_down = true
		queue_redraw()
		pressed.emit()
	else:
		_pointer = -1
		if not is_down:
			return
		is_down = false
		queue_redraw()
		released.emit()


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	var fill := active_fill_color if is_toggled_active else fill_color
	var ring := active_ring_color if is_toggled_active else ring_color
	if is_down:
		fill = Color(
			minf(fill.r + 0.22, 1.0),
			minf(fill.g + 0.18, 1.0),
			minf(fill.b + 0.14, 1.0),
			minf(fill.a + 0.25, 1.0)
		)
		ring = Color(1.0, 1.0, 1.0, 1.0)

	# Outer shadow halo + filled circular tactical button + crisp double ring
	draw_circle(center + Vector2(0.0, 2.0), radius, Color(0.0, 0.0, 0.0, 0.34))
	draw_circle(center, maxf(1.0, radius - 1.5), fill)
	draw_arc(center, maxf(2.0, radius - 2.0), 0.0, TAU, 64, ring, 2.8, true)
	if radius >= 55.0:
		draw_arc(center, radius - 8.5, 0.0, TAU, 56, Color(1.0, 0.92, 0.72, 0.28), 1.5, true)

	_draw_vector_glyph(center, radius)

	var font := get_theme_default_font()
	if font == null:
		return

	if not label_text.is_empty():
		var text_y_offset := radius * 0.34 if not icon_kind.is_empty() else 0.0
		var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := Vector2(0.0, center.y + text_y_offset + text_size.y * 0.34 - font.get_descent(font_size) * 0.4)
		var outline_sz: int = 5 if label_outline else 0
		if outline_sz > 0:
			draw_string_outline(font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, outline_sz, Color(0, 0, 0, 0.82))
		draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, label_color)

	if not badge_text.is_empty():
		var b_pos := Vector2(size.x - 28.0, 16.0)
		draw_circle(b_pos + Vector2(10.0, -4.0), 12.0, Color(0.08, 0.12, 0.18, 0.92))
		draw_arc(b_pos + Vector2(10.0, -4.0), 12.0, 0.0, TAU, 24, ring, 1.6, true)
		draw_string_outline(font, b_pos, badge_text, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, 3, Color(0, 0, 0, 0.85))
		draw_string(font, b_pos, badge_text, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, Color(1.0, 0.94, 0.65, 1.0))


func _draw_vector_glyph(c: Vector2, r: float) -> void:
	if icon_kind.is_empty():
		return
	var ic := c - Vector2(0.0, r * 0.18)
	var col := Color(1.0, 0.97, 0.90, 0.95)
	match icon_kind:
		"fire":
			var cr := r * 0.24
			draw_arc(ic, cr, 0.0, TAU, 32, col, 2.6, true)
			draw_circle(ic, 3.2, col)
			for i in 4:
				var a := float(i) * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				draw_line(ic + d * (cr + 3.0), ic + d * (cr + 10.0), col, 2.4, true)
		"aim":
			var ar := r * 0.25
			draw_arc(ic, ar, 0.0, TAU, 28, col, 2.2, true)
			draw_line(ic - Vector2(ar + 5.0, 0.0), ic + Vector2(ar + 5.0, 0.0), col, 1.8)
			draw_line(ic - Vector2(0.0, ar + 5.0), ic + Vector2(0.0, ar + 5.0), col, 1.8)
		"jump":
			var s := r * 0.24
			draw_polyline(PackedVector2Array([
				ic + Vector2(-s, s * 0.4),
				ic + Vector2(0.0, -s * 0.7),
				ic + Vector2(s, s * 0.4),
			]), col, 2.8, true)
			draw_line(ic + Vector2(0.0, -s * 0.6), ic + Vector2(0.0, s * 0.8), col, 2.6)
		"crouch":
			var cs := r * 0.23
			draw_polyline(PackedVector2Array([
				ic + Vector2(-cs, -cs * 0.45),
				ic + Vector2(0.0, cs * 0.45),
				ic + Vector2(cs, -cs * 0.45),
			]), col, 2.8, true)
			draw_line(ic + Vector2(-cs, cs * 0.78), ic + Vector2(cs, cs * 0.78), col, 2.4)
		"reload":
			var rr := r * 0.23
			draw_arc(ic, rr, 0.35, TAU - 0.55, 24, col, 2.5, true)
			var tip := ic + Vector2(cos(0.35), sin(0.35)) * rr
			draw_polyline(PackedVector2Array([
				tip + Vector2(-6.0, -3.0),
				tip,
				tip + Vector2(2.0, -7.0),
			]), col, 2.4, true)
		"heal":
			var hs := r * 0.22
			draw_line(ic - Vector2(hs, 0.0), ic + Vector2(hs, 0.0), Color(0.45, 1.0, 0.62), 5.0)
			draw_line(ic - Vector2(0.0, hs), ic + Vector2(0.0, hs), Color(0.45, 1.0, 0.62), 5.0)
		"bag":
			var bw := r * 0.22
			var bh := r * 0.22
			draw_rect(Rect2(ic - Vector2(bw, bh * 0.7), Vector2(bw * 2.0, bh * 1.7)), col, false, 2.4)
			draw_arc(ic - Vector2(0.0, bh * 0.7), bw * 0.52, PI, TAU, 14, col, 2.2, true)
		"eject":
			var pr := r * 0.25
			draw_arc(ic - Vector2(0.0, 2.0), pr, PI, TAU, 24, col, 3.2, true)
			draw_line(ic - Vector2(pr, 2.0), ic + Vector2(pr, -2.0), col, 2.2)
			draw_line(ic - Vector2(pr * 0.75, 2.0), ic + Vector2(0.0, pr * 0.85), col, 1.8)
			draw_line(ic + Vector2(pr * 0.75, -2.0), ic + Vector2(0.0, pr * 0.85), col, 1.8)
		"sprint":
			var sp := r * 0.20
			for k in 2:
				var oy := float(k) * 7.0 - 3.0
				draw_polyline(PackedVector2Array([
					ic + Vector2(-sp, oy + 4.0),
					ic + Vector2(0.0, oy - 4.0),
					ic + Vector2(sp, oy + 4.0),
				]), col, 2.3, true)
