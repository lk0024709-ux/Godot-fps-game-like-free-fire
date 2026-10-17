# CC0 models ka integration — poora report

**Ek line:** Tumhare upload kiye 66 CC0 (Quaternius) FBX models ab game me lag chuke hain —
guns (25/28), characters (player + enemy), ped/patthar/ghaas/plant aur 5-6 gaadiyan — aur
CI (GitHub Actions) har push pe khud unhe `.glb` me convert karke check karta hai; koi model
na mile to game chup-chaap procedural fallback pe chalta rehta hai, kabhi crash nahi hota.

- Branch: `arena/c519475b-godot-fps-game-like-free-fire`
- Aakhri commit: `0773c62` (README + docs), usse pehle `8eb91d2` (weapon alias fix), `7b44f9d` (CI fix)
- CI run (green, 22/22 steps, 2m 8s): `38908628886`
- APK: **https://github.com/lk0024709-ux/Godot-fps-game-like-free-fire/releases/download/latest-apk/FreeFireFPS.apk** (~23.6 MB)
- Asset selftest: **PASS — 171/171 checks**
- Loader ko jo mila: `weapons 30 · nature 28 · characters 16 · vehicles 5` models

---

## 1. MODIFIED files (sirf badle hue hisse)

### `scripts/weapon_data.gd` — har gun ko model mila

Purana: sirf 5 shape (pistol/smg/rifle/sniper/shotgun) + rang.
Naya: har gun ki line me `"model"` (aur SMG me `"scale"`).

```gdscript
// >>> BADLA: WEAPON_MODELS table add hua (roughly line 48 se 84 tak)
const WEAPON_MODELS := {
	# ---- rifles (11 weapons -> 11 models) ----
	"AK": {"model": "ar_5"},              # wood stock wala
	"M4A1": {"model": "ar_4"},            # black, alag look
	"SCAR": {"model": "ar_6"},            # ar_6 = AssaultRifle2_1 (pack me do AR group hain)
	"Groza": {"model": "bullpup_1"},
	"FAMAS": {"model": "bullpup_2"},
	"AUG": {"model": "bullpup_3"},
	"M7": {"model": "ar_7"},              # = AssaultRifle2_2
	"XM8": {"model": "ar_8"},             # = AssaultRifle2_3
	"Parafal": {"model": "ar_3"},
	"AN94": {"model": "ar_2"},
	"Kingfisher": {"model": "ar_1"},
	# ---- SMGs (8 weapons -> 5 models, 3 repeat) ----
	"MP40": {"model": "smg_1", "scale": 1.0},
	"MP5": {"model": "smg_2", "scale": 0.9},
	"UMP": {"model": "smg_3", "scale": 1.1},
	"P90": {"model": "smg_4", "scale": 1.0},
	"Thompson": {"model": "smg_5", "scale": 1.2},
	"Bizon": {"model": "smg_1", "scale": 1.3},      # repeat
	"Skorpion": {"model": "smg_3", "scale": 0.7},   # repeat
	"Vector": {"model": "smg_4", "scale": 0.9},     # repeat
	# ---- snipers (3 -> 3) ---- / ---- shotguns (3 -> 3) ----
	"Kar98k": {"model": "sniper_1"}, "AWM": {"model": "sniper_2"}, "M82B": {"model": "sniper_3"},
	"M1014": {"model": "shotgun_1"}, "MAG-7": {"model": "shotgun_2"}, "SPAS12": {"model": "shotgun_3"},
	# ---- pistols: models upload me nahi hain -> procedural ----
	"Desert Eagle": {"model": ""}, "USP": {"model": ""}, "M500": {"model": ""},
}
```

`get_weapons()` ab har gun me `"model"` aur `"scale"` bhejta hai (line ~180) — baaki
damage/fire-rate/ammo me kuch nahi chheda, isliye HUD/gun-switching/reload pehle jaisa hi hai.

### `scripts/assets.gd` — 3D models banane ka dil

