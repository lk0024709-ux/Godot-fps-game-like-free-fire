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
