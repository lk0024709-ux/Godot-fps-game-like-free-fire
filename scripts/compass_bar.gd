extends Control
##
## CompassBar — Top-Center Battle Royale Bearing Ribbon
##
## Displays continuous horizontal cardinal & intercardinal headings (`N, NE, E, SE, S, SW, W, NW`),
## 15-degree tick marks, and the exact live numeric bearing (`0..359°`) as the player rotates.
## Strictly non-interactive (`mouse_filter = Control.MOUSE_FILTER_IGNORE`).
##

const CARDINAL_LABELS := {
	0: "N",
	45: "NE",
	90: "E",
	135: "SE",
	180: "S",
	225: "SW",
	270: "W",
	315: "NW",
}

const FOV_SPAN_DEG: float = 150.0

var bearing_deg: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_from_yaw(yaw_rad: float) -> void:
	var deg := fposmod(rad_to_deg(-yaw_rad), 360.0)
	if absf(deg - bearing_deg) > 0.05:
		bearing_deg = deg
		queue_redraw()


func get_cardinal_string() -> String:
	var idx := int(round(bearing_deg / 45.0)) % 8
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return "%s · %03d°" % [names[idx], int(round(bearing_deg)) % 360]


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 10.0 or h <= 10.0:
		return

	# Translucent obsidian glass backing + gold top hairline
	var strip_h := 28.0
	draw_rect(Rect2(0.0, 0.0, w, strip_h), Color(0.04, 0.07, 0.12, 0.66), true)
	draw_line(Vector2(0.0, 0.0), Vector2(w, 0.0), Color(0.96, 0.80, 0.30, 0.72), 1.8)
	draw_line(Vector2(0.0, strip_h), Vector2(w, strip_h), Color(0.32, 0.85, 0.98, 0.35), 1.0)

	var font := get_theme_default_font()
	var px_per_deg := w / FOV_SPAN_DEG
	var half_span := FOV_SPAN_DEG * 0.5
	var first_tick := int(floor((bearing_deg - half_span) / 15.0)) * 15
	var last_tick := int(ceil((bearing_deg + half_span) / 15.0)) * 15

	for raw_deg in range(first_tick, last_tick + 1, 15):
		var delta_deg := float(raw_deg) - bearing_deg
		if absf(delta_deg) > half_span:
			continue
		var x := w * 0.5 + delta_deg * px_per_deg
		var norm_deg := ((raw_deg % 360) + 360) % 360
		var edge_fade := clampf(1.0 - absf(delta_deg) / half_span, 0.18, 1.0)

		if CARDINAL_LABELS.has(norm_deg):
			var label: String = CARDINAL_LABELS[norm_deg]
			var is_north := norm_deg == 0
			var is_major := (norm_deg % 90) == 0
			var col := Color(1.0, 0.42, 0.30, edge_fade) if is_north else (
				Color(1.0, 0.88, 0.42, edge_fade) if is_major else Color(0.92, 0.96, 1.0, edge_fade * 0.92)
			)
			draw_line(Vector2(x, 2.0), Vector2(x, 9.0), col, 2.0)
			if font != null:
				var fsz := 14 if is_major else 12
				draw_string_outline(font, Vector2(x - 16.0, 23.0), label, HORIZONTAL_ALIGNMENT_CENTER, 32.0, fsz, 3, Color(0, 0, 0, 0.8 * edge_fade))
				draw_string(font, Vector2(x - 16.0, 23.0), label, HORIZONTAL_ALIGNMENT_CENTER, 32.0, fsz, col)
		else:
			draw_line(Vector2(x, 3.0), Vector2(x, 8.0), Color(0.80, 0.86, 0.94, 0.55 * edge_fade), 1.2)
			if font != null and (norm_deg % 30) == 0:
				draw_string(
					font,
					Vector2(x - 16.0, 21.0),
					str(norm_deg),
					HORIZONTAL_ALIGNMENT_CENTER,
					32.0,
					10,
					Color(0.76, 0.84, 0.92, 0.72 * edge_fade)
				)

	# Center pointer triangle + live numeric bearing pill below ribbon
	var cx := w * 0.5
	var ptr := PackedVector2Array([
		Vector2(cx - 6.0, 0.0),
		Vector2(cx + 6.0, 0.0),
		Vector2(cx, 7.0),
	])
	draw_colored_polygon(ptr, Color(1.0, 0.84, 0.24, 1.0))

	if font != null:
		var badge_w := 88.0
		var badge_rect := Rect2(cx - badge_w * 0.5, strip_h + 3.0, badge_w, 17.0)
		draw_rect(badge_rect, Color(0.05, 0.09, 0.15, 0.84), true)
		draw_rect(badge_rect, Color(1.0, 0.82, 0.28, 0.75), false, 1.2)
		var readout := get_cardinal_string()
		draw_string(
			font,
			Vector2(badge_rect.position.x, badge_rect.position.y + 13.0),
			readout,
			HORIZONTAL_ALIGNMENT_CENTER,
			badge_w,
			11,
			Color(1.0, 0.94, 0.74, 1.0)
		)
