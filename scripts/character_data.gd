extends RefCounted
##
## CharacterData — 10 characters ka data (naam, model, rang) + enemy ke liye pool.
##
## Sirf data hai, koi logic nahi. player.gd (apna body) aur enemy.gd (dushman) dono
## yahi file padhte hain, isliye ek jagah badalne se dono jagah badal jata hai.
##
##   model  = asset_loader.gd ko diya jaane wala naam ("male_1" ... "female_5")
##            Loader inhe asli FBX/GLB files se jodta hai (male_1 -> Male_Casual.glb)
##   body   = kapdon ka rang (material override)
##   accent = doosra rang (pant / cap / detail)
##
## 16 character files uploaded hain (8 male + 8 female) — male_1..male_8 aur
## female_1..female_8 sab chalte hain, lekin game ki roster 10 characters ki hai
## (spec ke mutabik male_1-5 + female_1-5).
##

## Enemy ke liye model pool — spec: "random character: male_1-5 or female_1-5"
const ENEMY_POOL: Array[String] = [
	"male_1", "male_2", "male_3", "male_4", "male_5",
	"female_1", "female_2", "female_3", "female_4", "female_5",
]

## Enemy ka rang — spec: dark red tint (0.55, 0.12, 0.12)
const ENEMY_TINT := Color(0.55, 0.12, 0.12)

## Enemy ki height (m) — model 1.8m me convert hota hai, isliye 1.0 hi rehta hai
const ENEMY_HEIGHT := 1.8

## Player ke body ka rang (character data se override hota hai)
const PLAYER_BODY_LAYER := 2


## Gameplay roster (HUD/selection ke liye). Order yahi rehne do — index se select hota hai.
static func get_characters() -> Array[Dictionary]:
	return [
		_char("Rey", "male_1", Color(0.20, 0.45, 0.75), Color(0.12, 0.16, 0.24)),
		_char("Zen", "male_2", Color(0.16, 0.55, 0.42), Color(0.10, 0.14, 0.16)),
		_char("Vihaan", "female_1", Color(0.72, 0.30, 0.32), Color(0.18, 0.14, 0.16)),
		_char("Ace", "male_3", Color(0.85, 0.72, 0.25), Color(0.22, 0.18, 0.10)),
		_char("Rudra", "male_4", Color(0.35, 0.28, 0.55), Color(0.12, 0.12, 0.18)),
		_char("Ghost", "male_5", Color(0.78, 0.80, 0.84), Color(0.20, 0.22, 0.26)),
		_char("Krish", "female_2", Color(0.30, 0.62, 0.70), Color(0.14, 0.18, 0.22)),
		_char("Blaze", "female_3", Color(0.80, 0.38, 0.16), Color(0.24, 0.14, 0.10)),
		_char("Ayaan", "female_4", Color(0.30, 0.36, 0.30), Color(0.14, 0.16, 0.14)),
		_char("Raze", "female_5", Color(0.55, 0.22, 0.28), Color(0.16, 0.12, 0.14)),
	]


## Ek character ka Dictionary
static func _char(char_name: String, model: String, body: Color, accent: Color) -> Dictionary:
	return {
		"name": char_name,
		"model": model,
		"body": body,
		"accent": accent,
	}


## index -> Dictionary (range ke bahar ho to wrap)
static func get_character(index: int) -> Dictionary:
	var list := get_characters()
	if list.is_empty():
		return {}
	return list[absi(index) % list.size()]


## NOTE: naam `display_name` hai, `get_name` nahi — GDScript (Script resource) ka apna
## `get_name()` 0 arguments leta hai, isliye purana call runtime pe "Invalid call ...
## Expected 0 arguments" deta tha (CI ke map smoke test ne pakda).
static func display_name(index: int) -> String:
	return String(get_character(index).get("name", "Player"))


static func get_model(index: int) -> String:
	return String(get_character(index).get("model", "male_1"))


static func count() -> int:
	return get_characters().size()
