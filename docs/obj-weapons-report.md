# OBJ weapons pack — integration report

**Ek line me:** 40 OBJ weapons (`assets/downloaded_obj/Weapons/`) build ke waqt GLB me convert hote hain, aur game ke **saare 28 guns** inhi models pe chal rahe hain (pistols/revolver bhi) — CI green, APK ban gaya, aur kuch bhi fail ho to purana procedural model chalta rehta hai.

## 1) Folder scan — jo `.obj` files mili (40)

* AssaultRifle2_1.obj · AssaultRifle2_2.obj · AssaultRifle2_3.obj · AssaultRifle2_4.obj
* AssaultRifle_1.obj · AssaultRifle_2.obj · AssaultRifle_3.obj · AssaultRifle_4.obj
* AssaultRifle_5.obj · Bullpup_1.obj · Bullpup_2.obj · Bullpup_3.obj
* Pistol_1.obj · Pistol_2.obj · Pistol_3.obj · Pistol_4.obj
* Pistol_5.obj · Pistol_6.obj · Revolver_1.obj · Revolver_2.obj
* Revolver_3.obj · Revolver_4.obj · Revolver_5.obj · Shotgun_1.obj
* Shotgun_2.obj · Shotgun_3.obj · Shotgun_4.obj · Shotgun_SawedOff.obj
* Shotgun_ShortStock.obj · SniperRifle_1.obj · SniperRifle_2.obj · SniperRifle_3.obj
* SniperRifle_4.obj · SniperRifle_5.obj · SniperRifle_6.obj · SubmachineGun_1.obj
* SubmachineGun_2.obj · SubmachineGun_3.obj · SubmachineGun_4.obj · SubmachineGun_5.obj

Saath me **40 `.mtl`** (har gun ka apna material — colour wahi se aata hai) aur `LICENSE.txt` (CC0 1.0). Total 81 files (40 + 40 + 1). Folder ka naam `Weapons` (capital W) hai; output `assets/models/weapons/` (chhote `w`) me jaata hai.

## 2) Guns ka model mapping (28/28 downloaded model pe)

| Gun | model id | file | size (game me) |
|---|---|---|---|
| AK | `ar_5` | `AssaultRifle_5.glb` | 1.20 m |
| M4A1 | `ar_6` | `AssaultRifle2_1.glb` | 1.20 m |
| SCAR | `ar_7` | `AssaultRifle2_2.glb` | 1.20 m |
| M7 | `ar_9` | `AssaultRifle2_4.glb` | 1.20 m |
| XM8 | `ar_8` | `AssaultRifle2_3.glb` | 1.20 m |
| Groza | `bullpup_1` | `Bullpup_1.glb` | 1.20 m |
| FAMAS | `bullpup_2` | `Bullpup_2.glb` | 1.20 m |
| AUG | `bullpup_3` | `Bullpup_3.glb` | 1.20 m |
| Parafal | `ar_1` | `AssaultRifle_1.glb` | 1.20 m |
| AN94 | `ar_2` | `AssaultRifle_2.glb` | 1.20 m |
| Kingfisher | `ar_4` | `AssaultRifle_4.glb` | 1.20 m |
| MP40 | `smg_2` | `SubmachineGun_2.glb` | 0.60 m |
| MP5 | `smg_1` | `SubmachineGun_1.glb` | 0.60 m |
| UMP | `smg_4` | `SubmachineGun_4.glb` | 0.66 m |
| P90 | `smg_3` | `SubmachineGun_3.glb` | 0.60 m |
| Thompson | `smg_5` | `SubmachineGun_5.glb` | 0.72 m |
| Bizon | `smg_1` | `SubmachineGun_1.glb` | 0.78 m |
| Skorpion | `smg_3` | `SubmachineGun_3.glb` | 0.42 m |
| Vector | `smg_4` | `SubmachineGun_4.glb` | 0.54 m |
| Kar98k | `sniper_1` | `SniperRifle_1.glb` | 1.40 m |
| AWM | `sniper_2` | `SniperRifle_2.glb` | 1.40 m |
| M82B | `sniper_3` | `SniperRifle_3.glb` | 1.40 m |
| M1014 | `shotgun_1` | `Shotgun_1.glb` | 1.10 m |
| MAG-7 | `shotgun_2` | `Shotgun_2.glb` | 1.10 m |
| SPAS12 | `shotgun_3` | `Shotgun_3.glb` | 1.10 m |
| Desert Eagle | `pistol_6` | `Pistol_6.glb` | 0.30 m |
| USP | `pistol_1` | `Pistol_1.glb` | 0.30 m |
| M500 | `revolver_1` | `Revolver_1.glb` | 0.30 m |

