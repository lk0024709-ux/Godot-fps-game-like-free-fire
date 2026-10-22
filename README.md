# Indus : Battle Royale — Godot 4.2 (PC + Android)

Ek chhota par **pura 3D First-Person Shooter**, jo PC (WASD + mouse) aur Android
(touch joystick + swipe) dono pe chalta hai.

Guns, characters, ped-patthar aur gaadiyan ab **asli 3D models** (CC0 / public domain)
se aate hain — wo bhi bina kuch manually convert kiye: GitHub Actions build ke waqt
unhe `.glb` me badalta hai. Koi model na mile (ya folder hi na ho) to game
**procedural fallback** (code se bane box/cone shapes) pe chalta rehta hai —
build ya game kabhi is wajah se nahi rukta.

APK **GitHub Actions** se automatic ban jata hai, PC pe Godot install karne ki zaroorat nahi.

## Game launch flow (UI)

```
splash.tscn  ->  loading.tscn  ->  home.tscn  ->  main.tscn
(logo+PRESENTS)  (progress bar)   (BATTLE)      (asli game)
```

| Screen | File | Kya hota hai |
|---|---|---|
| **Splash** | `scenes/splash.tscn` + `scripts/splash.gd` | Kaala background, logo (`res://icon.svg`, 300x300) + "PRESENTS". 1s fade-in -> 1.5s hold -> 1s fade-out. Tap/key se skip. |
| **Loading** | `scenes/loading.tscn` + `scripts/loading.gd` | Dark grey background, "LOADING..." + green progress bar (screen ki 60% width). `main.tscn` background thread me load hota hai. 100% pe 0.5s ruk kar home. |
| **Home** | `scenes/home.tscn` + `scripts/home.gd` | Cinematic lobby: `assets/ui/home_bg.png` full-screen (cover), top-left logo, top-right coins/gems/settings/notifications, left me **MISSIONS / INVENTORY / WEAPONS** (dark blue + cyan), bottom-left **SOLO / SQUAD**, bottom-right bada gold **START BATTLE** -> game. |
| **Game** | `scenes/main.tscn` | Pehle jaisa hi — arena, weapons, HUD, enemies. |

Sab UI **code se** bana hai (Control/ColorRect/TextureRect/Label/Button/ProgressBar +
containers). Koi external font/theme nahi — sirf do images load hoti hain:
`assets/ui/home_bg.png` (home ka background) aur logo. Home ka logo pehle
`assets/ui/home_logo.png` dhoondhta hai; file na mile to `icon.svg` + "INDUS" text
lockup dikh jata hai. Background ya logo missing ho to procedural fallback — crash nahi.

> **Apna art badalna hai?** `assets/ui/home_bg.png` (16:9) ko apni image se replace karo.
> Logo ke liye `assets/ui/home_logo.png` (~250x100, transparent PNG) daal do — bas.

> `res://icon.svg` hi launcher icon bhi hai (`export_presets.cfg` ->
> `launcher_icons/main_192x192`). Naya logo chahiye? Bas wahi file replace kar do —
> splash, home aur APK icon teeno apne aap badal jayenge.

---

## 1. APK kaise banega (step by step)

1. Ye repo GitHub pe push karo (ya merge karo).
2. Repo me **Actions** tab kholo.
3. `Build Android APK` workflow apne aap chalu ho jayega (har push pe chalta hai).
   Manually chalane ke liye: **Actions → Build Android APK → Run workflow**.
   Workflow sab kuch khud karta hai — Godot 4.2.2 download, export templates install,
   keystore, APK export, upload. Kisi third-party action pe depend nahi karta.
4. ~2-4 minute wait (pehli baar thoda zyada, cache lagne ke baad ~1.5 minute).
   Green tick aa gaya to APK ready hai.
5. APK lene ke 2 tarike:
   - **Releases page** (sabse aasan, phone ke browser me bhi khulta hai):
     `Releases → Latest APK → FreeFireFPS.apk` — seedha download.
     Link: `https://github.com/<tumhara-username>/<repo>/releases/download/latest-apk/FreeFireFPS.apk`
   - **Actions run page** → neeche `Artifacts` → `FreeFireFPS-apk` (zip me hoga).
6. Phone me install karo. Android "unknown app install" ki permission maangega → **Allow**.

