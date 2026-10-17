extends RefCounted
##
## AssetLoader — download kiye gaye CC0 models (Quaternius) runtime pe load karta hai.
##
## Ye file HYBRID asset system ka "loader" hissa hai:
##   0. `assets/downloaded_obj/<category>/` me OBJ source models hote hain (weapons, nature,
##      characters, vehicles) — build ke waqt tools/obj2glb.py unhe bhi .glb banata hai.
##   1. `assets/downloaded/<category>/` me tumhare upload kiye FBX source models rehte hain.
##      Us folder me `.gdignore` pada hai, isliye Godot unhe scan NAHI karta
##      (Godot 4 FBX import nahi kar sakta — aur bade packs pe import atak jata hai).
##   2. GitHub Actions build ke waqt `tools/fbx2glb.py` unhe `.glb` me convert karta hai
##      aur `assets/models/<category>/` me daalta hai (kahin bhi manual kuch nahi karna padta).
##   3. Godot sirf `assets/models/` ko import karta hai, aur ye script wahan se
##      PackedScene load karta hai.
##   4. Agar kuch bhi na mile (folder khali, file delete, conversion fail) to chup-chaap
##      `null` deta hai -> scripts/assets.gd ka procedural fallback chalta hai.
##
## Sab kuch SAFE hai: folder na ho, file kharab ho, PCK me list na aaye — koi error
## nahi aata, bas null milta hai. Isliye game KABHI asset ki wajah se nahi rukta.
##
## Istemal (assets.gd / player.gd / enemy.gd me):
##     const Loader := preload("res://scripts/asset_loader.gd")
##     var scene := Loader.load_model("ar_5", "weapons")       # PackedScene ya null
##     var scene := Loader.load_variant(NATURE_POOL, 3, "nature")
##

## Models kahan dhundhne hain (order matlab rakhta hai: pehla folder jeetta hai).
## "assets/models/"       = CI ne banaye hue .glb (Godot-imported) — asli jagah.
##                          FBX (assets/downloaded) aur OBJ (assets/downloaded_obj) dono
##                          isi me convert hote hain (dekho tools/fbx2glb.py + tools/obj2glb.py).
## "assets/downloaded/"     = FBX source + `.gdignore` (Godot inhe scan nahi karta).
## "assets/downloaded_obj/" = OBJ/MTL source (weapons + nature + characters + vehicles)
##                          + `.gdignore`. Yahan bhi agar koi khud .glb daal de to
##                          wo mil jayega — warna skip.
const BASE_DIRS: Array[String] = ["res://assets/models/", "res://assets/downloaded/",
		"res://assets/downloaded_obj/"]

## Kaunse formats chalte hain. `.fbx`/`.obj` list me hain taaki file naming sahi rahe —
## Godot inhe load nahi kar sakta (isliye CI .glb convert karta hai), aur aisi file
## listing me sirf tab aati hai jab Godot usko sach me load kar sake
## (ResourceLoader.exists() check hota hai).
const EXTENSIONS: Array[String] = [".glb", ".gltf", ".obj", ".fbx"]

## Saari categories
const CATEGORIES: Array[String] = ["weapons", "nature", "characters", "vehicles"]

## character files ke asli naam — male_1..male_8 / female_1..female_8 alias inhi pe jaate hain.
## Spec: **male_1 = Male_Suit** (game roster: Rey = male_1). Baaki files usi order me.
## Pehle 4 normal-poly models, aakhri 4 "Smooth" (zyada detail wale) models.
const CHARACTER_FILES := {
	"male": ["Male_Suit", "Male_Casual", "Male_Shirt", "Male_LongSleeve",
		"Smooth_Male_Suit", "Smooth_Male_Casual", "Smooth_Male_Shirt", "Smooth_Male_LongSleeve"],
	"female": ["Female_Casual", "Female_Dress", "Female_Alternative", "Female_TankTop",
		"Smooth_Female_Casual", "Smooth_Female_Dress", "Smooth_Female_Alternative",
		"Smooth_Female_TankTop"],
}

## vehicle aliases: jo maanga gaya naam -> asli OBJ files (7 uploaded).
## Game ka code purane alias use karta hai (cop_car / sedan / sports_2...) taaki
## weapon/HUD waghaira na badalna pade — yahan mapping hai.
const VEHICLE_FILES := {
	"cop_car": ["Cop"],
	"cop": ["Cop"],
	"taxi": ["Taxi"],
	"suv": ["SUV"],
	"normalcar1": ["NormalCar1"],
	"normalcar2": ["NormalCar2"],
	"sedan": ["NormalCar1"],          # purana alias -> NormalCar1
	"normal_1": ["NormalCar1"],
	"normal_2": ["NormalCar2"],
	"sedan_2": ["NormalCar2"],        # purana alias -> NormalCar2
	"sports": ["SportsCar"],
	"street": ["SportsCar"],
	"sports_2": ["SportsCar2"],       # spec: 1 random SportsCar2
}

