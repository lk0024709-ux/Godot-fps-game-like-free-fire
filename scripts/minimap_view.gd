extends Control
##
## MinimapView — Top-Left Live RANNBHOOMI Tactical Minimap + Rotating Player Arrow
##
## - Uses preloaded `res://assets/ui/rannbhoomi_minimap.png` so Android APK export
##   always embeds the high-resolution satellite map texture inside the PCK.
## - Enforces `mouse_filter = Control.MOUSE_FILTER_IGNORE` on itself and its rotating
##   `PlayerArrow` child control so non-interactive HUD elements never block touch input.
##

const MINIMAP_TEXTURE: Texture2D = preload("res://assets/ui/rannbhoomi_minimap.png")
const MAP_WORLD_SPAN: float = 1400.0        ## [-700m .. +700m] matches rannbhoomi_minimap.png
const PLANE_VIEW_UV_SPAN: float = 0.80      ## Wide strategic overview while aboard plane
const GROUND_VIEW_UV_SPAN: float = 0.34     ## ~476m tactical radar window while skydiving/on ground

var player_world_xz: Vector2 = Vector2.ZERO
var bearing_rad: float = 0.0
var in_plane_overview: bool = false
var has_plane: bool = false
var plane_world_xz: Vector2 = Vector2.ZERO
var flight_start_xz: Vector2 = Vector2(-530.33, -530.33)
var flight_end_xz: Vector2 = Vector2(530.33, 530.33)
var enemy_world_positions: Array[Vector2] = []

var _player_arrow: Control = null


class PlayerArrowIndicator extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		# Subtle translucent cyan 64-degree forward field-of-view cone
		var fov_half := deg_to_rad(32.0)
		var cone_len := 36.0
		var cone := PackedVector2Array([
			c,
			c + Vector2(sin(-fov_half), -cos(-fov_half)) * cone_len,
			c + Vector2(0.0, -cone_len * 1.06),
			c + Vector2(sin(fov_half), -cos(fov_half)) * cone_len,
		])
		draw_colored_polygon(cone, Color(0.22, 0.90, 1.0, 0.22))

		# High-contrast notched Battle Royale directional arrow pointing UP (North at rotation=0)
		var outer := PackedVector2Array([
			c + Vector2(0.0, -13.0),
			c + Vector2(9.5, 10.0),
			c + Vector2(0.0, 4.5),
			c + Vector2(-9.5, 10.0),
		])
		var inner := PackedVector2Array([
			c + Vector2(0.0, -10.5),
			c + Vector2(7.2, 7.8),
			c + Vector2(0.0, 3.0),
			c + Vector2(-7.2, 7.8),
		])
		draw_colored_polygon(outer, Color(0.04, 0.07, 0.12, 0.95))
		draw_colored_polygon(inner, Color(1.0, 0.86, 0.28, 1.0))
		draw_circle(c + Vector2(0.0, -1.5), 2.2, Color(1.0, 1.0, 1.0, 0.98))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_ensure_arrow_node()
	resized.connect(_reposition_arrow)
	_reposition_arrow()


func _ensure_arrow_node() -> void:
	var existing := get_node_or_null("PlayerArrow")
	if existing is Control:
		_player_arrow = existing as Control
	else:
		_player_arrow = PlayerArrowIndicator.new()
		_player_arrow.name = "PlayerArrow"
		add_child(_player_arrow)
	_player_arrow.size = Vector2(32.0, 32.0)
	_player_arrow.pivot_offset = Vector2(16.0, 16.0)
	_player_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _reposition_arrow() -> void:
	if _player_arrow == null:
		return
	var target_px := _world_to_canvas(player_world_xz)
	_player_arrow.pivot_offset = _player_arrow.size * 0.5
	_player_arrow.position = target_px - _player_arrow.pivot_offset
	_player_arrow.rotation = bearing_rad
	_player_arrow.queue_redraw()