> Note: build ke waqt ek **test keystore** ban jaata hai (kyunki Google Play ke bina
> signing key nahi hoti). Iska matlab: agar tumne pehle wala APK install kiya hua hai,
> to naya APK install karne se pehle **purana uninstall** karna padega
> ("App not installed" error ki wajah yahi hoti hai).
>
> Pakka (stable) signing key chahiye? Repo → Settings → Secrets → Actions me 3 secrets daal do:
> `ANDROID_KEYSTORE_BASE64` (base64 me `base64 -w0 my.keystore`), `ANDROID_KEYSTORE_ALIAS`,
> `ANDROID_KEYSTORE_PASSWORD`. Workflow khud hi unhe use kar lega.

---

## 2. Controls

| Kaam | PC | Android |
|---|---|---|
| Chalna | `W A S D` (ya arrow keys) | **Left half** me kahin bhi ungli rakho (joystick wahin ban jata hai) |
| Dekhna | Mouse | Screen ke **right half pe swipe** |
| Firing | Left click / Enter (hold = auto fire) | **FIRE** button (bottom-right) |
| Gun badalna | `Q` pichhla / `E` agla / `mouse wheel`, `1-9` seedha gun | **SWAP** button (agla gun) |
| Poori gun list (28) | `G` | **GUNS** button |
| Reload | `R` (khali hone pe khud bhi hota hai) | **RELOAD** button |
| Jump | `Space` | **JUMP** button |
| **Sprint** | `Shift` dabaye rakho (6 → 10 m/s, FOV 75 → 85) | **SPRINT** button (joystick ke paas) — dabaye rakho |
| **Plane se kudna (match start)** | `Space` ya **JUMP OUT** button (10s me auto-eject) | **JUMP OUT** button (10s me auto-eject) |
| **Hawa me steering** | `W A S D` | **joystick** |
| Mouse free/capture | `Esc` / click | — |
| Restart (marne ke baad) | `TAP TO RESTART` button | `TAP TO RESTART` button |

---

## 3. Gameplay rules (jo maanga gaya tha)

- **BATTLE ROYALE DROP: match 300m upar plane me shuru** — plane procedural boxes
  se bana (body/wings/engines/tail — sab low-poly, shadow off) aur 70 m/s se map ke
  paar udta hai. **JUMP OUT** button (PC: `Space`) ya **10 second** ka countdown
  (auto-eject). Plane me shooting/movement band, sirf look-around chalta hai
- **Free-fall**: gravity se girta hai (max 55 m/s), WASD/joystick se hawa me
  steering. **50m pe parachute khud khulta hai** (8-side cone, low-poly) — fall
  speed **5 m/s** + steering. Land pe chhatri hati, gun wapas, "Landed!" toast
- **Dushman land karne ke baad hi spawn hote hain** (drop ke dauran koi fight nahi)
- First-person camera, **FOV 75** (sprint me 85), player ki head height pe
- **Sprint: `Shift` / SPRINT button — 6 → 10 m/s**, camera FOV smooth 75 → 85,
  weapon me halka bob. Rukte hi sab wapas normal
- Player **100 HP** se shuru, enemy touch = **-10 HP**
- Enemy marne pe **+10 score**
- Goli **2 second** me gayab, enemy 2 goli me marta hai, takrayi to damage deti hai
- Enemies random (8 fixed puntos me se, player se door) spawn hote hain aur chal ke paas aate hain
- HP 0 → **GAME OVER** screen + restart button
- Zameen **2000×2000m** (grid shader), cover boxes/pillars, boundary walls, DirectionalLight with shadows
  (**drop ke dauran shadows off** — 4GB phone pe smooth FPS, land pe wapas on)
- Touch UI sirf touch-device pe dikhta hai, PC pe nahi
- **Renderer: mobile** (Android performance ke liye), sab low-poly (koi texture nahi)

---

## 3b. Weapon system (28 guns, Free Fire style)

| Category | Kitne | Guns |
|---|---|---|
| Pistols (semi) | 3 | Desert Eagle, USP, M500 |
| SMG (auto) | 8 | MP40, MP5, UMP, P90, Thompson, Bizon, Skorpion, Vector |
| Rifles (auto, M7 semi) | 11 | AK, M4A1, SCAR, Groza, FAMAS, M7, XM8, AUG, Parafal, AN94, Kingfisher |
| Snipers (semi) | 3 | AWM, Kar98k, M82B |
| Shotguns | 3 | M1014 (6 pellets), MAG-7 (8 pellets), SPAS12 (6 pellets) |