## prefix -> asli FBX naam ka pattern (weapons + nature ke liye)
const FILE_PREFIXES := {
	"weapons": {
		"ar": "AssaultRifle", "sniper": "SniperRifle", "smg": "SubmachineGun",
		"submachine": "SubmachineGun", "bullpup": "Bullpup", "shotgun": "Shotgun",
		"pistol": "Pistol", "revolver": "Revolver",
	},
	"nature": {
		"pine": "PineTree", "rock": "Rock", "plant": "Plant", "grass": "Grass",
	},
}

## Upload kiye weapons pack me AR ke DO group hain:
##   AssaultRifle_1..5   (pehla group)
##   AssaultRifle2_1..4  (doosra group — naam me "2" hai, number phir 1 se shuru)
## Isliye "ar_6" ka seedha matlab AssaultRifle2_1 hai. Neeche har prefix ke liye
## batate hain ki doosra group ka naam kya hai aur pehle group me kitni files hain
## (utna number ghata kar doosre group me dhundha jata hai).
## Pehla group hamesha pehle try hota hai — kal ko AssaultRifle_6 aa jaye to wahi milega.
const SECOND_GROUP := {
	"weapons": {
		"ar": {"prefix": "AssaultRifle2", "offset": 5},
	},
}

## khaas aliases (jo prefix rule me nahi aate)
const SPECIAL_ALIASES := {
	"nature": {
		"plant_flowers": ["Plant_Flowers"],
		"flowers": ["Plant_Flowers"],
		"flower": ["Flower_1"],
		"grass_small": ["Grass_Small"],
		"grass_large": ["Grass_Large"],
		"grass_large_2": ["Grass_Large_Extruded"],
		"grass_large_extruded": ["Grass_Large_Extruded"],
		"bush": ["Bush"],
		"bush_large": ["Bush_Large"],
		"bush_small": ["Bush_Small"],
	},
	"characters": {
		"female_alternative": ["Female_Alternative"],
		"smooth_female_alternative": ["Smooth_Female_Alternative"],
	},
}


# ---------------------------------------------------------- static storage ---

## category -> Array[String] (loadable model ke naam, asli case me)
static var _names: Dictionary = {}

## category -> { naam(lowercase) : "res://..." path }
static var _paths: Dictionary = {}

## category/name -> PackedScene (ya null). Static = poore project me ek hi baar load.
static var _cache: Dictionary = {}

## "dir|category" -> asli folder ka path. Case bhi match hota hai, kyunki upload me
## "Characters"/"Vehicles" capital me hain aur Linux/Android case-sensitive hote hain.
static var _dir_cache: Dictionary = {}

## ek hi warning baar-baar na aaye
static var _warned: Dictionary = {}

## Test/debug ke liye: isko set karo to sirf yahi folder dhundha jayega
## (scripts/selftest.gd isko use karke "sab file gayab" wala case check karta hai)
static var base_dir_override: String = ""


# ============================================================ PUBLIC API =====

## Ek category ke saare loadable model naam (extension ke bina, asli case me).
static func list_models(category: String = "nature") -> Array[String]:
	_scan(category)
	var out: Array[String] = []
	out.assign(_names.get(category, []))
	return out


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


## Pool me se ek variant uthao (variant index wrap ho jata hai).
## `names` ek Array hota hai jaise ["pine_1", "pine_2", ...] ya ["ar_1", ...].
static func load_variant(names: Array, variant: int = 0,
		category: String = "nature") -> PackedScene:
	if names.is_empty():
		return null
	var idx := absi(variant) % names.size()
	return load_model(str(names[idx]), category)


## Us naam ka poora res:// path (ya ""). Debug/HUD ke liye.
static func find_path(name_fragment: String, category: String = "nature") -> String:
	return _resolve(name_fragment, category)


## Kisi bhi category me kuch mila hai?
static func has_models(category: String = "nature") -> bool:
	return not list_models(category).is_empty()


## Kahin bhi kuch bhi mila hai?
static func has_any_models() -> bool:
	for category in CATEGORIES:
		if has_models(category):
			return true
	return false


## Cache khali karo (tests ke liye; normally zaroorat nahi)
static func clear_cache() -> void:
	_cache.clear()
	_names.clear()
	_paths.clear()
	_dir_cache.clear()
	_warned.clear()


## Kis category me kitni files mili — CI summary / debug HUD ke liye.
static func stats() -> Dictionary:
	var out := {}
	for category in CATEGORIES:
		out[category] = list_models(category).size()
	return out


## Insaani zubaan me report (GitHub Actions log + selftest isko print karte hain)
static func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("AssetLoader dirs: " + ", ".join(search_dirs()))
	for category in CATEGORIES:
		var names := list_models(category)
		lines.append("  %-11s %2d model%s" % [category, names.size(),
				"" if names.size() == 1 else "s"])
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

