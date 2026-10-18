extends RefCounted
##
## MapData — saare Battle Royale maps ke NAAM aur details, ek hi table me.
##
## Sirf data hai, koi logic/scene nahi banta yahan se. Map ka naam badalna ho
## to bas yahan "name" badal do — main.gd / map.gd dono yahi table padhte hain.
##
##   id       = code ke liye chhota naam (badalna mat, isse map pehchana jata hai)
##   name     = screen pe dikhne wala naam (NAAM badalna hai to yahi badlo)
##   scene    = map ki .tscn file ("" = abhi bana nahi hai, sirf naam reserve hai)
##   playable = abhi khel sakte hain ya nahi (false = "coming soon" wala map)
##   size_m   = map ka size metres me (ek kinare se doosre kinare tak)
##   desc     = ek line me map kaisa hai (future map-select screen ke liye)
##
## Abhi 2 maps khele ja sakte hain; baaki 3 sirf naam hain — unki scenes
## baad me banengi, par roster pehle se taiyaar hai (Free Fire style).
##

## Default map — BATTLE dabane pe yahi khulta hai (scenes/main.tscn)
const DEFAULT_MAP_ID := "Veergarh"

## Saare maps. Order = map-select screen me dikhne wala order.
const MAPS := [
	{
		"id": "Veergarh",
		"name": "Veergarh",
		"scene": "res://scenes/main.tscn",
		"playable": true,
		"size_m": 2000,
		"desc": "Center me kasba (Chowk, Haveli, Khet...) aur chaaron taraf 2km khula maidan + samundar.",
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


## Saare maps ki list (naam sahit)
static func get_maps() -> Array:
	return MAPS


## Sirf khele ja sakne wale maps
static func get_playable_maps() -> Array:
	var out: Array = []
	for m in MAPS:
		if bool(m.get("playable", false)):
			out.append(m)
	return out


## id -> map ka Dictionary (na mile to khaali {})
static func get_map(map_id: String) -> Dictionary:
	for m in MAPS:
		if String(m.get("id", "")) == map_id:
			return m
	return {}


## id -> screen pe dikhne wala naam (na mile to id hi wapas)
static func display_name(map_id: String) -> String:
	var m := get_map(map_id)
	if m.is_empty():
		return map_id
	return String(m.get("name", map_id))


## Index -> map (character_data.gd jaisa pattern; range ke bahar = wrap)
static func get_map_by_index(index: int) -> Dictionary:
	if MAPS.is_empty():
		return {}
	return MAPS[wrapi(index, 0, MAPS.size())]
