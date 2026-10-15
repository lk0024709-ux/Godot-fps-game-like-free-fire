extends RefCounted
##
## AssetLoader — build ke waqt download hue CC0 models ko runtime pe load karta hai.
##
## Ye file HYBRID asset system ka "loader" hissa hai:
##   - GitHub Actions `assets/downloaded/<category>/` me free CC0 models (.glb) daalta hai
##   - Ye script wahan se unhe load karta hai (PackedScene)
##   - Agar kuch bhi download na hua ho (net/github down, ya folder hi na ho) to
##     ye chup-chaap `null` deta hai -> assets.gd ka procedural fallback chalta hai
##
## Sab kuch SAFE hai: folder na ho, file kharab ho, PCK me list na aaye — koi error
## nahi aata, bas null milta hai. Isliye game KABHI asset download ki wajah se nahi rukta.
##
## Static cache hai, isliye ek hi model baar-baar disk se nahi padha jaata.
##
## Istemal (assets.gd me):
##     const Loader := preload("res://scripts/asset_loader.gd")
##     var scene := Loader.load_model("tree_default", "nature")   # PackedScene ya null
##

## Jahan CI download karta hai (dekho .github/workflows/build-apk.yml step "7c")
const BASE_DIR := "res://assets/downloaded/"

## Sirf ye formats chalte hain (GLB self-contained hota hai: usme hi mesh + material aate hain)
const EXTENSIONS: Array[String] = [".glb", ".gltf"]


## category/fragment -> PackedScene (ya null). Static = poore project me ek hi baar load.
static var _cache: Dictionary = {}

## category -> Array[String] (ek hi baar folder padha jaata hai)
static var _listings: Dictionary = {}


# ============================================================ PUBLIC API =====

## Ek category ke saare model naam (extension ke bina). Folder na ho to khali list.
static func list_models(category: String = "nature") -> Array[String]:
	if _listings.has(category):
		return _listings[category]

	var names: Array[String] = []
	var dir_path := BASE_DIR + category

	# Folder hi nahi hai (download fail hua / assets skip hue)? Koi error nahi, khali list.
	# dir_exists_absolute() res:// paths ke saath bhi kaam karta hai.
	if not DirAccess.dir_exists_absolute(dir_path):
		_listings[category] = names
		return names

	var dir := DirAccess.open(dir_path)
	if dir == null:
		_listings[category] = names
		return names

	for file_name in dir.get_files():
		var clean := _strip_suffix(file_name)
		var ext := "." + clean.get_extension().to_lower()
		if EXTENSIONS.has(ext):
			names.append(clean.trim_suffix(ext))

	names.sort()          # deterministic (warna PCK ki listing ka order badal sakta hai)
	_listings[category] = names
	return names


## Naam ke hisse se model dhundo -> PackedScene, warna null (kabhi crash nahi).
## Match ka order: exact naam -> naam se shuru -> naam me kahin bhi.
static func load_model(name_fragment: String, category: String = "nature") -> PackedScene:
	var key := category + "/" + name_fragment
	if _cache.has(key):
		return _cache[key]

	var scene := _try_load(name_fragment, category)
	_cache[key] = scene
	return scene


## Kisi bhi category me kuch download hua hai? (debug / README ke liye)
static func has_models(category: String = "nature") -> bool:
	return not list_models(category).is_empty()


## Saari categories me kuch bhi hai? (HUD/debug ke liye)
static func has_any_models() -> bool:
	return has_models("nature") or has_models("buildings") or has_models("weapons") \
		or has_models("characters")


## Cache khali karo (aksar zaroorat nahi — scene reload pe bhi cache chalta rehta hai)
static func clear_cache() -> void:
	_cache.clear()
	_listings.clear()


# ============================================================== INTERNAL ======

## Ek model load karne ki koshish. Fail hone pe null.
static func _try_load(name_fragment: String, category: String) -> PackedScene:
	var fragment := name_fragment.to_lower().strip_edges()
	if fragment.is_empty():
		return null

	# ---- 1) Folder listing se best match dhoondo ----
	var best := ""
	var files := list_models(category)
	for f in files:
		if f.to_lower() == fragment:
			best = f
			break
	if best.is_empty():
		for f in files:
			if f.to_lower().begins_with(fragment):
				best = f
				break
	if best.is_empty():
		for f in files:
			if f.to_lower().contains(fragment):
				best = f
				break

	# ---- 2) Listing khali ho (jaise PCK me list na aaye) to seedha path try karo ----
	#        (assets.gd ke paas fragment naam already hote hain, isliye ye hamesha chalega)
	if best.is_empty():
		for ext in EXTENSIONS:
			var direct := BASE_DIR + category + "/" + name_fragment + ext
			var loaded_direct := _load_scene(direct)
			if loaded_direct != null:
				return loaded_direct
		return null

	for ext in EXTENSIONS:
		var path := BASE_DIR + category + "/" + best + ext
		var loaded := _load_scene(path)
		if loaded != null:
			return loaded
	return null


## Path se PackedScene (agar exist karta hai aur PackedScene hai)
static func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	return null


## Exported PCK me kabhi kabhi ".remap"/".import" laga hua naam aata hai -> hata do
static func _strip_suffix(file_name: String) -> String:
	var clean := file_name
	if clean.ends_with(".remap"):
		clean = clean.trim_suffix(".remap")
	elif clean.ends_with(".import"):
		clean = clean.trim_suffix(".import")
	return clean