**%d alag model** use ho rahe hain (%d guns me). 3 SMG jaan-boojh kar model share karte hain — rang aur size alag hai, isliye dikhne me alag lagte hain: **MP5**(black/grey) vs **Bizon**(dark green, 1.3x), **P90**(black/olive) vs **Skorpion**(grey, 0.7x), **UMP**(dark blue, 1.1x) vs **Vector**(white/red, 0.9x).

## 3) MODIFIED files (sirf jo hisse badle)

| File | Kya badla |
|---|---|
| `tools/obj2glb.py` **(naya)** | OBJ (+MTL) -> GLB converter. Barrel `+X` -> `-Z` (rotY 90), winding check (ulta model andar se bahar na dikhe), per-polygon material slots MTL ke `Kd` se, normals sanitise, AABB centre + longest side 1.0 m, fail-soft CLI + `--report` JSON. |
| `assets/downloaded_obj/` **(naya folder)** | 40 `.obj` + 40 `.mtl` + `LICENSE.txt` (aapka upload, commit kiya) + **`.gdignore`** — taaki Godot inhe scan na kare (FBX wale hang se bachne ke liye). |
| `scripts/asset_loader.gd` | `BASE_DIRS` me `res://assets/downloaded_obj/`, `EXTENSIONS` me `.obj`, `FILE_PREFIXES` me `pistol`/`revolver`/`submachine`; naya `load_mesh_node()` — Godot agar file ko `Mesh` de (PackedScene nahi) to `MeshInstance3D` me lapet deta hai. Cache + `null` fallback waise hi. |
| `scripts/assets.gd` | Naya `_load_weapon_instance()`; `_prepare_weapon_model()` me `_normalize_orientation()` (barrel -Z) + `_normalize_scale()` (target: pistol 0.30 / smg 0.60 / rifle 1.20 / sniper 1.40 / shotgun 1.10 m + safety: <0.3 m -> x3, >1.5 m -> x0.5); naya `_weapon_target_length()`; skin metallic **0.6**, roughness **0.4**. |
| `scripts/weapon_data.gd` | `WEAPON_MODELS` poora remap (28 entries) + header comments. |
| `scripts/selftest.gd` | Model scan log me print + naye checks: 28 guns, >=25 downloaded model, >=22 alag model, har gun ka model + muzzle. |
| `.github/workflows/build-apk.yml` | Naya step **7d) OBJ -> GLB conversion** (`python3 tools/obj2glb.py assets/downloaded_obj --out-root assets/models`), FBX step ab `--skip-existing`, cache key me OBJ hash, order 7d(obj) -> 7d(fbx) -> 7e -> 8d. |
| `tools/fbx2glb.py` | Naya `--skip-existing` (OBJ se bane weapons GLB ko FBX step overwrite na kare). |
| `tools/objpreview.py`, `docs/renders/*.png` **(naya)** | Offline side-view renderer + 3 montage — isi se barrel ka `+X` rule verify hua (isliye converter ko 180° auto-flip nahi chahiye). |
| `README.md`, `docs/model-assets-notes.md` | OBJ pipeline, muzzle direction aur winding ka section. |
| `.gitignore` | `assets/downloaded_obj/**/*.glb`, `*.gltf`, `*.obj.import` ignore. |

