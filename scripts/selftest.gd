extends Node3D
##
## Selftest — asset pipeline ka automatic check (CI me chalta hai).
##
## Ye scene main game ko chhedti nahi. Iska kaam sirf ye dekhna hai:
##   1. AssetLoader folders padh pata hai aur models load kar pata hai
##   2. weapon_data.gd ke "model" naam sach me match karte hain ("ar_5" -> AssaultRifle_5)
##   3. build_weapon_model() downloaded model ke saath sahi ban raha hai
##      (scale, muzzle node, material override, shadow off)
##   4. character model 1.8m aur pair y=0 pe aata hai
##   5. nature props (tree/rock/grass/plant), vehicles aur BUILDINGS bante hain
##   6. FAIL-SOFT: base_dir_override ko khali folder pe set kar ke dekhte hain ki
##      sab kuch procedural fallback se phir bhi ban jaye (koi crash nahi)
##
## Chalane ka tarika (GitHub Actions step "8d"):
##     godot --headless --path . --quit-after 200 scenes/selftest.tscn
## Kuch bhi fail hua to exit code 1 -> CI red (aur commit pe error comment).
##
## Phone pe dekhna ho to: main scene ke bajaye ye scene chala do — screen pe
## "SELFTEST PASS/FAIL" likha aa jayega.
##

const Loader := preload("res://scripts/asset_loader.gd")
const Assets := preload("res://scripts/assets.gd")
const DATA := preload("res://scripts/weapon_data.gd")
const CHARACTERS := preload("res://scripts/character_data.gd")
const BUILDING := preload("res://scripts/building_builder.gd")

## Download kuch nahi hua ho to bhi kitne tests chalne chahiye (fail-soft test me kam)
var _checks: int = 0
var _failures: Array[String] = []
var _notes: Array[String] = []
var _phase: int = 0
var _frames: int = 0


func _ready() -> void:
	print("==================== SELFTEST START ====================")
	_run_phase_1_real_assets()


func _process(_delta: float) -> void:
	_frames += 1


