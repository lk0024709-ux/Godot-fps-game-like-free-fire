extends Control
##
## Dynamic Virtual Joystick (Bottom-Left Mobile Multi-Touch Control)
##
## - Dynamic origin: wherever the player places their finger in the bottom-left zone
##   becomes the joystick center; releasing smoothly snaps back to the resting position.
## - Tracks its own dedicated touch `index` and calls `accept_event()` so simultaneous
##   touches on Fire / Aim / Jump / Crouch / Reload / Right-half Camera Look all work
##   independently without interference (true multi-touch).
##

@export var base_radius: float = 84.0
@export var knob_radius: float = 34.0
@export var dead_zone: float = 0.12
@export var margin: float = 36.0

var output: Vector2 = Vector2.ZERO

var _pointer_id: int = -1        ## -1 = idle, -2 = mouse, >= 0 = touch index
var _knob_offset: Vector2 = Vector2.ZERO
var _touch_device: bool = false
var _center: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_device = DisplayServer.is_touchscreen_available()
	resized.connect(_reset_center)
	_reset_center()


func _reset_center() -> void:
	var rx := clampf(base_radius + margin + 12.0, base_radius, maxf(base_radius, size.x - base_radius))
	var ry := clampf(size.y - base_radius - margin, base_radius, maxf(base_radius, size.y - base_radius))
	_center = Vector2(rx, ry)
	queue_redraw()


func _clamp_center(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, base_radius, maxf(base_radius, size.x - base_radius)),
		clampf(pos.y, base_radius, maxf(base_radius, size.y - base_radius))
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _pointer_id == -1:
				_pointer_id = touch.index
				_active = true
				_center = _clamp_center(touch.position)
				_update_knob(touch.position - _center)
				accept_event()
		elif touch.index == _pointer_id:
			_release()
			accept_event()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer_id:
			_update_knob(drag.position - _center)
			accept_event()
		return

	if _touch_device:
		return

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer_id == -1:
				_pointer_id = -2
				_active = true
				_center = _clamp_center(event.position)
				_update_knob(event.position - _center)
				accept_event()
		elif _pointer_id == -2:
			_release()
			accept_event()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		_update_knob(event.position - _center)
		accept_event()


func _update_knob(offset: Vector2) -> void:
	_knob_offset = offset.limit_length(base_radius)
	output = _knob_offset / base_radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	queue_redraw()


func _release() -> void:
	_pointer_id = -1
	_active = false
	_knob_offset = Vector2.ZERO
	output = Vector2.ZERO
	_reset_center()


func _draw() -> void:
	var outer_fill := Color(0.05, 0.09, 0.14, 0.42 if _active else 0.28)
	var outer_ring := Color(0.35, 0.86, 0.98, 0.78 if _active else 0.46)
	var gold_accent := Color(1.0, 0.80, 0.28, 0.88 if _active else 0.55)

	draw_circle(_center, base_radius, outer_fill)
	draw_arc(_center, base_radius, 0.0, TAU, 64, outer_ring, 2.6, true)
	draw_arc(_center, base_radius - 6.0, 0.0, TAU, 48, Color(1, 1, 1, 0.10), 1.2, true)

	# 4 directional ticks around outer ring
	for i in 4:
		var ang := float(i) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(
			_center + dir * (base_radius - 13.0),
			_center + dir * (base_radius - 4.0),
			gold_accent,
			2.4,
			true
		)

	var knob_pos := _center + _knob_offset
	draw_circle(knob_pos, knob_radius, Color(0.95, 0.80, 0.30, 0.52 if _active else 0.30))
	draw_circle(knob_pos, knob_radius * 0.62, Color(1.0, 0.94, 0.72, 0.72 if _active else 0.44))
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 48, gold_accent, 2.5, true)
