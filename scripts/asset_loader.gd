extends RefCounted
##
## AssetLoader — download kiye gaye CC0 models (Quaternius / Kenney) runtime pe load karta hai.
##
## Ye file HYBRID asset system ka "loader" hissa hai:
##   - GitHub Actions `assets/downloaded/<category>/` me FBX ko GLB me badalta hai
##     (dekho tools/fbx2glb.py + workflow step "7d"), aur Godot import ke waqt
##     usi folder se .glb padh leta hai
##   - ye script wahan se unhe load karta hai (PackedScene)
##   - Agar kuch bhi na mile (folder khali, file delete, download fail) to chup-chaap
##     `null` deta hai -> scripts/assets.gd ka procedural fallback chalta hai
##
## DHYAAN DO: Godot 4 na .fbx import kar sakta hai na runtime pe load — isliye build
## ke waqt FBX -> GLB conversion hoti hai. Loader dono jagah dhundhta hai:
##   1. res://assets/downloaded/<category>/   (CI ka fresh converted output)
##   2. res://assets/models/<category>/       (agar tum khud GLB repo me daalo)
##
## Sab kuch SAFE hai: folder na ho, file kharab ho, PCK me list na aaye — koi error
## nahi aata, bas null milta hai. Isliye game KABSE asset ki wajah se nahi rukta.
##
## Static cache hai, isliye ek hi model baar-baar disk se nahi padha jaata.
##
## Istemal (assets.gd / player.gd / enemy.gd me):
##     const Loader := preload("res://scripts/asset_loader.gd")
##     var scene := Loader.load_model("ar_5", "weapons")     # PackedScene ya null
##     var scene := Loader.load_variant(NATURE_POOL, "nature", 3)   # random/variant pick
##

## Jahan models dhundhne hain (order matlab rakhta hai: pehla jeetega)
const BASE_DIRS: Array[String] = ["res://assets/downloaded/", "res://assets/models/"]

## Kaunse formats chalte hain. GLB sabse pehle (self-contained: mesh + material ek hi file me).
## .fbx list me sirf isliye hai ki agar koi Godot build usko import kar le to kaam kare —
## normally wo skip ho jata hai (Godot 4 me FBX importer nahi hai).
const EXTENSIONS: Array[String] = [".glb", ".gltf", ".fbx"]

## Saari categories (stats / debug ke liye)
const CATEGORIES: Array[String] = ["weapons", "nature", "characters", "vehicles"]

## character files ka asli naam — male_1..male_8 / female_1..female_8 alias inhi pe jaate hain
const CHARACTER_FILES := {
	"male": ["Male_Casual", "Male_LongSleeve", "Male_Shirt", "Male_Suit",
		"Smooth_Male_Casual", "Smooth_Male_LongSleeve", "Smooth_Male_Shirt", "Smooth_Male_Suit"],
	"female": ["Female_Casual", "Female_TankTop", "Female_Dress", "Female_Alternative",
		"Smooth_Female_Casual", "Smooth_Female_TankTop", "Smooth_Female_Dress",
		"Smooth_Female_Alternative"],
}

## vehicle aliases: jo maanga gaya naam -> asli files (upload me sirf 5 vehicle hain)
const VEHICLE_FILES := {
	"cop_car": ["Cop"],
	"taxi": ["Taxi"],
	"suv": ["SUV"],
	"sedan": ["Sedan", "SportsCar"],
	"sedan_2": ["Sedan2", "SportsCar2"],
	"sports": ["SportsCar"],
	"sports_2": ["SportsCar2"],
}

## prefix -> asli FBX naam ka pattern (nature + weapons ke liye)
const FILE_PREFIXES := {
	"weapons": {
		"ar": "AssaultRifle", "sniper": "SniperRifle", "smg": "SubmachineGun",
		"bullpup": "Bullpup", "shotgun": "Shotgun",
	},
	"nature": {
		"pine": "PineTree", "rock": "Rock", "plant": "Plant", "grass": "Grass",
	},
}

## khaas aliases (prefix rule me nahi aate)
const SPECIAL_ALIASES := {
	"nature": {
		"plant_flowers": ["Plant_Flowers"],
		"flowers": ["Plant_Flowers"],
		"grass_small": ["Grass_Small"],
		"grass_large": ["Grass_Large"],
		"grass_large_2": ["Grass_Large_Extruded"],
		"grass_large_extruded": ["Grass_Large_Extruded"],
		"pine_5": ["PineTree_1"],          # sirf 4 pine files hain -> 5th alias pehle pe
	},
	"characters": {
		"female_alternative": ["Female_Alternative"],
		"smooth_female_alternative": ["Smooth_Female_Alternative"],
	},
}


# ---------------------------------------------------------- static storage ---

## category/name -> PackedScene (ya null). Static = poore project me ek hi baar load.
static var _cache: Dictionary = {}

## "<dir>|<category>" -> Array[String] (asli case wale naam, extension ke bina)
static var _listings: Dictionary = {}

## ek hi warning baar-baar na aaye
static var _warned: Dictionary = {}

