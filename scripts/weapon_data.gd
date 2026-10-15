extends RefCounted
##
## WeaponData — 28 weapons ke saare stats + skin colours (Free Fire style).
## Sirf data hai, koi logic nahi. weapon_manager.gd isko padhta hai.
##
## Har weapon ek Dictionary hai (keys neeche _gun() me saaf likhe hain):
##   name, shape, damage, pellets, fire_rate, ammo, auto, reload,
##   body, accent, spread, bullet_speed, recoil
##
## NOTE: shape sirf 5 me se ek ho sakta hai -> assets.gd wahi 5 base models banata hai.
##

# ------------------------------------------------------------ model shapes ----
const PISTOL := "pistol"
const SMG := "smg"
const RIFLE := "rifle"
const SNIPER := "sniper"
const SHOTGUN := "shotgun"

# --------------------------------------------------------------- colours -----
# Skin colours (sirf albedo — koi texture nahi)
const GOLD := Color(0.85, 0.68, 0.22)
const SILVER := Color(0.72, 0.74, 0.78)
const BLACK := Color(0.08, 0.08, 0.09)
const GREY := Color(0.42, 0.44, 0.47)
const WHITE := Color(0.85, 0.86, 0.88)
const BROWN := Color(0.34, 0.21, 0.11)
const WOOD := Color(0.55, 0.36, 0.17)
const TAN := Color(0.66, 0.57, 0.38)
const GREEN := Color(0.28, 0.42, 0.22)
const DARK_GREEN := Color(0.16, 0.26, 0.16)
const OLIVE := Color(0.35, 0.38, 0.20)
const BLUE := Color(0.16, 0.32, 0.62)
const DARK_BLUE := Color(0.14, 0.18, 0.28)
const RED := Color(0.62, 0.14, 0.12)
const CYAN := Color(0.25, 0.62, 0.68)


## Poori list (index 0..27). Yahi order game me aur gun-picker me dikhta hai.
static func get_weapons() -> Array[Dictionary]:
	return [
		# ---------------------------------------------------------- PISTOLS ----
		_gun("Desert Eagle", PISTOL, 55.0, 0.35, 7, false, GOLD, BLACK),
		_gun("USP", PISTOL, 30.0, 0.28, 12, false, BLACK, GREY),
		_gun("M500", PISTOL, 90.0, 0.90, 5, false, SILVER, GOLD),

		# ------------------------------------------------------------- SMGs ----
		_gun("MP40", SMG, 24.0, 0.070, 30, true, GREY, BROWN),
		_gun("MP5", SMG, 26.0, 0.080, 30, true, BLACK, GREY),
		_gun("UMP", SMG, 32.0, 0.100, 25, true, DARK_BLUE, BLACK),
		_gun("P90", SMG, 25.0, 0.070, 50, true, BLACK, OLIVE),
		_gun("Thompson", SMG, 34.0, 0.090, 30, true, BROWN, WOOD),
		_gun("Bizon", SMG, 22.0, 0.060, 40, true, DARK_GREEN, BLACK),
		_gun("Skorpion", SMG, 20.0, 0.055, 20, true, GREY, BLACK),
		_gun("Vector", SMG, 28.0, 0.050, 25, true, WHITE, RED),

		# ----------------------------------------------------------- RIFLES ----
		_gun("AK", RIFLE, 60.0, 0.15, 30, true, BROWN, WOOD),
		_gun("M4A1", RIFLE, 48.0, 0.11, 30, true, BLACK, GREY),
		_gun("SCAR", RIFLE, 53.0, 0.12, 30, true, TAN, BLACK),
		_gun("Groza", RIFLE, 61.0, 0.14, 30, true, GOLD, BLACK),
		_gun("FAMAS", RIFLE, 54.0, 0.10, 30, true, GREEN, BLACK),
		_gun("M7", RIFLE, 65.0, 0.25, 20, false, GREY, WOOD),
		_gun("XM8", RIFLE, 50.0, 0.12, 30, true, GREY, DARK_GREEN),
		_gun("AUG", RIFLE, 51.0, 0.11, 30, true, TAN, OLIVE),
		_gun("Parafal", RIFLE, 58.0, 0.15, 30, true, DARK_GREEN, BLACK),
		_gun("AN94", RIFLE, 56.0, 0.13, 30, true, DARK_BLUE, GREY),
		_gun("Kingfisher", RIFLE, 55.0, 0.13, 30, true, BLUE, GOLD),

		# ---------------------------------------------------------- SNIPERS ----
		_gun("AWM", SNIPER, 95.0, 1.40, 5, false, DARK_GREEN, BLACK),
		_gun("Kar98k", SNIPER, 88.0, 1.30, 5, false, WOOD, BROWN),
		_gun("M82B", SNIPER, 120.0, 1.80, 5, false, BLACK, GREY),

		# --------------------------------------------------------- SHOTGUNS ----
		# (aakhri number = pellets, yaani ek baar me kitni goliyaan nikalengi)
		_gun("M1014", SHOTGUN, 15.0, 0.80, 8, false, BLACK, GREY, 6),
		_gun("MAG-7", SHOTGUN, 18.0, 0.90, 5, false, GREY, DARK_BLUE, 8),
		_gun("SPAS12", SHOTGUN, 14.0, 0.70, 8, false, BLACK, RED, 6),
	]


## Ek weapon ka Dictionary banata hai.
## spread / bullet_speed / recoil shape (pistol/smg/rifle/sniper/shotgun) ke
## hisaab se set hote hain, baaki sab upar wali table se aata hai.
static func _gun(weapon_name: String, shape: String, damage: float, fire_rate: float,
		magazine: int, automatic: bool, body: Color, accent: Color, pellets: int = 1) -> Dictionary:
	var spread := 0.6          # bullet kitna bhatakta hai (degrees)
	var speed := 55.0          # goli ki raftaar (m/s)
	var recoil := 1.0          # goli chalne pe camera ka jhatka (degrees)

	match shape:
		PISTOL:
			spread = 0.5
			speed = 32.0
			recoil = 1.4
		SMG:
			spread = 1.3
			speed = 40.0
			recoil = 0.6
		RIFLE:
			spread = 0.7
			speed = 55.0
			recoil = 1.0
		SNIPER:
			spread = 0.05
			speed = 110.0
			recoil = 3.2
		SHOTGUN:
			spread = 6.0
			speed = 30.0
			recoil = 3.6
		_:
			pass

	return {
		"name": weapon_name,
		"shape": shape,
		"damage": damage,
		"pellets": pellets,
		"fire_rate": fire_rate,
		"ammo": magazine,
		"auto": automatic,
		"reload": 1.2,
		"body": body,
		"accent": accent,
		"spread": spread,
		"bullet_speed": speed,
		"recoil": recoil,
	}


## HUD ke gun-picker me har button pe chhota category tag dikhane ke liye
static func short_tag(shape: String) -> String:
	match shape:
		PISTOL:
			return "P"
		SMG:
			return "SMG"
		RIFLE:
			return "RFL"
		SNIPER:
			return "SNP"
		SHOTGUN:
			return "SHG"
	return "?"