- Har gun ka apna **damage / fire rate / magazine / spread / recoil / bullet speed** hai
  (sab `scripts/weapon_data.gd` me ek-ek line me likha hai — wahi tumhara tuning table hai).
- **Gun ka 3D model**: 25 guns ka apna asli (CC0) model hai — `scripts/weapon_data.gd` ki
  har line me `"model"` field hai (jaise `"model": "ar_5"` = `AssaultRifle_5.glb`), aur usi ke
  saath `"body"`/`"accent"` colour lagta hai. 3 pistols ke models pack me nahi the, isliye wo
  code se bante hain (procedural). Model kisi wajah se na mile to automatic procedural shape
  use hota hai — gun kabhi ghayab nahi hoti.
- Koi texture nahi — sirf `StandardMaterial3D` ka `albedo_color` (body = surface 0, baaki = accent).
- Reload **1.2 s**, magazine khali hone pe **khud** reload hota hai.
- `GUNS` button (ya PC pe `G`) se poori list khulti hai — har button pe us gun ka skin
  colour dikhta hai, tap karo aur gun equip.
- Ammo poora bhara milta hai (reserve ammo system nahi hai) — simple rakhne ke liye.
- Enemy ka HP **200** hai taaki chhoti gun aur sniper me farq saaf mehsoos ho.
  Value badalni ho to `scripts/enemy.gd` me sirf `max_health = 200.0` ka number badal do.

### Enemy ko marne me kitni goli lagti hai (200 HP pe)

| Gun ka type | Example | Per goli damage | Kitni goli |
|---|---|---|---|
| Sniper (sabse strong) | M82B | 120 | **2** |
| Sniper | AWM | 95 | **3** |
| Sniper / Pistol | Kar98k / M500 | 88 / 90 | **3** |
| Rifle | AK / Groza | 60 / 61 | **4** |
| Rifle | M4A1 / SCAR | 48 / 53 | **4-5** |
| Pistol | Desert Eagle | 55 | **4** |
| Pistol | USP | 30 | **7** |
| SMG | MP40 / Vector | 24 / 28 | **8-9** |
| SMG (sabse halki) | Skorpion | 20 | **10** |
| Shotgun | SPAS12 (6 pellets x 14) | 84 (sab lage to) | **3 blast** |
| Shotgun | MAG-7 (8 pellets x 18) | 144 (sab lage to) | **2 blast** |

> Note: shotgun ke pellets bikharte hain — door se chalane pe sab nahi lagte, isliye
> asli goliyaan isse zyada lagengi. Yahi balance ka maza hai.

---

## 4. Files (kya kya hai aur kis kaam ka)

