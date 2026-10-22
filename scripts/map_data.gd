extends RefCounted
##
## MapData — saare Battle Royale maps ke NAAM aur details, ek hi table me.
##

## Default map — BATTLE dabane pe yahi khulta hai (scenes/main.tscn)
const DEFAULT_MAP_ID := "Veergarh"

## Saare maps. Order = map-select screen me dikhne wala order.
const MAPS := [
	{
		"id": "Veergarh",
		"name": "Rannbhoomi",
		"scene": "res://scenes/main.tscn",
		"playable": true,
		"size_m": 2000,
		"desc": "Shahi Mahal (0,15,0), NW Aravalli Ghat, Veergram Village, Military Base aur Purana Bazaar.",
	},
	{
		"id": "neel_dweep",
		"name": "Neel Dweep",
		"scene": "res://scenes/map.tscn",
		"playable": true,
		"size_m": 2000,
		"desc": "2km ka pahadi Samudra — beech me 300m plateau, pahadon ka ring, beach aur 4km samundar.",
	},
	{
		"id": "Thar",
		"name": "Thar",
		"scene": "",
		"playable": false,
		"size_m": 2000,
		"desc": "Coming soon — Rajasthan ka registan: ret ke tibbe, purani haveliyan, door tak khali nazara (sniper map).",
	},
	{
		"id": "Himgiri",
		"name": "Himgiri",
		"scene": "",
		"playable": false,
		"size_m": 2000,
		"desc": "Coming soon — barf ke pahad: safed waadiyan, pine ke jungle, fisalne wali dhalanein.",
	},
	{
		"id": "vanraj",
		"name": "Vanraj",
		"scene": "",
		"playable": false,
		"size_m": 2000,
		"desc": "Coming soon — ghana jungle: unche ped, nadi-naale, chhupne ki hazaar jagah.",
	},
]


static func get_maps() -> Array:
	return MAPS


static func get_playable_maps() -> Array:
	var out: Array = []
	for m in MAPS:
		if bool(m.get("playable", false)):
			out.append(m)
	return out


static func get_map(map_id: String) -> Dictionary:
	for m in MAPS:
		if String(m.get("id", "")) == map_id or String(m.get("name", "")) == map_id:
			return m
	return {}


static func display_name(map_id: String) -> String:
	var m := get_map(map_id)
	if m.is_empty():
		return map_id
	return String(m.get("name", map_id))


static func get_map_by_index(index: int) -> Dictionary:
	if MAPS.is_empty():
		return {}
	return MAPS[wrapi(index, 0, MAPS.size())]