```gdscript
// >>> BADLA: build_weapon_model() ab downloaded model try karta hai (line 63)
static func build_weapon_model(shape: String, body_color: Color, accent_color: Color,
		model_name: String = "", scale_hint: float = 1.0, muzzle_hint: float = -1.0) -> Node3D:
	if not model_name.is_empty():
		var scene := Loader.load_model(model_name, "weapons")
		if scene != null:
			var inst := scene.instantiate()
			if inst is Node3D:
				var prepared := _prepare_weapon_model(inst as Node3D, shape, body_color,
						accent_color, scale_hint, muzzle_hint)
				if prepared != null:
					return prepared
	match shape:            # yahan se neeche: purana procedural fallback (jaisa tha)
		"pistol": return _pistol(body_color, accent_color)
		"smg":    return _smg(body_color, accent_color)
		...
```

```gdscript
// >>> NAYA: character model (player + enemy), line 235
static func build_character_model(model_name: String, body_color: Color, accent_color: Color,
		tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var scene := Loader.load_model(model_name, "characters")
	if scene == null:
		return null                       # caller fallback karega
	var inst := scene.instantiate()
	...
	_apply_character_skin(model, body_color, accent_color, tint)   # surface 0 = body, baaki = accent
	var root := Node3D.new()
	root.name = "CharacterModel"
	root.add_child(model)
	fit_to_height(model, CHARACTER_HEIGHT)     # 1.8 m + pair y=0 + X/Z center
	return root
```

```gdscript
// >>> NAYA: nature prop ka downloaded version (line 804) — tree/rock/bush/plant/grass_tuft
// isko call karte hain, na mile to wahi purana procedural shape return hota hai
static func _try_downloaded(kind: String, variant: int, scale_f: float, node_name: String,
		with_collision: bool, yaw_deg: float = 0.0, with_shadow: bool = true) -> Node3D:
	var names: Array = NATURE_MODELS.get(kind, [])
	var fragment: String = str(names[absi(variant) % names.size()])
	var scene := Loader.load_model(fragment, "nature")
	if scene == null:
		return null                       # download nahi hua -> procedural fallback
	...
	model.position = Vector3(          # base theek y=0 pe, X/Z center
		-(box.position.x + box.size.x * 0.5) * scale_f,
		-box.position.y * scale_f,
		-(box.position.z + box.size.z * 0.5) * scale_f)
	if with_collision:
		_ensure_collision(root, kind)      # tree = capsule trunk, rock = BoxShape3D (AABB se)
	return root
```

Isi file me ye sab bhi naya/juda hua: `build_vehicle_model()` (line 292, model + collision,
null deta hai to caller procedural gaadi banata hai), `fallback_character()` (line 340),
`tint_grey()` (zone ka rang), `disable_collision()`, `_apply_weapon_skin()` (surface 0 =
body, baaki = accent), `_strip_shadows()` (gun par shadow nahi), `_add_muzzle_node()`
(barrel ke aage "Muzzle" node, hidden), `fit_to_height()`, `visual_aabb()`,
`_ensure_collision()`, `fallback_vehicle()`.

### `scripts/weapon_manager.gd` — gun lagane ki jagah (line 167)

```gdscript
// >>> BADLA: pehle sirf shape+colour jaata tha, ab model naam + scale bhi
	_model = ASSETS.build_weapon_model(
			String(weapon.get("shape", "rifle")),
			weapon.get("body", Color.WHITE),
			weapon.get("accent", Color.BLACK),
			String(weapon.get("model", "")),          # <-- naya
			float(weapon.get("scale", 1.0)))          # <-- naya
	if _model == null:
		return
	_model.scale = Vector3.ONE * model_scale
	holder.add_child(_model)
	muzzle = _model.find_child("Muzzle", true, false)   # muzzle flash pehle jaisa hi chalta hai
```

**Weapon switching / reload / HUD ka code chheda nahi gaya** — sirf model banane wali line badli.

### `scripts/player.gd` — visible body + naam ka tag

```gdscript
// >>> NAYA: _build_body() (line 98) — character_data se model + rang, sar chhupa hua
func _build_body() -> void:
	if not show_body:
		return
	var data: Dictionary = CHARACTERS.get_character(character_index)
	var model := ASSETS.build_character_model(
			String(data.get("model", "male_1")),
			data.get("body", Color(0.25, 0.45, 0.70)),
			data.get("accent", Color(0.14, 0.16, 0.22)))
	if model == null:
		return          # asset nahi mila -> body invisible (pehle jaisa game)
	model.name = "Body"
	add_child(model)
	var head_node := model.find_child("head", true, false)
	if head_node is Node3D:
		(head_node as Node3D).visible = false      # camera sar ke andar hai
	if name_tag:
		_add_name_tag(model, CHARACTERS.get_name(character_index))
```