```
project.godot                  # Project settings: naam, 1280x720, mobile renderer, input keys (WASD/jump/fire), landscape orientation
export_presets.cfg             # Android export preset (naam "Android", arm64-v8a, APK, signed) — isi ko Actions use karta hai
icon.svg                       # Launcher icon (hand-made SVG, koi download nahi)
assets/ui/home_bg.png          # Home screen ka cinematic background (1672x941, 16:9)
assets/ui/home_logo.png        # (optional) home ka logo — na ho to icon.svg + text lockup

scenes/splash.tscn             # Launch scene #1: logo + PRESENTS (1s in / 1.5s hold / 1s out)
scenes/loading.tscn            # Launch scene #2: progress bar + threaded main.tscn load
scenes/home.tscn               # Launch scene #3: home menu (BATTLE / GUNS / SETTINGS / coins)
scenes/main.tscn               # Game scene: sky + sun + player + HUD + timer (baaki duniya code me banti hai)
scenes/player.tscn             # Player body + head + camera (FOV 75) + gun model
scenes/enemy.tscn              # Enemy (capsule + head + visor) + wall-check ray
scenes/bullet.tscn             # Goli ka chhota glowing sphere
scenes/hud.tscn                # Crosshair, HP bar, score, GAME OVER panel, joystick + FIRE/JUMP/RELOAD/SWAP/GUNS/SPRINT + gun-picker panel + JUMP OUT drop UI

scripts/splash.gd              # Splash ka UI + fade tween + loading.tscn pe transition
scripts/loading.gd             # Threaded load (load_threaded_request/status) + progress bar + home.tscn
scripts/home.gd                # Home lobby UI: bg image, logo, left menu, mode select, START BATTLE -> main.tscn
scripts/main.gd                # Game manager: arena + buildings + nature + gaadiyaan banata hai, enemies/score/game over
scripts/weapon_data.gd         # 28 weapons ke stats + skin colours + kaunsa CC0 model (sirf data — yahan numbers badlo)
scripts/weapon_manager.gd      # Gun switching, ammo, reload, model lagana (signals HUD ko bhejta hai)
scripts/assets.gd              # Saare models: pehle downloaded CC0 model, warna code se bana procedural shape
scripts/character_data.gd      # 10 characters (Rey/Zen/Vihaan/... ) -> kaunsa male/female model + rang
scripts/player.gd              # Movement (WASD/joystick), look (mouse/swipe), jump, SPRINT (Shift/10 m/s/FOV), firing, health/damage, body model, PLANE DROP states (plane/freefall/parachute/land)
scripts/enemy.gd               # Dushman: 200 HP, player ko follow karta hai, touch = -10 HP, flash + death, humanoid model
scripts/asset_loader.gd        # Downloaded models load karta hai, char/vehicle/nature aliases ke saath (fail-safe: na mile to null -> procedural)
scripts/building_builder.gd    # Enterable buildings (ghar/barn/dukaan): deewar ke tukde + darwaza + light + furniture
scripts/selftest.gd            # Automatic asset test (CI step 8d): loader/muzzle/height/buildings/fail-soft
scripts/drop_selftest.gd       # Automatic BR drop test (CI step 8h): plane -> jump out -> parachute -> land -> sprint
scenes/drop_selftest.tscn      # Drop selftest scene (headless CI + phone pe bhi chal sakta hai)
scripts/bullet.gd              # Goli: Area3D (body_entered) + ray-check (no tunnelling), 2.5s lifetime, enemy ko damage
scripts/hud.gd                 # HUD values, buttons ke signals, damage flash, game over screen
scripts/joystick.gd            # Left-half virtual joystick (jahan ungli rakho wahi center; khud draw karta hai)
scenes/selftest.tscn           # Selftest scene (assets check karta hai, phone pe bhi chala sakte ho)

assets/downloaded/             # FBX source (nature/characters/vehicles) — .gdignore pada hai, Godot inhe scan nahi karta
assets/downloaded_obj/        # OBJ + MTL source: Weapons 40, Nature 66, Characters 16, Vehicles 7
                               #   .gdignore pada hai (Godot scan nahi karta; CI .glb banata hai)
assets/models/                 # CI ne banaye .glb (Godot sirf yahin se model uthata hai) — commit NAHI hote
tools/obj2glb.py               # OBJ+MTL -> GLB converter (weapons/nature/characters/vehicles, pure python)
tools/fbx2glb.py               # FBX 7.x -> GLB converter (pure python, koi pip/numpy nahi)
tools/glbcheck.py              # .glb files ki jaanch (header/accessor/normals) — CI step 7e
tools/gdcheckrefs.py           # Har Helper.func() call aur parameter count ki cross-check — CI step 8b
docs/model-assets-notes.md     # Ye sab kaise kaam karta hai (aur .gdignore kyun hai)
docs/obj-weapons-report.md     # OBJ weapons pack ka report (mapping + verify checklist)
docs/obj-all-assets-report.md  # Nature + characters + vehicles + buildings ka report
docs/renders/                  # 40 guns ke side-view renders (barrel kis taraf — isi se verify hua)

.github/workflows/build-apk.yml # GitHub Actions: FBX->GLB convert + Godot 4.2.2 + keystore + selftest + APK export + upload
```

---

## 5. Kya-kya tweak karna hai kahan

