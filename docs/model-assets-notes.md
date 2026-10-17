# `assets/downloaded/.gdignore` kya hai?

Wo ek **khali file** hai (file ka content matter nahi karta, naam hi kaafi hai).

Godot jis folder me `.gdignore` dekhta hai, us poore folder ko **scan karna band** kar deta hai.
Yahan isliye rakhi hai:

* `assets/downloaded/` me tumhare upload kiye Quaternius **.fbx** source models hain.
* Godot 4 **.fbx import nahi kar sakta**, aur is repo ka CI isi wajah se
  "8) Project import" step pe **atka** hua tha (40+ minute, koi error bhi nahi).
* Build ke waqt `tools/fbx2glb.py` in FBX ko `.glb` me convert karke
  `assets/models/<category>/` me daalta hai — **wahi folder Godot padhta hai**.

Isliye is `.gdignore` ko delete mat karo. (Delete ho jaye to game phir bhi chalta hai,
bas models ki jagah procedural shapes dikhengi — kuch toota nahi.)

---

# Naam se model kaise milta hai (alias system)

`scripts/asset_loader.gd` game ke andar ke chhote naam (jaise `ar_5`, `pine_2`,
`male_3`, `taxi`) ko `assets/models/` ki asli files se jodta hai:

| Kahan | Kya karta hai |
|---|---|
| `FILE_PREFIXES` | `ar_5` → `AssaultRifle_5`, `sniper_2` → `SniperRifle_2`, `pine_3` → `PineTree_3` |
| `SECOND_GROUP` | Jab pack me ek group do baar ho: `ar_6` → `AssaultRifle2_1` (weapons pack me AR ke 2 group hain: `AssaultRifle_1..5` aur `AssaultRifle2_1..4`) |
| `CHARACTER_FILES` | `male_3` → `Male_Shirt` (male/female ki 8-8 files, number wrap hota hai) |
| `VEHICLE_FILES` | `taxi` → `Taxi`, `cop_car` → `Cop`, `sedan` → `SportsCar` |
| `SPECIAL_ALIASES` | Nature ke khaas naam: `pine_5` → `PineTree_1` (sirf 4 pine hain), `grass_large_2` → `Grass_Large_Extruded` |

Dhoondhne ka order: **exact naam** → **naam se shuru** → **naam me kahin** →
(optional) number hata ke prefix. Kuch bhi na mile to `null` — aur game
procedural shape bana leta hai.

**Naya model add karte waqt:** file ka naam aisa rakho jo upar wale rules se match kare
(jaise naya SMG ho to `SubmachineGun_6.fbx` — `smg_6` seedha chal jayega). Naya group
ho to `SECOND_GROUP`/`SPECIAL_ALIASES` me ek line add kar do.

`scripts/selftest.gd` (CI step 8d) yahi sab check karta hai: har gun ka model, muzzle
node ka barrel ke aage hona, character ki height 1.8 m, pair zameen pe, aur "sab assets
gayab" wala fail-soft case. Fail hone pe poora output commit ke comment me aata hai.

---

# OBJ weapons ka pipeline (assets/downloaded_obj/)

Weapons ka source **OBJ + MTL** hai (`assets/downloaded_obj/Weapons/`, 40 guns = 80 files).
Baaki sab (nature/characters/vehicles) FBX me hai (`assets/downloaded/`).

1. Build ke waqt step **7d**:
   `python3 tools/obj2glb.py assets/downloaded_obj --out-root assets/models`
   → `assets/models/weapons/<Name>.glb`
2. Phir FBX step (**7d-b**) `--skip-existing` ke saath chalta hai, isliye weapons ke `.glb`
   OBJ se hi bante hain (FBX weapons sirf backup hain).
3. Godot sirf `assets/models/` import karta hai. Raw folders me **`.gdignore`** pada hai,
   isliye Godot unhe scan bhi nahi karta (FBX wale hang ki wajah yahi thi).
4. Raw `.obj`/`.mtl` build workspace se hata diye jate hain (repo me safe rehte hain).

## Muzzle direction (barrel kis taraf hai)

Is pack me **har gun ka barrel +X taraf** hai (stock -X pe). Ye 40 models ke side-view
renders se verify kiya gaya (Bullpup_1 aur SubmachineGun_3 jaise ajeeb shapes me bhi).
Isliye converter `rotY(90)` lagata hai, jisse:

* lambai ka axis X → **Z** ho jata hai
* barrel (+X) → **-Z** (game me yahi chahiye, muzzle node usi sirre pe lagta hai)

**Auto-flip jaan-boojh kar nahi hai:** "jis sirre pe zyada ubhaar (grip/stock) ho wo peeche"
wala guess is pack me 2 guns pe **ulta** baithta hai (Bullpup_1, SubmachineGun_3 —
dono ke renders me barrel phir bhi +X pe hai). Isliye converter/loader sirf **warning**
deti hai, khud se 180° nahi ghumati (`assets.gd` → `_normalize_orientation()`).

## Winding (inside-out check)

`tools/obj2glb.py` har model ke triangle ka geometric normal, OBJ ke apne `vn` normals se
milata hai. Agar 60% se zyada faces ulte nikle to winding flip kar deta hai (Godot back-face
cull karta hai, warna gun andar se dikhta). Run 40/40 models ka result: **sab theek**
(flip ki zaroorat kisi me nahi padi).

---

# Nature / Characters / Vehicles (OBJ pack) — modes aur rules

`tools/obj2glb.py` **folder ke naam se mode chunta hai** (`--mode auto`):

| Folder | Mode | Rotation | Size | Kyun |
|---|---|---|---|---|
| `Weapons/` | `weapon` | +X → −Z (rotY 90) | longest = 1.0 m | barrel −Z chahiye |
| `Nature/` | `prop` | koi nahi (Y-up) | **asli metres** | ped khade rehne chahiye; "longest → Z" rule unhe lita deta |
| `Characters/` | `character` | rotY 180 | asli metres | muh +Z pe hai (Eyes material se naapa) → −Z |
| `Vehicles/` | `vehicle` | rotY 180 | asli metres | headlights +Z pe hain → −Z |

**Base hamesha y = 0** (nature/characters/vehicles me) aur X/Z centre — isliye
`assets.gd` ka koi bhi builder model ko seedha zameen pe rakh sakta hai.

## Runtime scaling

| Cheez | Kaun scale karta hai | Kitna |
|---|---|---|
| Pine tree | `main.gd` `_scatter_nature()` | 0.9–1.4 × (model 2.3–6.9 m) |
| Rock | wahi | 0.7–1.4 × (model 0.7–2.2 m) |
| Grass / plant | wahi | 0.85–1.55 × (model 0.3–1.5 m) |
| Character | `assets.gd` `fit_to_height()` | hamesha 1.8 m |
| Vehicle | `assets.gd` `build_vehicle_model()` | hamesha 4.4 m lambai |

## Collision

* **Pine** → `CapsuleShape3D` radius **0.5 m** (spec), height = model ki height.
* **Rock** → `BoxShape3D` (AABB se, 0.85×).
* **Grass / plant** → **koi collision nahi** (decor).
* **Vehicle** → `BoxShape3D` (AABB ka 90–96%).

## MultiMesh (ghaas/plant)

`main.gd` me agar kisi kind ke **40 se zyada** instances hain (`multimesh_threshold`),
to har model-variant ka ek `MultiMeshInstance3D` ban jata hai (1 draw call per variant).
Condition: model me **ek hi mesh node** ho (hamara OBJ→GLB aisa hi hai). Warna
individual nodes lag jate hain — fail-soft.