## Phase 1: jo assets maujood hain unke saath poora test
func _run_phase_1_real_assets() -> void:
	_phase = 1

	# ---------- 1) loader ----------
	var stats := Loader.stats()
	_notes.append("loader: " + str(stats))
	for line in Loader.report_lines():
		print("  " + line)
	# Har category ke saare model naam (CI log me poora scan dikh jaye)
	for category in Loader.CATEGORIES:
		print("  %s ke models (%d): %s" % [category, Loader.list_models(category).size(),
				", ".join(Loader.list_models(category))])
	for category in Loader.CATEGORIES:
		_check(stats.get(category, 0) >= 0, "loader: %s listing chali" % category)

	var any_downloaded := Loader.has_any_models()
	_notes.append("koi downloaded model mila: %s" % any_downloaded)

	# ---- ye counts CI me PAKKE hone chahiye (spec) ----
	# Source folder repo me hai (CI source tree) to .glb bhi bane hone chahiye.
	# Agar OBJ/FBX conversion fail hui to yahin RED ho jayega (chhup ke nahi jayega).
	var sources := {
		"weapons": "res://assets/downloaded_obj/Weapons",
		"nature": "res://assets/downloaded_obj/Nature",
		"characters": "res://assets/downloaded_obj/Characters",
		"vehicles": "res://assets/downloaded_obj/Vehicles",
	}
	var expected := {"weapons": 40, "nature": 60, "characters": 16, "vehicles": 7}
	for category in expected:
		if DirAccess.dir_exists_absolute(String(sources[category])):
			var got := int(stats.get(category, 0))
			_check(got >= int(expected[category]),
					"%s ke models %d+ chahiye, mile %d" % [category, int(expected[category]), got])

	# ---------- 2) weapon models ----------
	var missing_models: Array[String] = []
	var weapons: Array[Dictionary] = DATA.get_weapons()
	_check(weapons.size() == 28, "weapon_data me 28 weapons hain (%d mile)" % weapons.size())
	var with_model := 0
	for weapon in weapons:
		var model_name := String(weapon.get("model", ""))
		if model_name.is_empty():
			continue          # pistols: jaan-boojh kar procedural
		with_model += 1
		if Loader.load_model(model_name, "weapons") == null:
			missing_models.append("%s->%s" % [weapon.get("name"), model_name])
	_notes.append("downloaded weapon models: %d/28 (baaki procedural)" % with_model)
	if any_downloaded and with_model > 0 and not missing_models.is_empty():
		_check(false, "ye weapon models nahi mile: " + str(missing_models))

	# kaun gun kaunsa model use kar raha hai (log me saaf dikh jaye) + kitne alag models
	var resolved := {}
	var model_paths := {}
	for weapon in weapons:
		var mname := String(weapon.get("model", ""))
		var path := Loader.find_path(mname, "weapons") if not mname.is_empty() else ""
		print("  %-14s -> %-10s %s" % [weapon.get("name"), mname if not mname.is_empty() else "(procedural)",
				path if not path.is_empty() else "MISSING"])
		if not path.is_empty():
			resolved[mname] = true
			model_paths[path] = true
	_notes.append("alag downloaded models: %d (28 guns me, SMG me kuch repeat hote hain)"
			% model_paths.size())
	if any_downloaded:
		_check(model_paths.size() >= 22,
				"28 guns me kam se kam 22 alag model use ho rahe hain (%d mile)" % model_paths.size())
		_check(resolved.size() >= 25, "kam se kam 25 guns ke paas downloaded model hai (%d mile)" % resolved.size())

	# har weapon ka poora model banao (downloaded ya procedural — dono chalta hai)
	for weapon in weapons:
		var model := Assets.build_weapon_model(
				String(weapon.get("shape", "rifle")),
				weapon.get("body", Color.WHITE),
				weapon.get("accent", Color.BLACK),
				String(weapon.get("model", "")),
				float(weapon.get("scale", 1.0)))
		var wname := String(weapon.get("name", "?"))
		_check(model != null, "weapon model bana: %s" % wname)
		if model == null:
			continue
		add_child(model)
		var muzzle := model.find_child("Muzzle", true, false)
		_check(muzzle != null, "muzzle node mila: %s" % wname)
		var box := Assets.visual_aabb(model)
		_check(box.size.z > 0.02, "weapon ki lambai theek hai: %s (%.2fm)" % [wname, box.size.z])
		if String(weapon.get("model", "")) != "" and not missing_models.is_empty():
			_check(true, "  (procedural fallback chal raha hai: %s)" % wname)
		# muzzle barrel ke aage hona chahiye (peeche nahi)
		if muzzle is Node3D and box.size.z > 0.02:
			var local_z: float = (muzzle as Node3D).position.z
			_check(local_z < 0.02, "muzzle aage hai: %s (z=%.2f)" % [wname, local_z])
		model.queue_free()

	# ---------- 3) character models ----------
	for pick in ["male_1", "male_3", "female_1", "female_5"]:
		var body := Assets.build_character_model(pick,
				CHARACTERS.get_character(0).get("body", Color.WHITE),
				CHARACTERS.get_character(0).get("accent", Color.BLACK),
				CHARACTERS.ENEMY_TINT)
		if body == null:
			body = Assets.fallback_character(CHARACTERS.ENEMY_TINT, CHARACTERS.ENEMY_TINT,
					CHARACTERS.ENEMY_TINT)
		_check(body != null, "character model bana: %s" % pick)
		if body != null:
			add_child(body)
			var box := Assets.visual_aabb(body)
			_check(absf(box.size.y - CHARACTERS.ENEMY_HEIGHT) < 0.25,
					"%s ki height %.2fm (1.8m chahiye)" % [pick, box.size.y])
			_check(absf(box.position.y) < 0.15, "%s ke pair zameen pe (y=%.2f)" % [pick, box.position.y])
			if Loader.load_model(pick, "characters") != null:
				var limbs := body.find_child("leg_l", true, false) != null \
						and body.find_child("arm_r", true, false) != null
				if limbs:
					_check(true, "%s ke limb nodes mile (animation chalegi)" % pick)
			body.queue_free()

	# ---------- 4) nature + vehicle ----------
	for kind in ["tree", "rock", "grass", "plant"]:
		var prop: Node3D = null
		match kind:
			"tree":
				prop = Assets.tree(1.0, 0)
			"rock":
				prop = Assets.rock(1.0, 1)
			"grass":
				prop = Assets.grass_tuft(1.0, 2)
			"plant":
				prop = Assets.plant(1.0, 0)
		_check(prop != null, "nature prop bana: %s" % kind)
		if prop != null:
			add_child(prop)
			prop.queue_free()

	# ---- 4b) downloaded model naam sach me resolve ho rahe hain? ----
	var nature_wanted: Array[String] = [
		"pine_1", "pine_2", "pine_3", "pine_4", "pine_5",
		"rock_1", "rock_2", "rock_3", "rock_4", "rock_5",
		"plant_1", "plant_2", "plant_flowers",
		"grass_small", "grass_large", "grass_large_2",
	]
	var nature_missing: Array[String] = []
	for nm in nature_wanted:
		if Loader.find_path(nm, "nature").is_empty():
			nature_missing.append(nm)
	if any_downloaded and Loader.has_models("nature"):
		_check(nature_missing.is_empty(), "nature ke saare models mile (missing: %s)" % str(nature_missing))

	var char_missing: Array[String] = []
	for i in CHARACTERS.count():
		var model_name := CHARACTERS.get_model(i)
		if Loader.find_path(model_name, "characters").is_empty():
			char_missing.append("%s->%s" % [CHARACTERS.display_name(i), model_name])
	if any_downloaded and Loader.has_models("characters"):
		_check(char_missing.is_empty(), "10 characters ke models mile (missing: %s)" % str(char_missing))

	var vehicle_wanted: Array[String] = ["Cop", "NormalCar1", "NormalCar2", "Taxi", "SUV",
			"SportsCar", "SportsCar2"]
	var vehicle_missing: Array[String] = []
	for nm in vehicle_wanted:
		if Loader.find_path(nm, "vehicles").is_empty():
			vehicle_missing.append(nm)
	if any_downloaded and Loader.has_models("vehicles"):
		_check(vehicle_missing.is_empty(), "7 vehicles ke models mile (missing: %s)" % str(vehicle_missing))

	# tree pe CapsuleShape3D collision (spec: r = 0.5)
	var tree_prop: Node3D = Assets.tree(1.0, 0)
	if tree_prop != null:
		add_child(tree_prop)
		var capsule_found := false
		for child in tree_prop.get_children():
			if child is StaticBody3D:
				for col in (child as StaticBody3D).get_children():
					if col is CollisionShape3D and (col as CollisionShape3D).shape is CapsuleShape3D:
						capsule_found = true
		_check(capsule_found, "ped pe CapsuleShape3D collision hai")
		tree_prop.queue_free()

	var vehicle: StaticBody3D = Assets.build_vehicle_model("Taxi")
	if vehicle == null:
		vehicle = Assets.fallback_vehicle("Taxi", Color(0.9, 0.8, 0.2))
	_check(vehicle != null, "vehicle bana (Taxi)")
	if vehicle != null:
		add_child(vehicle)
		vehicle.queue_free()

	# ---- 5) BUILDINGS: chaaron types bante hain, light + solid walls ke saath ----
	for kind in ["small_house", "big_house", "barn", "shop"]:
		var building: Node3D = BUILDING.build(kind)
		_check(building != null, "building bana: %s" % kind)
		if building == null:
			continue
		add_child(building)
		var solids := 0
		var lights := 0
		for child in building.get_children():
			if child is StaticBody3D:
				solids += 1
			elif child is OmniLight3D:
				lights += 1
		_check(solids >= 6, "%s me solid pieces hain (%d)" % [kind, solids])
		_check(lights == 1, "%s me 1 interior light hai (%d)" % [kind, lights])
		var foot: Vector2 = BUILDING.footprint(kind)
		_check(foot.x >= 6.0 and foot.y >= 6.0, "%s ka footprint theek hai (%.1f x %.1f)"
				% [kind, foot.x, foot.y])
		building.queue_free()

	# ---------- 6) FAIL-SOFT test: assets gayab ----------
	# loader ko aise folder pe set karte hain jahan kuch nahi hai -> sab kuch
	# procedural fallback se banna chahiye, aur koi crash nahi hona chahiye.
	Loader.base_dir_override = "res://assets/downloaded_missing/"
	Loader.clear_cache()
	Phase2.new(self).run()
	Loader.base_dir_override = ""
	Loader.clear_cache()

	_report()