## "res://assets/downloaded/|characters" -> asli folder ka naam (case bhi match karta hai,
## kyunki upload me "Characters" capital me hai aur Linux/Android case-sensitive hain)
static var _dir_cache: Dictionary = {}

## Test/debug ke liye: isko set karo to sirf yahi folder dhundha jayega
## (scripts/selftest.gd isko use karke "sab file gayab" wala case check karta hai)
static var base_dir_override: String = ""


# ============================================================ PUBLIC API =====

## Ek category ke saare model naam (extension ke bina, asli case me, dono folders ka mel).
static func list_models(category: String = "nature") -> Array[String]:
	var names: Array[String] = []
	var seen := {}
	for dir_path in search_dirs():
		for bare in _list_dir(dir_path, category):
			var key := bare.to_lower()
			if seen.has(key):
				continue
			seen[key] = true
			names.append(bare)
	names.sort()
	return names


## Naam ke hisse se model dhundo -> PackedScene, warna null (kabhi crash nahi).
## Match order: exact naam -> naam se shuru -> naam me kahin bhi.
static func load_model(name_fragment: String, category: String = "nature") -> PackedScene:
	if name_fragment.strip_edges().is_empty():
		return null
	var key := category + "/" + name_fragment
	if _cache.has(key):
		return _cache[key]
	var scene := _try_load(name_fragment, category)
	_cache[key] = scene
	return scene


## Pool me se ek variant uthao (randf/int pick ke liye) — variant index wrap ho jata hai.
## `names` ek Array[String] hota hai jaise ["pine_1", "pine_2", ...] ya ["ar_1", ...].
static func load_variant(names: Array, category: String, variant: int = 0) -> PackedScene:
	if names.is_empty():
		return null
	var idx := absi(variant) % names.size()
	return load_model(str(names[idx]), category)


## Us naam ka poora res:// path (ya ""). Debug/HUD ke liye.
static func find_path(name_fragment: String, category: String = "nature") -> String:
	return _resolve(name_fragment, category)


## Kisi bhi category me kuch download hua hai?
static func has_models(category: String = "nature") -> bool:
	return not list_models(category).is_empty()


## Saari categories me kuch bhi hai?
static func has_any_models() -> bool:
	for category in CATEGORIES:
		if has_models(category):
			return true
	return false


## Cache khali karo (tests ke liye; normally zaroorat nahi)
static func clear_cache() -> void:
	_cache.clear()
	_listings.clear()
	_warned.clear()
	_dir_cache.clear()


## Kis category me kitni files mili — CI summary / debug HUD ke liye.
static func stats() -> Dictionary:
	var out := {}
	for category in CATEGORIES:
		out[category] = list_models(category).size()
	return out


## Insaani zubaan me report (GitHub Actions summary + selftest isko print karte hain)
static func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("AssetLoader dirs: " + ", ".join(search_dirs()))
	for category in CATEGORIES:
		var names := list_models(category)
		lines.append("  %-11s %2d model%s" % [category, names.size(), "" if names.size() == 1 else "s"])
	return lines


## Jahan folders dhundhne hain
static func search_dirs() -> Array[String]:
	if not base_dir_override.is_empty():
		return [base_dir_override]
	return BASE_DIRS.duplicate()


## category ke asli folder ka poora path (case-agnostic) — "" agar folder hi nahi hai.
## Public hai taaki debug/HUD bata sake ki models kahan se aa rahe hain.
static func category_dir(dir_path: String, category: String) -> String:
	var key := dir_path + "|" + category
	if _dir_cache.has(key):
		return _dir_cache[key]

	var found := ""
	if DirAccess.dir_exists_absolute(dir_path + category):
		found = dir_path + category
	else:
		# "characters" maanga, folder "Characters" hai -> dhundh lo
		var parent := DirAccess.open(dir_path)
		if parent != null:
			for sub in parent.get_directories():
				if sub.to_lower() == category.to_lower():
					found = dir_path + sub
					break
	_dir_cache[key] = found
	return found


# ============================================================== INTERNAL ======

## Folder path (trailing slash ke saath) — listing ke andar path banane ke liye
static func _list_dir_path(dir_path: String, category: String) -> String:
	var folder := category_dir(dir_path, category)
	if folder.is_empty():
		return ""
	return folder.rstrip("/") + "/"


## Ek folder me pada model files (extension ke bina). Cache hota hai.
static func _list_dir(dir_path: String, category: String) -> Array[String]:
	var key := dir_path + "|" + category
	if _listings.has(key):
		return _listings[key]

	var names: Array[String] = []
	var folder := category_dir(dir_path, category)

	# Folder hi nahi hai (download fail / assets skip)? Koi error nahi — khali list.
	# dir_exists_absolute() res:// paths ke saath bhi kaam karta hai.
	if folder.is_empty():
		# assets/models/ optional hai (tum khud GLB daalo to) — sirf main folder ka warning
		if dir_path == BASE_DIRS[0]:
			_warn_once("missing:" + dir_path + category,
					"AssetLoader: folder nahi mila -> %s%s (procedural fallback chalega)"
					% [dir_path, category])
		_listings[key] = names
		return names

	var dir := DirAccess.open(folder)
	if dir == null:
		_warn_once("open:" + folder, "AssetLoader: folder khul nahi paya -> " + folder)
		_listings[key] = names
		return names

	for file_name in dir.get_files():
		var clean := _strip_suffix(file_name)
		var ext := clean.get_extension().to_lower()
		if not EXTENSIONS.has("." + ext):
			continue
		var bare := clean.substr(0, clean.length() - ext.length() - 1)
		if bare.is_empty() or bare.begins_with("."):
			continue                                   # .gitkeep / dot files skip
		names.append(bare)

	names.sort()          # deterministic (warna PCK ki listing ka order badal sakta hai)
	_listings[key] = names
	return names