| Kya chahiye | Kahan badlo |
|---|---|
| Game ka naam / icon / launch scene | `project.godot` → `application/config/name`, `config/icon`, `run/main_scene` |
| Splash ki speed | `scripts/splash.gd` → `FADE_IN`, `HOLD`, `FADE_OUT` |
| Loading screen kitni der | `scripts/loading.gd` → `MIN_SHOW`, `DONE_DELAY` |
| Home ka background | `assets/ui/home_bg.png` replace karo (16:9 PNG) — code change nahi chahiye |
| Home ka logo | `assets/ui/home_logo.png` daalo (~250x100); na ho to `icon.svg` fallback |
| Home ke buttons / rang | `scripts/home.gd` → `GOLD`, `PANEL_BG`, `CHIP_BG`, `_panel_style()` |
| Player speed / jump | `scripts/player.gd` → `move_speed`, `jump_velocity` |
| Sprint speed / FOV | `scripts/player.gd` → `sprint_speed` (10.0), `sprint_fov` (85.0) |
| Plane drop (height / speed / countdown) | `scripts/main.gd` → `plane_start`, `plane_speed`, `auto_eject_time`, `plane_drop_enabled` (off = seedha ground match) |
| Parachute (kab khule / kitni dheere gire) | `scripts/player.gd` → `parachute_height` (50), `parachute_fall_speed` (5.0), `parachute_steer_speed` |
| Firing speed / damage | `scripts/player.gd` → `fire_cooldown`, `bullet_damage` |
| Mouse / touch sensitivity | `scripts/player.gd` → `mouse_sensitivity`, `touch_sensitivity` |
| Enemy speed / HP / damage | `scenes/enemy.tscn` khologe to inspector me dikhega, ya `scripts/enemy.gd` ke `@export` defaults |
| Kitne enemies + spawn speed | `scenes/main.tscn` → `Main` node ke inspector me (`max_enemies`, `spawn_interval`) |
| Maidan ka size / cover boxes | `scripts/main.gd` → `arena_size` aur `_obstacles` list |
| Buildings (kitni/kahan) | `scripts/main.gd` → `BUILDING_PLAN` (zone ke hisaab se list) |
| Building ka size / darwaza / furniture | `scripts/building_builder.gd` → `SIZES`, `DOOR_SIZE`, `_add_furniture()` |
| Ped / patthar / jhaadi / ghaas ki ginti | `scripts/main.gd` → `tree_count`, `rock_count`, `bush_count`, `grass_count` |
| Nature ka layout (kahan kya uge) | `scripts/main.gd` → `nature_seed` (same seed = same map) |
| Kisi bhi gun ka damage / ammo / speed | `scripts/weapon_data.gd` → us gun ki line (ek hi line me sab hai) |
| Gun ka rang (skin) | `scripts/weapon_data.gd` → wahi line, `GOLD`/`BLACK` jaise colour naam |
| Naye colour add karne ho | `scripts/weapon_data.gd` ke top pe `const MY_COLOR := Color(...)` |
| Reload time | `scripts/weapon_manager.gd` → `reload_time` (default 1.2) |
| Gun ka size screen pe | `scenes/player.tscn` → `Head/Camera3D/WeaponHolder` ki position, aur `weapon_manager.gd` ka `model_scale` (0.7) |
| Gun (3D model) ki asli lambai | `scripts/assets.gd` → `WEAPON_TARGET_LENGTH` (pistol 0.30, smg 0.60, rifle 1.20, sniper 1.40, shotgun 1.10 m) |
| Kisi ek gun ko bada/chhota karna | `scripts/weapon_data.gd` → us gun ki line me `"scale": 1.3` (Bizon/Skorpion isi tarah set hue hain) |
| Character ki height | `scripts/assets.gd` → `CHARACTER_HEIGHT` (1.8 m) aur `scripts/character_data.gd` → `ENEMY_HEIGHT` |
| Enemy ka rang (dark red) | `scripts/character_data.gd` → `ENEMY_TINT` (default `Color(0.55, 0.12, 0.12)`) |
| Player ke body ka model / rang | `scripts/character_data.gd` → `get_characters()` ki list (Rey→male_1, Zen→male_2, ...) |
| Gaadi ki lambai | `scripts/assets.gd` → `VEHICLE_LENGTH` (4.4 m) |
| Gaadi kis zone me kaunsi | `scripts/main.gd` → `_spawn_vehicles()` ka zone table (Chowk taxi+sedan, Haveli cop_car, ...) |
| Nature ki max hadd | `scripts/main.gd` → `max_trees` (80) / `max_rocks` (50) — hadd pe pahunchne pe warning aati hai |
| Enemy ka HP | `scripts/enemy.gd` → `max_health` (abhi **200** — pistol ~7, sniper 2-3 goli) |
| Player ki HP | `scripts/player.gd` → `max_health` (abhi 100) — HP bar apne aap isi ke hisaab se set hoti hai |
| Score per kill | `scripts/main.gd` → `_on_enemy_died()` me `score += 10` |
| HUD ka rang / button size | `scenes/hud.tscn` ke stylebox + offsets |