### `scripts/enemy.gd` + `scenes/enemy.tscn` — box wala dushman khatam

`enemy.tscn` se purane `Body` (capsule mesh), `Head` (sphere) aur `Visor` (box) hata diye —
ab sirf `CollisionShape3D` (capsule) aur `WallCheck` ray bacha hai.

```gdscript
// >>> NAYA: _build_body() (line 75) — random male/female model + dark red tint
func _build_body() -> void:
	var pick: String = CHARACTERS.ENEMY_POOL[randi() % CHARACTERS.ENEMY_POOL.size()]
	var model := ASSETS.build_character_model(pick,
			Color(0.60, 0.20, 0.18), Color(0.30, 0.12, 0.12),
			CHARACTERS.ENEMY_TINT)                       # spec: (0.55, 0.12, 0.12)
	if model == null:
		model = ASSETS.fallback_character(...)           # dushman kabhi invisible nahi
	model.name = "Body"
	add_child(model)
	ASSETS.fit_to_height(model, CHARACTERS.ENEMY_HEIGHT) # 1.8 m, pair y=0
	_leg_l = model.find_child("leg_l", true, false) as Node3D
	_leg_r = model.find_child("leg_r", true, false) as Node3D
	_arm_l = model.find_child("arm_l", true, false) as Node3D
	_arm_r = model.find_child("arm_r", true, false) as Node3D
```

```gdscript
// >>> NAYA: chalte waqt haath-pair ka sine swing (line 207)
func _animate_limbs(delta: float) -> void:
	if _body == null:
		return
	var speed := animation_speed if _moving else 1.6
	_walk_phase += delta * speed
	var leg_swing := sin(_walk_phase) * (0.55 if _moving else 0.05)
	var arm_swing := -leg_swing * 0.7
	if _leg_l != null: _leg_l.rotation.x = leg_swing
	if _leg_r != null: _leg_r.rotation.x = -leg_swing
	if _arm_l != null: _arm_l.rotation.x = arm_swing
	if _arm_r != null: _arm_r.rotation.x = -arm_swing
```

### `scripts/main.gd` — zone-wise nature + gaadiyan

```gdscript
// >>> NAYA: 8 zones ki table (line 76) — weight 0 = us zone me wo cheez kabhi nahi
const ZONES := {
	"Chowk":     {"angle": -45.0, "spread": 44.0, "w_tree": 0.5, "w_rock": 1.2, "w_grass": 0.2, "w_plant": 0.2, "vehicles": ["taxi", "sedan"]},
	"Haveli":    {"angle":   0.0, "spread": 44.0, "w_tree": 0.6, "w_rock": 0.3, "w_grass": 0.9, "w_plant": 0.4, "vehicles": ["cop_car"]},
	"Himvana":   {"angle":  45.0, "spread": 44.0, "w_tree": 1.4, "w_rock": 0.0, "w_grass": 0.0, "w_plant": 0.0, "vehicles": []},   # sirf pine
	"Kanak":     {"angle":  90.0, ... "vehicles": ["suv"]},
	"Samudra":   {"angle": 135.0, ... "vehicles": ["sports"]},          # patthar + beach
	"Marusthal": {"angle": 180.0, "w_tree": 0.0, "w_rock": 1.6, "w_grass": 0.0, "w_plant": 0.0, "vehicles": ["sedan_2"]},  # sirf rock
	"Khet":      {"angle": -135.0, "w_tree": 0.5, "w_rock": 0.2, "w_grass": 1.0, "w_plant": 0.8, "vehicles": []},
	"Haritvan":  {"angle": -90.0, "w_tree": 1.8, "w_rock": 0.4, "w_grass": 1.6, "w_plant": 1.6, "vehicles": []},  # sabse ghana
}
```

```gdscript
// >>> NAYA: performance caps (line 39-41) — spec: 80 trees, 50 rocks
@export var max_trees: int = 80
@export var max_rocks: int = 50
@export var multimesh_threshold: int = 40      # (abhi MultiMesh use nahi hota — future work)

// >>> NAYA: cap lagne pe console me saaf warning (line 272)
if cap > 0 and wanted > cap:
	push_warning("Nature: %s ka cap lag gaya (%d -> %d) — max_%ss badhao to aur lagenge" % [...])
	wanted = cap
```

