extends Control
##
## Virtual joystick (mobile touch controls)
##
## Spec: "Left half of screen = movement joystick (touch drag)".
## Isliye ye Control poore LEFT HALF ko cover karta hai (hud.tscn me anchors
## dekho) — screen ke left hisse me jahan chaho ungli rakho, wahi joystick ka
## center ban jata hai (Free Fire jaisa). Ungli chhodne pe ghera bottom-left pe
## wapas aa jata hai.
##
## output = Vector2 (-1..1, -1..1)   -> x = left/right, y = up/down (-1 = aage)
## Drawing bhi khud karta hai (draw_circle), koi image/asset nahi chahiye.
##

@export var base_radius: float = 92.0    ## bade ghere ka radius
@export var knob_radius: float = 38.0    ## andar wale knob ka radius
@export var dead_zone: float = 0.12      ## itna hilne tak kuch na ho
@export var margin: float = 40.0         ## screen ke kinare se itna andar

var output: Vector2 = Vector2.ZERO

var _pointer_id: int = -1                 ## -1 = kuch nahi, -2 = mouse, >=0 = touch index
var _knob_offset: Vector2 = Vector2.ZERO
var _touch_device: bool = false
var _center: Vector2 = Vector2.ZERO       ## ghera kahan hai (ungli ke neeche / resting spot)
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP     # touch yahin ruk jaye (look na ho)
	_touch_device = DisplayServer.is_touchscreen_available()
	resized.connect(_reset_center)
	_reset_center()


## Jab kuch nahi chal raha: ghera bottom-left me aaram se pada rahe
func _reset_center() -> void:
	_center = Vector2(minf(size.x * 0.5, base_radius + margin), size.y - base_radius - margin)
	queue_redraw()


## Ghera screen ke andar hi rahe (kinare se bahar na nikle)
func _clamp_center(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, base_radius, size.x - base_radius),
		clampf(pos.y, base_radius, size.y - base_radius))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_id == -1:
				_pointer_id = event.index
				_active = true
				_center = _clamp_center(event.position)   # jahan ungli rakhi = naya center
				_update_knob(event.position - _center)
		elif event.index == _pointer_id:
			_release()
		return

	if event is InputEventScreenDrag:
		if event.index == _pointer_id:
			_update_knob(event.position - _center)
		return

	if _touch_device:
		return   # touch device pe emulated mouse events ignore karo (warna double input)

	# PC: jab mouse FPS mode me capture hai (aim/fire kar rahe ho) to joystick ko
	# haath mat lagao — warna left half me click karne pe player chalne lag jaye
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pointer_id == -1:
				_pointer_id = -2
				_active = true
				_center = _clamp_center(event.position)
				_update_knob(event.position - _center)
		elif _pointer_id == -2:
			_release()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		_update_knob(event.position - _center)


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
	var base_alpha: float = 0.16 if _active else 0.10
	var ring_alpha: float = 0.5 if _active else 0.35
	# bahar wala ghera
	draw_circle(_center, base_radius, Color(1, 1, 1, base_alpha))
	draw_arc(_center, base_radius, 0.0, TAU, 64, Color(1, 1, 1, ring_alpha), 3.0, true)
	# andar wala knob
	draw_circle(_center + _knob_offset, knob_radius, Color(1, 1, 1, 0.30))
	draw_arc(_center + _knob_offset, knob_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0, true)