Tip: har script ke `@export` variables Godot editor me Inspector me dikhte hain — code chhue bina values badal sakte ho.

---

## 5b. Model assets (CC0 Quaternius + procedural fallback)

Game me models **3 layer** se aate hain — upar wala mile to wahi, warna neeche wala:

1. **Repo me pade CC0 source files** — `assets/downloaded/<category>/` (Quaternius ke
   `.fbx`). Is folder me `.gdignore` pada hai, isliye **Godot inhe scan nahi karta**
   (Godot 4 me FBX importer hai hi nahi, aur bade packs pe uska import scan hang ho jata hai).
2. **CI ka conversion + import** — build ke waqt:
   - step **7d**: `tools/obj2glb.py` OBJ+MTL (weapons) ko `.glb` me badalta hai,
     aur `assets/models/weapons/` me daalta hai. Ye pack me har gun ka barrel **+X**
     taraf hota hai → converter usko **-Z** pe ghumata hai (game ko wahi chahiye),
     aur winding bhi check karta hai (model andar se bahar na dikhe).
   - step **7d-b**: `tools/fbx2glb.py` baaki FBX (nature/characters/vehicles) ka kaam
     karta hai (`--skip-existing`, isliye weapons ke `.glb` OBJ se hi bante hain).
   - **Godot sirf** `assets/models/` **se** models padhta hai. Ye `.glb` commit NAHI hote —
     har build pe bante hain (aur cache hote hain, isliye build tezz rehta hai).
   - step **7e** har `.glb` ko check karta hai (`glbcheck.py`), step **8d** game ka apna
     selftest chalata hai (loader + har gun ka model/muzzle + fail-soft test).
3. **Procedural fallback** — kuch bhi na mile (file delete, conversion fail, folder
   hi gayab), to `scripts/assets.gd` wahi model **code se** bana deta hai (box/cone/
   cylinder). Build **pass** hota hai, game chalta hai — bas shape simple ho jata hai.

| Category | Kya use hota hai | Kitni files | License | Source |
|---|---|---|---|---|
| `weapons` | **40 models**: AssaultRifle 1-5 + AssaultRifle2 1-4, Bullpup 1-3, SubmachineGun 1-5, SniperRifle 1-6, Shotgun 1-4 + SawedOff + ShortStock, Pistol 1-6, Revolver 1-5 | 40 (OBJ+MTL) | **CC0 1.0** | Quaternius (low-poly weapon pack) — source: `assets/downloaded_obj/Weapons/`, license: `assets/downloaded_obj/LICENSE.txt` |
| `characters` | Male/Female Casual, Shirt, Suit, LongSleeve, Dress, TankTop, Alternative, + Smooth wale | 16 | **CC0 1.0** | Quaternius (`assets/downloaded/Characters/License.txt`) |
| `vehicles` | Taxi, Cop, SUV, SportsCar, SportsCar2 | 5 | **CC0 1.0** | Quaternius (`assets/downloaded/Vehicles/License.txt`) |
| `nature` | PineTree 1-4, Rock 1-5, Plant 1-2, Plant_Flowers, Grass Small/Large/Extruded | 15 | **CC0 1.0** | Quaternius Ultimate Platformer pack (`License_nature.txt`) |
| `nature` (backup) | Kenney Nature Kit 2.1 — 14 `.glb` (step **7c** download karta hai, fail-soft) | 14 | **CC0 1.0** | https://kenney.nl/assets/nature-kit |

- CC0 ka matlab: commercial use, modify, redistribute — sab allowed, credit zaroori nahi.
  Phir bhi credit diya gaya hai (upar table) — achhi practice hai.