```gdscript
// >>> NAYA: gaadiyan zones ke fixed spots pe (line 391) — abhi static decoration
func _spawn_vehicles() -> void:
	...
	for zone_name in ZONES:
		for model_name in zone.get("vehicles", []):
			var body := _make_vehicle(str(model_name))     # model -> warna procedural
			body.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)   # y = 0
			body.rotation.y = angle + rng.randf_range(-0.5, 0.5)
			if not vehicle_collision:
				Assets.disable_collision(body)
			container.add_child(body)
```

### `.github/workflows/build-apk.yml` — build me sab kuch automatic

```yaml
// >>> NAYA (step 7b-7e, 8b, 8d):
7b) Cache: converted models        # key: cc0-glb-${{ hashFiles('assets/downloaded/**/*.fbx') }}
7c) Download CC0 nature assets     # Kenney backup (fail-soft, 45s deadline)
7d) FBX -> GLB conversion          # python3 tools/fbx2glb.py assets/downloaded --out-root assets/models
                                   # phir build workspace se .fbx delete (repo me safe rehte hain)
7e) GLB sanity check               # 80/80 glb theek | 152,596 triangles | 0 errors
8)  Project import (headless)      # ~25s (pehle 40+ minute atak jata tha)
8b) GDScript syntax check          # + tools/gdcheckrefs.py --params (cross-file ref + arity + unused params)
8d) Asset selftest                 # scripts/selftest.gd — 171 checks, fail hone pe commit comment me output
```

### `.gitignore`, `README.md`, `docs/`

- `.gitignore`: `assets/downloaded/**/*.glb|.gltf|.fbx.import` (converted files repo me nahi jaate),
  `qa-renders/`, `__pycache__/`, `build/glb-report.json`.
- `README.md`: naya section **5b. Model assets (CC0 Quaternius + procedural fallback)**,
  tuning table me model/scale/height wale knobs, troubleshooting me model-related rows,
  Credit section me Quaternius + Kenney.
- `docs/model-assets-notes.md`: `.gdignore` kyun zaroori hai + naam/alias ka poora rule table.

---

## 2. NEW files

| File | Kaam |
|---|---|
| `scripts/asset_loader.gd` | Sab models load karne ki ek jagah (Phase 1). Naam ka alias + cache + fail-soft `null`. |
| `scripts/character_data.gd` | 10 characters (Rey…Raze) → male_1..5 / female_1..5 + rang; `ENEMY_TINT`. |
| `scripts/selftest.gd` + `scenes/selftest.tscn` | CI ka asset test (171 checks) + fail-soft test. |
| `tools/fbx2glb.py` | FBX 7.x → GLB converter (pure python, koi pip nahi). `--out-root` se category folders bhi. |
| `tools/glbcheck.py` | `.glb` validator (header/chunks/accessors/index/normals) — exit 1 on bad file. |
| `tools/gdcheckrefs.py` | `<Helper>.<func>()` call ka existence + argument count + unused-parameter check. |
| `assets/downloaded/.gdignore` | Godot is folder ko scan hi nahi karta (isi wajah se FBX import hang fix hua). |
| `docs/model-assets-notes.md` | Wahi sab likha hua: `.gdignore`, alias rules, naya model kaise add karo. |

**`scripts/asset_loader.gd` ka dil (naya file, poora code yahin hai):**

```gdscript
extends RefCounted
## Sab models yahin se load hote hain. Kuch na mile to null -> game procedural shape banata hai.

const BASE_DIRS: Array[String] = ["res://assets/models/", "res://assets/downloaded/"]
const EXTENSIONS: Array[String] = [".glb", ".gltf", ".fbx"]
const CATEGORIES: Array[String] = ["weapons", "nature", "characters", "vehicles"]

## Naam se model dhundo -> PackedScene, warna null (kabhi crash nahi). Static cache ke saath.
static func load_model(name_fragment: String, category: String = "nature") -> PackedScene:
	if name_fragment.strip_edges().is_empty():
		return null
	var key := category + "/" + name_fragment
	if _cache.has(key):
		return _cache[key]
	var scene := _try_load(name_fragment, category)
	_cache[key] = scene
	return scene

## 5 weapons ke liye: "ar_6" -> AssaultRifle2_1 (pack me AR do group me hai)
const SECOND_GROUP := {
	"weapons": {
		"ar": {"prefix": "AssaultRifle2", "offset": 5},
	},
}
```