## 4) VERIFY (phone pe kya dekhna hai)

1. **AK = AssaultRifle model** — `ar_5` = `AssaultRifle_5.glb` (wood-stock AKM): wooden stock + curved mag.
2. **M4A1 alag AR** — `ar_6` = `AssaultRifle2_1.glb` (M4/AR-15 + buffer tube) — AK se shape saaf alag.
3. **28 weapons switch + sab visible** — CI log me har gun ki line aati hai (`AK -> ar_5 res://assets/models/weapons/AssaultRifle_5.glb`), aur `docs/renders/` ki 3 montage me poore pack ke silhouette hain. Pistol/revolver bhi ab model pe (`Pistol_6`, `Pistol_1`, `Revolver_1`).
4. **Muzzle flash barrel ke aage** — muzzle node AABB ke sabse aage wale sirre (barrel -Z) pe lagta hai; fire karke dekho flash gun ke aage hi nikalta hai (stock ke andar nahi).
5. **FPS > 30** — poore pack me sirf **56,822 triangles** (ek gun 309-1160 tris), koi texture nahi (sirf colour) — procedural models se bhi halka.
6. **Fail-soft** — koi model file delete kar do to game phir bhi chalta hai (procedural gun), crash nahi.

### CI evidence (last 2 runs — dono **Success**)
* Run `38910959200` (#44, commit `cb55478`) — 1 m 9 s; run `38911384726` (#45, commit `00663d5`) — 1 m 5 s.
  Dono me annotation: *"Asset selftest PASS (downloaded + procedural dono chal rahe hain)"*, aur step
  **7d) OBJ -> GLB conversion**, **7e) GLB sanity check**, **8d) Asset selftest**, **9) APK export** sab success.
* Artifact `FreeFireFPS-apk` 23.7 MB (`sha256:b54fa685…a1ab`) + `build-log`.
* Release **`latest-apk`** ka `FreeFireFPS.apk` = **25,155,101 bytes** (2026-10-16 13:54 UTC) — phone pe direct download.
* Local validation (jaisa CI karta hai): `obj2glb.py` 40/40 converted, `glbcheck.py` **40/40, 0 errors**, 56,822 tris; har GLB ka Z = longest axis aur lambai = 1.000 (barrel -Z convention sab me sahi); winding check 40/40 *theek* (koi model inside-out nahi).

## 5) IF IT FAILS — 3 sabse zyada mumkin errors + fix

| # | Lakshan | Wajah | Fix |
|---|---|---|---|
| 1 | Gun **ulta** dikhta hai (mag upar / barrel peeche) | model ki winding ulti hai ya barrel -Z nahi | `tools/obj2glb.py` me winding threshold (`winding_is_inverted()`, abhi 0.4) dekho; ya `scripts/assets.gd` ke `_normalize_orientation()` me `rotate_y(PI)` wali branch on karo (default me jaan-boojh kar off hai — reason `docs/model-assets-notes.md` me). |
| 2 | Gun **badi/chhoti** (screen bhar rahi ya gayab) | model ki asli lambai target se door | `scripts/weapon_data.gd` me us gun ka `"scale"` badlo (`0.7` chhota / `1.3` bada). `_normalize_scale()` ke rules (<0.3 m -> x3, >1.5 m -> x0.5) uske upar lagte hain. |
| 3 | CI me `7d`/8d fail ya `MISSING` model | `.obj`/`.mtl` ka naam schema se alag | `scripts/asset_loader.gd` ke `FILE_PREFIXES`/`SECOND_GROUP` me naya naam jodo, ya `weapon_data.gd` me us gun ka `"model"` badlo. Missing model pe game procedural banata hai — crash nahi. |

Note: `7d` step `continue-on-error` hai, isliye conversion fail hone pe bhi build rukta nahi — 7e/8d warnings dikhengi aur game procedural pe ban jayega. Us case me `build/obj-report.json` (artifact `build-log`) me dekho kaunsi file skip hui.