- Total converted size ~**7.9 MB** (33.5 MB FBX → 7.5 MB GLB) — APK par iska asar chhota hai.
- **Kaun model kahan lagta hai?** (sab `scripts/` me data ki tarah likha hai — code chhedne
  ki zaroorat nahi):
  - Guns → `scripts/weapon_data.gd` ke `"model"` field (jaise `"AK": {"model": "ar_5"}`).
    Naam ka matlab `assets/models/weapons/` ki file hai: `ar_5` = `AssaultRifle_5`.
    Pistols bhi models use karte hain: `pistol_1` = `Pistol_1.glb`, `revolver_1` = `Revolver_1.glb`.
  - Player/enemy → `scripts/character_data.gd` (10 characters me se har ek ko `male_1`
    jaise naam mila hai; `male_1..8` / `female_1..8` ka matlab `asset_loader.gd` ki
    `CHARACTER_FILES` list se hota hai).
  - Ped/patthar/ghaas → `scripts/main.gd` ke zone rules + `scripts/assets.gd` ke
    `tree()/rock()/grass_tuft()/plant()`.
  - Gaadi → `scripts/assets.gd` ke `VEHICLE_FILES` alias (`taxi`, `cop_car`, `suv`, ...).
- **Naya model add karna ho** (OBJ/FBX/GLB — sab chalta hai, par ek baar convert karna padta hai):
  1. File upload karo: weapons ke liye `assets/downloaded_obj/Weapons/` (`.obj` + uska `.mtl`
     dono), baaki categories ke liye `assets/downloaded/<category>/` (`weapons`, `nature`,
     `Characters`, `Vehicles`).
  2. Naam se usko game me bulana hai: `ar_10` jaisa naam prefix se match hona chahiye. Naye
     group ka naam ho (jaise `AssaultRifle2_*`) to `scripts/asset_loader.gd` ke `SECOND_GROUP`
     ya `SPECIAL_ALIASES` me ek line add karo.
  3. Push karo — CI khud convert karega. Log me step **7d** me `X/X converted` dikhega.

> Purana note (history): pehle nature models Kenney repos se build ke waqt download hote the,
> kyunki `Malcolmnixon/Quaternius-Nature` jaisa repo exist hi nahi karta tha aur `Shapespark`
> pack me `.glb` ki jagah Godot `.tscn` files (Git-LFS pe) thi. Ab Quaternius ke FBX repo me
> pade hain, isliye download ki zaroorat nahi — Kenney sirf backup ke liye reh gaya hai.

## 5c. Generator repo se automatic asset sync