Baki public API: `load_variant()`, `find_path()`, `list_models()`, `has_models()`,
`has_any_models()`, `clear_cache()`, `stats()`, `report_lines()`, `search_dirs()`,
`category_dir()`, aur test ke liye `base_dir_override`.

**`scripts/character_data.gd` ka data:**

```gdscript
const ENEMY_POOL: Array[String] = [
	"male_1", "male_2", "male_3", "male_4", "male_5",
	"female_1", "female_2", "female_3", "female_4", "female_5",
]
const ENEMY_TINT := Color(0.55, 0.12, 0.12)   ## spec ka dark red
const ENEMY_HEIGHT := 1.8
const PLAYER_BODY_LAYER := 2                  ## camera is layer ko nahi dekhta

static func get_characters() -> Array[Dictionary]:
	return [
		_char("Rey", "male_1", Color(0.20, 0.45, 0.75), Color(0.12, 0.16, 0.24)),
		_char("Zen", "male_2", ...), _char("Vihaan", "female_1", ...),
		_char("Ace", "male_3", ...), _char("Rudra", "male_4", ...),
		_char("Ghost", "male_5", ...), _char("Krish", "female_2", ...),
		_char("Blaze", "female_3", ...), _char("Ayaan", "female_4", ...),
		_char("Raze", "female_5", ...),
	]
```

**`scripts/selftest.gd` kya check karta hai (CI step 8d):**

1. loader ki listing (weapons/nature/characters/vehicles) chalti hai
2. 28 weapons me se jis gun ka `"model"` hai, wo sach me milta hai
3. har gun ka model banta hai + `Muzzle` node milta hai + muzzle **barrel ke aage (-Z)** hai + lambai > 2 cm
4. character model 1.8 m, pair y=0, aur `leg_l`/`arm_r` nodes milte hain (animation ke liye)
5. nature props (tree/rock/grass/plant) aur vehicle bante hain
6. **fail-soft test**: loader ko khali folder pe set karke dekhte hain ki sab kuch
   procedural se banta hai aur koi crash nahi hota

Fail hone pe workflow step 8d poora output **commit ke comment** me post karta hai —
isi se pichhle din pakda gaya tha ki `SCAR/M7/XM8` ke model nahi mil rahe the.

---

## 3. VERIFY (phone pe kya dekhna hai)

1. APK install karo (naya install — purana hai to pehle uninstall, kyunki test keystore badalta hai).
2. Game khulte hi **pehli gun (AK)** haath me — us pe asli 3D model dikhna chahiye
   (ab sirf box nahi), aur **goli chalane pe muzzle flash** barrel ke sirre pe.
3. `GUNS` button se list kholo aur 4-5 gun badal ke dekho: **har gun ka alag model** +
   alag rang (SMG me Bizon bada, Skorpion chhota dikhega).
4. Reload (RELOAD button) karo — animation/flash pehle jaisa hi chalta rahe (kuch toota nahi hai).
5. **Dushman** (aatma/enemy) ab box nahi — asli humanoid, **gehra laal** rang, chalte waqt
   **haath-pair hilte** hain, sar pe naam ka tag.
6. Nature: **Himvana** taraf sirf **ped**, **Marusthal** taraf sirf **patthar**, **Haritvan**
   me ghana jungle + ghaas/plant. Ghaas me se guzar jaoge (collision nahi), ped/patthar se takrayenge.
7. **Gaadiyan**: Chowk me taxi + sedan, Haveli me cop car, Samudra me sports car, Kanak me SUV,
   Marusthal me sedan — ek jagah khadi, takkar hoti hai (andar baithna abhi nahi aata).
8. Score, HP, gun-picker, joystick, camera toggle — **sab pehle jaisa** kaam kare.

---

## 4. TUNING (kya badal ke kya dekho)