func update_radar(
	p_world_xz: Vector2,
	p_yaw_rad: float,
	p_in_plane: bool,
	p_enemies: Array[Vector2],
	p_has_plane: bool,
	p_plane_xz: Vector2,
	p_route_start: Vector2,
	p_route_end: Vector2
) -> void:
	player_world_xz = p_world_xz
	bearing_rad = wrapf(-p_yaw_rad, 0.0, TAU)
	in_plane_overview = p_in_plane
	enemy_world_positions = p_enemies
	has_plane = p_has_plane
	plane_world_xz = p_plane_xz
	flight_start_xz = p_route_start
	flight_end_xz = p_route_end
	_ensure_arrow_node()
	_reposition_arrow()
	queue_redraw()


func _world_to_uv(xz: Vector2) -> Vector2:
	return Vector2(
		clampf(0.5 + xz.x / MAP_WORLD_SPAN, 0.0, 1.0),
		clampf(0.5 + xz.y / MAP_WORLD_SPAN, 0.0, 1.0)
	)


func _current_uv_rect() -> Rect2:
	var span := PLANE_VIEW_UV_SPAN if in_plane_overview else GROUND_VIEW_UV_SPAN
	var center_uv := Vector2(0.5, 0.5) if in_plane_overview else _world_to_uv(player_world_xz)
	var half := span * 0.5
	var left := clampf(center_uv.x - half, 0.0, 1.0 - span)
	var top := clampf(center_uv.y - half, 0.0, 1.0 - span)
	return Rect2(left, top, span, span)


func _world_to_canvas(xz: Vector2) -> Vector2:
	var uv := _world_to_uv(xz)
	var rect_uv := _current_uv_rect()
	var nx := (uv.x - rect_uv.position.x) / maxf(rect_uv.size.x, 0.001)
	var ny := (uv.y - rect_uv.position.y) / maxf(rect_uv.size.y, 0.001)
	return Vector2(
		clampf(nx * size.x, 8.0, maxf(8.0, size.x - 8.0)),
		clampf(ny * size.y, 8.0, maxf(8.0, size.y - 8.0))
	)


func _draw() -> void:
	var view_rect := Rect2(Vector2.ZERO, size)
	draw_rect(view_rect, Color(0.03, 0.14, 0.24, 1.0), true)

	if MINIMAP_TEXTURE != null:
		var tex_size := MINIMAP_TEXTURE.get_size()
		var uv_rect := _current_uv_rect()
		var src_rect := Rect2(
			uv_rect.position * tex_size,
			uv_rect.size * tex_size
		)
		draw_texture_rect_region(MINIMAP_TEXTURE, view_rect, src_rect)

	# Flight route overlay + dropship marker while cargo plane is active
	if has_plane:
		var a := _world_to_canvas(flight_start_xz)
		var b := _world_to_canvas(flight_end_xz)
		draw_dashed_line(a, b, Color(0.32, 0.92, 1.0, 0.82), 2.2, 7.0, true)

		var pc := _world_to_canvas(plane_world_xz)
		var dir := (b - a).normalized()
		if dir.length_squared() < 0.01:
			dir = Vector2(0.707, 0.707)
		var perp := Vector2(-dir.y, dir.x)
		var jet := PackedVector2Array([
			pc + dir * 9.0,
			pc - dir * 3.0 + perp * 7.5,
			pc - dir * 7.0,
			pc - dir * 3.0 - perp * 7.5,
		])
		draw_colored_polygon(jet, Color(0.25, 0.95, 1.0, 0.95))

	# Live enemy blips within tactical radar window
	for ep in enemy_world_positions:
		var ec := _world_to_canvas(ep)
		draw_circle(ec, 4.6, Color(0.10, 0.02, 0.02, 0.90))
		draw_circle(ec, 3.2, Color(1.0, 0.24, 0.22, 0.96))

	# Subtle tactical radar border & N badge
	draw_rect(view_rect.grow(-1.0), Color(0.95, 0.78, 0.30, 0.85), false, 2.0)
	var font := get_theme_default_font()
	if font != null:
		draw_circle(Vector2(size.x * 0.5, 11.0), 8.5, Color(0.05, 0.08, 0.14, 0.82))
		draw_string(font, Vector2(size.x * 0.5 - 8.0, 15.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color(1.0, 0.82, 0.30))