Har APK build me **Sync Assets from Generator Repo** step
[`indus-assets-gen`](https://github.com/lk0024709-ux/indus-assets-gen) ki `main`
branch ko temporary runner folder me shallow-clone karta hai. Manual download/upload
ki zaroorat nahi:

| Generator source | Godot destination |
|---|---|
| `docs/models/` (poora folder, subfolders aur glTF sidecars ke saath) | `res://assets/models/` |
| `docs/textures/` (agar present ho) | `res://assets/textures/` |

`assets/models/` hi `scripts/asset_loader.gd` ka canonical runtime search path hai.
Sync **cache restore aur OBJ/FBX conversion ke baad**, lekin **GLB validation,
Godot project import, selftests aur APK export se pehle** hota hai. Isliye purana
cache generator ki latest files ko overwrite nahi karega. Existing Quaternius
models bhi apni jagah rehte hain; generated files har build pe fresh copy hote hain
(inko game repo me commit karna zaroori nahi).

Clone fail ho, `docs/models/` missing/empty ho, ya destination me `.gdignore` ho,
to build clear error ke saath fail hota hai. `.gitignore` Git tracking ke liye hai,
Godot import ko block nahi karta; destination folders me **`.gdignore` mat daalna**.
Build log aur Actions summary me exact generator commit aur copied model/texture
counts milenge. Generator update lene ke liye game ka APK workflow dobara run karo;
generator repo pe push akela is game workflow ko trigger nahi karta.

## 6. Kuch galat ho to (troubleshooting)

| Problem | Kya karo |
|---|---|
| Actions me **export** step fail | Log me `keystore` ya `Android SDK` word dhundo. Is repo me keystore step pehle se hai, so iska matlab usually SDK/build-tools ka issue hai — log paste karo, fix mil jayega |
| Actions me **import** step me JS/JSON error | `.tscn` file me syntax issue — log ki line paste karo |
| Phone pe "App not installed" | Purana app uninstall karo (test keystore badal jata hai), ya Settings me "unknown sources" allow karo |
| Gun badalne/equip karne ke liye mobile pe | **SWAP** (agla gun) ya **GUNS** (poori list) — PC pe `Q`/`E`/`G`/`1-9` |
| Gun-picker khulta hai par tap kaam nahi karta | Ab ye multi-touch safe hai (grid khud raw touch leta hai). Purane build me ye problem thi — naya APK install karo |
| Ped/patthar simple box jaise dikh rahe hain | Downloaded model nahi mila (procedural fallback chal raha hai). Actions log me step **7d** me `convert ho gaye: 80 glb` aur step **8d** me `SELFTEST PASS: 171/171` dhundo — dono theek hone chahiye |
| Gun ka model nahi dikh raha / gun gol gol hai | Us gun ka `"model"` naam `assets/models/weapons/` ki file se match nahi kar raha. Log me `AssetLoader: model nahi mila -> weapons/<naam>` milega. `scripts/asset_loader.gd` ke `FILE_PREFIXES` / `SECOND_GROUP` / `SPECIAL_ALIASES` me alias add kar do |
| Naya model upload kiya par game me purana hi dikh raha | Step **7b** ka cache purana `.glb` de raha hai — cache key `assets/downloaded/**/*.fbx` ke hash pe hai, isliye naya file aane pe apne aap naya cache ban jata hai. Phir bhi purana dikhe to Actions me “Re-run all jobs” karo |
| Selftest (8d) fail hua | Failed commit ke neeche **comment** me poora selftest output aata hai (kaunsa check toota, kitne me se kitne). Wo output bhej do, fix ho jayega |
| Game khulta hai par touch kaam nahi karta | Confirm karo ki build **Android** ke liye hua (PC/other platform ke liye nahi) aur `hud.tscn` me `TouchControls` node hai |
| Game crash / black screen | Android me `adb logcat` chalao ya phone pe crash dialog ka text bhej do |
| PC pe test karna hai | PC pe **Godot 4.2.2** install karo (free, ~100 MB) → `project.godot` import karo → `F5` dabao |
| Naya code copy-paste kiya, game crash ho raha hai | Actions khud check karta hai: step **8b) GDScript syntax check** aur **8c) Import log error scan** — syntax error hui to build wahi ruk jayega aur error ka line number commit comment me milega |
| Build fail hua par log nahi dikh raha | Fail hue commit ke neeche ek **comment** post hota hai (workflow ka aakhri step) — usme poora build log hai. Ya Actions run page pe failed step kholo |
| Performance kam hai | `project.godot` me `renderer/rendering_method="gl_compatibility"` kar do, aur `scripts/main.gd` me `max_enemies` 8 → 4 |

---

## 7. Aage kya add kar sakte ho

- Sound: `AudioStreamPlayer` + procedurally generated beeps (`AudioStreamGenerator`) ya free `.wav` add karke
- Reload + ammo system, headshot bonus, enemy health bar
- Naye guns (model + ek line `weapon_data.gd` me) — dekho section **5b**
- Models upgrade karna (naye `.fbx`/`.obj` `assets/downloaded/` me daalo, CI khud convert karega)
- Waves / levels, high score save (`user://` me JSON)
- Enemy ko dodge karna sikhana, ya sniper enemy

---

## Credit / License

- **Game ka code** is repo me likha gaya hai (MIT style — jo chaho karo).
- **Godot Engine** ka apna license (MIT) hai.
- **3D models**: [Quaternius](https://quaternius.com) ke low-poly packs
  (weapons / characters / vehicles / nature) — **CC0 1.0 (public domain)**.
  License text har folder me pada hai: `assets/downloaded/*/License*.txt`.
- **Kenney Nature Kit 2.1** (backup nature models, build ke waqt optional download) —
  [kenney.nl](https://kenney.nl/assets/nature-kit), **CC0 1.0**.
- CC0 me credit ki zaroorat nahi, phir bhi dono creators ko credit diya gaya hai — achhi practice.
- Converted `.glb` files repo me commit nahi hote (CI har build pe banata hai).
