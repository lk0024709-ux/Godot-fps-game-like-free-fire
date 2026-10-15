extends Control
##
## TouchButton — FIRE / JUMP ke liye
##
## Godot ka normal "Button" multi-touch pe kaam nahi karta: engine sirf pehli
## ungli (touch index 0) ko mouse event me convert karta hai. Matlab joystick
## pakde hue doosri ungli se FIRE dabane pe Button ko kuch nahi milta.
## Isliye ye Control khud raw touch events (InputEventScreenTouch/Drag) handle
## karta hai — har touch index apna alag hota hai, isliye multi-touch perfect.
##
## Ghera aur text khud draw hota hai (draw_circle / draw_string) — koi texture nahi.

signal pressed
signal released

@export var label_text: String = "FIRE"
@export var font_size: int = 34
@export var fill_color: Color = Color(0.85, 0.2, 0.15, 0.5)
@export var ring_color: Color = Color(1, 0.65, 0.55, 0.8)
@export var label_color: Color = Color(1, 1, 1, 1)
@export var label_outline: bool = true

var is_down: bool = false

var _pointer: int = -1        ## -1 = kuch nahi, -2 = mouse, >=0 = touch index
var _touch_device: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_device = DisplayServer.is_touchscreen_available()
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer == -1:
				_pointer = event.index
				_set_down(true)
		elif event.index == _pointer:
			_set_down(false)
		return

	if event is InputEventScreenDrag:
		if event.index == _pointer:
			# ungli bahut door chali gayi -> button chhod do
			if event.position.distance_to(size * 0.5) > maxf(size.x, size.y) * 0.75:
				_set_down(false)
		return

	if _touch_device:
		return   # touch device pe emulated mouse events ko ignore karo (warna double)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer == -1:
				_pointer = -2
				_set_down(true)
		elif _pointer == -2:
			_set_down(false)


func _set_down(down: bool) -> void:
	if down:
		if is_down:
			return
		is_down = true
		pressed.emit()
	else:
		_pointer = -1
		if not is_down:
			return
		is_down = false
		released.emit()
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	var fill := fill_color
	var ring := ring_color
	if is_down:
		fill = Color(minf(fill.r + 0.2, 1.0), minf(fill.g + 0.15, 1.0), minf(fill.b + 0.15, 1.0), minf(fill.a + 0.4, 1.0))
		ring = Color(1, 1, 1, 0.95)

	draw_circle(center, radius, fill)
	draw_arc(center, radius - 2.0, 0.0, TAU, 64, ring, 3.0, true)

	if label_text.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(0.0, center.y + text_size.y * 0.5 - font.get_descent(font_size))
	var outline_size: int = 5 if label_outline else 0
	if outline_size > 0:
		draw_string_outline(font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, outline_size, Color(0, 0, 0, 0.7))
	draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, label_color)