## Naam -> alias list (jaise "ar_5" -> ["ar_5", "AssaultRifle_5"])
static func _alias_candidates(name: String, category: String) -> PackedStringArray:
	var frag := name.strip_edges()
	var out := PackedStringArray([frag])
	var lower := frag.to_lower()

	# ---- khaas alias (nature/characters) ----
	var special: Dictionary = SPECIAL_ALIASES.get(category, {})
	if special.has(lower):
		for extra in special[lower]:
			out.append(str(extra))
		return out

	# ---- vehicles ----
	if category == "vehicles":
		if VEHICLE_FILES.has(lower):
			for extra in VEHICLE_FILES[lower]:
				out.append(str(extra))
		return out

	# ---- characters: male_3 -> Male_Shirt ----
	for gender in ["male", "female"]:
		if lower.begins_with(gender + "_"):
			var tail := lower.trim_prefix(gender + "_")
			if tail.is_valid_int():
				var files: Array = CHARACTER_FILES[gender]
				var idx := (int(tail) - 1) % files.size()
				out.append(str(files[idx]))
			return out

	# ---- weapons/nature: ar_5 -> AssaultRifle_5, pine_2 -> PineTree_2 ----
	var prefixes: Dictionary = FILE_PREFIXES.get(category, {})
	var parts := lower.split("_", false)
	if parts.size() >= 2:
		var head := parts[0]
		var tail_num := parts[parts.size() - 1]
		if prefixes.has(head) and tail_num.is_valid_int():
			out.append(str(prefixes[head]) + "_" + tail_num)
		elif prefixes.has(lower):
			out.append(str(prefixes[lower]))
	return out


## Fragment -> asli file ka poora path (ya ""). Pehle downloaded, phir models folder.
static func _resolve(name_fragment: String, category: String) -> String:
	var fragment := name_fragment.strip_edges().to_lower()
	if fragment.is_empty():
		return ""

	var candidates := _alias_candidates(name_fragment, category)
	for dir_path in search_dirs():
		var files := _list_dir(dir_path, category)
		if files.is_empty():
			continue
		var folder := _list_dir_path(dir_path, category)

		# 1) exact match (case ignore) — sabse pehle, isliye "ar_5" hamesha AssaultRifle_5 hi dega
		for cand in candidates:
			var want := str(cand).to_lower()
			for f in files:
				if f.to_lower() == want:
					return _pick_existing(folder, f)

		# 2) naam se shuru
		for cand in candidates:
			var want := str(cand).to_lower()
			for f in files:
				if f.to_lower().begins_with(want):
					return _pick_existing(folder, f)

		# 3) naam me kahin bhi
		for cand in candidates:
			var want := str(cand).to_lower()
			for f in files:
				if f.to_lower().contains(want):
					return _pick_existing(folder, f)

		# 4) aakhri sahara: "_3" jaisa number hata ke dekho ("sniper_4" -> koi bhi sniper)
		var parts := fragment.split("_", false)
		if parts.size() >= 2:
			var word := parts[0]
			for f in files:
				if f.to_lower().contains(word):
					_warn_once("fuzzy:" + category + "/" + fragment,
							"AssetLoader: '%s' nahi mila -> '%s' use kar rahe hain" % [name_fragment, f])
					return _pick_existing(folder, f)
	return ""


## Folder + bare naam se pehla maujood extension ka path
static func _pick_existing(folder: String, bare: String) -> String:
	for ext in EXTENSIONS:
		var path := folder + bare + ext
		if ResourceLoader.exists(path):
			return path
	return ""


## Ek model load karne ki koshish. Fail hone pe null (koi error nahi).
static func _try_load(name_fragment: String, category: String) -> PackedScene:
	var path := _resolve(name_fragment, category)
	if path.is_empty():
		_warn_once("miss:" + category + "/" + name_fragment,
				"AssetLoader: model nahi mila -> %s/%s (procedural fallback)" % [category, name_fragment])
		return null

	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	_warn_once("bad:" + path, "AssetLoader: %s PackedScene nahi hai -> skip" % path)
	return null


## Exported PCK me kabhi kabhi ".remap"/".import" laga hua naam aata hai -> hata do
static func _strip_suffix(file_name: String) -> String:
	var clean := file_name
	if clean.ends_with(".remap"):
		clean = clean.trim_suffix(".remap")
	elif clean.ends_with(".import"):
		clean = clean.trim_suffix(".import")
	return clean


## Ek hi warning ek baar (log spam na ho)
static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