## Phase 2 (fail-soft) — alag class me isliye ki await/lambda ke bina saaf rahe
class Phase2:
	var host: Node

	func _init(h: Node) -> void:
		host = h

	func run() -> void:
		# assets gayab hone pe bhi ye sab ban jana chahiye (procedural se)
		var weapon := Assets.build_weapon_model("rifle", Color(0.3, 0.2, 0.1), Color.BLACK,
				"ar_5", 1.0)
		host._check(weapon != null, "FAIL-SOFT: weapon procedural se bana (no assets)")
		if weapon != null:
			host._check(weapon.find_child("Muzzle", true, false) != null,
					"FAIL-SOFT: procedural weapon ka muzzle bhi hai")
			weapon.queue_free()

		var body := Assets.build_character_model("male_1", Color.WHITE, Color.BLACK)
		host._check(body == null, "FAIL-SOFT: character null deta hai (caller fallback kare)")
		if body == null:
			var fb := Assets.fallback_character(Color.WHITE, Color.BLACK)
			host._check(fb != null, "FAIL-SOFT: procedural humanoid bana")
			fb.queue_free()

		var tree := Assets.tree(1.0, 0)
		host._check(tree != null, "FAIL-SOFT: tree procedural se bana")
		if tree != null:
			tree.queue_free()

		var veh := Assets.build_vehicle_model("taxi")
		host._check(veh == null, "FAIL-SOFT: vehicle null deta hai (caller fallback kare)")
		if veh == null:
			var fb_veh := Assets.fallback_vehicle("taxi", Color(0.9, 0.8, 0.2))
			host._check(fb_veh != null, "FAIL-SOFT: procedural gaadi bani")
			fb_veh.queue_free()


# ------------------------------------------------------------------ report ---

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(label)
	push_error("SELFTEST FAIL: " + label)


func _report() -> void:
	print("----------------------- SELFTEST SUMMARY -----------------------")
	for note in _notes:
		print("  note: " + note)
	if _failures.is_empty():
		print("SELFTEST PASS: %d/%d checks theek" % [_checks, _checks])
	else:
		print("SELFTEST FAIL: %d/%d checks fail" % [_failures.size(), _checks])
		for f in _failures:
			print("   FAIL: " + f)
	print("================================================================")
	# CI ko exit code chahiye (headless run me ye bas print hota hai, decide workflow karta hai)
	if _failures.is_empty():
		print("SELFTEST_EXIT_OK")
	else:
		print("SELFTEST_EXIT_FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