## Saare search dirs se ek category ki loadable files ki list banao (ek hi baar, cache).
static func _scan(category: String) -> void:
	if _names.has(category):
		return

	var names: Array[String] = []
	var paths := {}
	var seen := {}

	for dir_path in search_dirs():
		var folder := category_dir(dir_path, category)
		if folder.is_empty():
			continue                        # folder hi nahi hai -> skip (koi error nahi)
		var dir := DirAccess.open(folder)
		if dir == null:
			continue

		for file_name in dir.get_files():
			var clean := _strip_suffix(file_name)
			var ext := clean.get_extension().to_lower()
			if not EXTENSIONS.has("." + ext):
				continue
			var bare := clean.substr(0, clean.length() - ext.length() - 1)
			if bare.is_empty() or bare.begins_with("."):
				continue                    # .gdignore / .gitkeep / dot files

			var full := folder.rstrip("/") + "/" + file_name
			# Sirf wahi file lo jo Godot sach me load kar sake. Godot 4 .fbx load NAHI
			# karta (isliye build ke waqt .glb convert hota hai) — aise files yahan
			# chup-chaap skip ho jati hain, aur game procedural fallback pe chalta hai.
			if not ResourceLoader.exists(full):
				continue

			var key := bare.to_lower()
			if seen.has(key):
				continue                    # pehla folder jeeta (BASE_DIRS ka order)
			seen[key] = true
			names.append(bare)
			paths[key] = full

	names.sort()                            # deterministic (PCK ka order badal sakta hai)
	_names[category] = names
	_paths[category] = paths

	if names.is_empty():
		_warn_once("empty:" + category,
				"AssetLoader: %s me koi loadable model nahi mila -> procedural fallback chalega"
				% category)


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
			# doosra group (jaise ar_6 -> AssaultRifle2_1) — pack me AR do baar hai
			var second: Dictionary = SECOND_GROUP.get(category, {})
			if second.has(head):
				var info: Dictionary = second[head]
				var shifted := int(tail_num) - int(info.get("offset", 0))
				if shifted >= 1:
					out.append(str(info.get("prefix", "")) + "_" + str(shifted))
		elif prefixes.has(lower):
			out.append(str(prefixes[lower]))
	return out


## Fragment -> asli file ka poora path (ya ""). Koi filesystem call nahi — listing
## pehle hi ban chuki hai (aur usme sirf loadable files hain).
static func _resolve(name_fragment: String, category: String) -> String:
	var fragment := name_fragment.strip_edges().to_lower()
	if fragment.is_empty():
		return ""

	_scan(category)
	var paths: Dictionary = _paths.get(category, {})
	if paths.is_empty():
		return ""

	var candidates := _alias_candidates(name_fragment, category)

	# 1) exact match (case ignore) — sabse pehle, isliye "ar_5" hamesha AssaultRifle_5 hi dega
	for cand in candidates:
		var want := str(cand).to_lower()
		if paths.has(want):
			return String(paths[want])

	# 2) naam se shuru
	for cand in candidates:
		var want := str(cand).to_lower()
		for key in paths:
			if String(key).begins_with(want):
				return String(paths[key])

	# 3) naam me kahin bhi
	for cand in candidates:
		var want := str(cand).to_lower()
		for key in paths:
			if String(key).contains(want):
				return String(paths[key])

	# 4) aakhri sahara: number hata ke prefix dhoondo ("sniper_4" -> koi bhi sniper)
	var parts := fragment.split("_", false)
	if parts.size() >= 2:
		var word := parts[0]
		for key in paths:
			if String(key).contains(word):
				_warn_once("fuzzy:" + category + "/" + fragment,
						"AssetLoader: '%s' nahi mila -> '%s' use kar rahe hain"
						% [name_fragment, key])
				return String(paths[key])
	return ""


## Ek model load karne ki koshish. Fail hone pe null (koi error nahi).
static func _try_load(name_fragment: String, category: String) -> PackedScene:
	var path := _resolve(name_fragment, category)
	if path.is_empty():
		_warn_once("miss:" + category + "/" + name_fragment,
				"AssetLoader: model nahi mila -> %s/%s (procedural fallback chalega)"
				% [category, name_fragment])
		return null

	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	_warn_once("bad:" + path, "AssetLoader: %s PackedScene nahi hai -> skip" % path)
	return null


## Jab resource PackedScene na ho par Mesh ho (jaise Godot ne `.obj` khud import kar liya).
## Us case me ek MeshInstance3D wapas dete hain — assets.gd usko bhi waise hi taiyaar
## kar leta hai (skin, shadow, scale, muzzle). Kuch na mile to null.
static func load_mesh_node(name_fragment: String, category: String = "weapons") -> MeshInstance3D:
	var path := _resolve(name_fragment, category)
	if path.is_empty():
		return null
	var res: Resource = load(path)
	if not (res is Mesh):
		return null
	var node := MeshInstance3D.new()
	node.name = name_fragment
	node.mesh = res as Mesh
	_warn_once("mesh:" + path, "AssetLoader: %s Mesh ke roop me load hua (MeshInstance3D bana)" % path)
	return node


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
