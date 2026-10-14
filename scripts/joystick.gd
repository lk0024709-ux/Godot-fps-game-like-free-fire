extends Control
##
## Virtual joystick (mobile touch controls)
## Control ke andar touch/mouse drag se output nikalta hai:
##   output = Vector2 (-1..1, -1..1)   -> x = left/right, y = up/down (-1 = aage)
## Drawing bhi khud karta hai (draw_circle), koi image/asset nahi chahiye.
##

@export var base_radius: float = 92.0    ## bade ghere ka radius
@export var knob_radius: float = 38.0    ## andar wale knob ka radius
@export var dead_zone: float = 0.12      ## itna hilne tak kuch na ho

var output: Vector2 = Vector2.ZERO

var _pointer_id: int = -1                 ## -1 = kuch nahi, -2 = mouse, >=0 = touch index
var _knob_offset: Vector2 = Vector2.ZERO
var _touch_device: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP     # touch yahin ruk jaye (look na ho)
	_touch_device = DisplayServer.is_touchscreen_available()
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	var center := size * 0.5

	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_id == -1:
				_pointer_id = event.index
				_update_knob(event.position - center)
		elif event.index == _pointer_id:
			_release()
		return

	if event is InputEventScreenDrag:
		if event.index == _pointer_id:
			_update_knob(event.position - center)
		return

	if _touch_device:
		return   # touch device pe emulated mouse events ignore karo (warna double input)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer_id == -1:
				_pointer_id = -2
				_update_knob(event.position - center)
		elif _pointer_id == -2:
			_release()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		_update_knob(event.position - center)


func _update_knob(offset: Vector2) -> void:
	_knob_offset = offset.limit_length(base_radius)
	output = _knob_offset / base_radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	queue_redraw()


func _release() -> void:
	_pointer_id = -1
	_knob_offset = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	# bahar wala ghera
	draw_circle(center, base_radius, Color(1, 1, 1, 0.10))
	draw_arc(center, base_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 3.0, true)
	# andar wala knob
	draw_circle(center + _knob_offset, knob_radius, Color(1, 1, 1, 0.30))
	draw_arc(center + _knob_offset, knob_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0, true)