| Kya chahiye | Kahan badlo (ek line) |
|---|---|
| Gun model ki lambai (global) | `scripts/assets.gd` → `WEAPON_TARGET_LENGTH` = `{"pistol": 0.30, "smg": 0.60, "rifle": 1.20, "sniper": 1.40, "shotgun": 1.10}` |
| Ek gun bada/chhota | `scripts/weapon_data.gd` → us gun ki line me `"scale": 1.3` (jaise Bizon/Skorpion) |
| Gun haath me kahan baithe | `scripts/weapon_manager.gd` → `model_scale`; `scenes/player.tscn` → `Head/Camera3D/WeaponHolder` ki position |
| Character ki height | `scripts/assets.gd` → `CHARACTER_HEIGHT` (1.8) aur `scripts/character_data.gd` → `ENEMY_HEIGHT` |
| Enemy ka rang | `scripts/character_data.gd` → `ENEMY_TINT` (`Color(0.55, 0.12, 0.12)`) |
| Enemy kitni tez haath hilaye | `scripts/enemy.gd` → `animation_speed` aur `_animate_limbs()` ka `0.55` |
| Ped/patthar/ghaas/plant ki ginti | `scripts/main.gd` → `tree_count` (26), `rock_count` (18), `grass_count` (40), `plant_count` (20) |
| Kitne ped max | `scripts/main.gd` → `max_trees` (80) / `max_rocks` (50) — cap lage to console me warning aati hai |
| Nature ka layout (kahan kya) | `scripts/main.gd` → `ZONES` ki `w_tree/w_rock/w_grass/w_plant` (0 = kabhi nahi) |
| Gaadi kitni + kahan | `scripts/main.gd` → `vehicle_count` (6) aur `ZONES[...]["vehicles"]` |
| Gaadi ki lambai | `scripts/assets.gd` → `VEHICLE_LENGTH` (4.4 m) |
| Nature ka seed (pura layout) | `scripts/main.gd` → `nature_seed` (same seed = same map) |

---

## 5. IF IT FAILS (3 sabse zyada chance wali galtiyan + fix)

**1. Gun gol-gol (procedural) ya ped box jaisa dikh raha hai — model load hi nahi hua.**
- Log me dhundo: `AssetLoader: model nahi mila -> weapons/<naam>` (Actions run ke step 7d/8d me).
- Matlab: `weapon_data.gd` ka `"model"` naam `assets/models/weapons/` ki file se match nahi kar raha.
- Fix: `scripts/asset_loader.gd` ke `FILE_PREFIXES` (jaise `ar` → `AssaultRifle`) ya
  `SECOND_GROUP`/`SPECIAL_ALIASES` me us naam ke liye ek line add karo. Jaldi wala upay:
  `weapon_data.gd` me us gun ka `"model"` kisi maujood model pe set kar do (jaise `"ar_1"`).

**2. CI step 8d (Asset selftest) red ho gaya.**
- Ghabrao mat — **failed commit ke neeche comment** me poora selftest output aata hai
  (kaunsa check toota, `X/171 checks fail`)। Wo comment copy karke bhej do.
- Us output se seedha pata chal jata hai: model missing hai, height galat hai, ya muzzle peeche hai.
- Fix ke bina bhi game chalta rehta hai (procedural fallback) — APK banna bas ruk jata hai,
  taaki kharab APK tumhare phone tak na pahunche.

**3. Phone pe game install hi nahi hua / "App not installed".**
- Purana APK uninstall karo (test keystore har build me naya hota hai), phir naya install karo.
- Settings → "install unknown apps" allow karo (browser ke liye).
- Agar APK download hi nahi hua: `Releases → Latest APK` se seedha `FreeFireFPS.apk` download karo
  (Actions run page ka artifact zip phone pe kholna mushkil hota hai).

---

## 6. Pichhle din ke do bug (dono fix ho gaye)

1. **CI 40+ minute atak jata tha** — `assets/downloaded/` ke FBX pe Godot ka import scan.
   Fix: us folder me `.gdignore` + FBX ko build ke waqt `assets/models/` me `.glb` bana ke daalna
   (repo se delete nahi karte). Ab step 8 sirf **~25 second** leta hai.
2. **Selftest chup-chaap fail ho raha tha, output kahin nahi dikhta tha** — GitHub Actions
   ke `run:` steps me bash `-e` chalta hai, isliye `OUT=$(godot ...)` (jab Godot exit code 1
   deta hai) wahin script ko rok deta tha → na log, na comment. Fix: `set +e` + exit code
   capture + output ko commit comment aur run page summary me bhejna. Usi ke baad asli
   bug dikha: **`SCAR`/`M7`/`XM8` ke model nahi mil rahe the** (pack me AR ke do group hain:
   `AssaultRifle_1..5` aur `AssaultRifle2_1..4`) — `SECOND_GROUP` alias se fix hua, aur
   ab selftest **171/171** pass karta hai.
