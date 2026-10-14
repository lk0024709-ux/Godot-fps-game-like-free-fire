# Free Fire Style FPS — Godot 4.2 (PC + Android)

Ek chhota par **pura 3D First-Person Shooter**, jo PC (WASD + mouse) aur Android
(touch joystick + swipe) dono pe chalta hai.
Sab kuch **procedural** hai — koi image, sound ya external asset download nahi karna padta.
APK **GitHub Actions** se automatic ban jata hai, PC pe Godot install karne ki zaroorat nahi.

---

## 1. APK kaise banega (step by step)

1. Ye repo GitHub pe push karo (ya merge karo).
2. Repo me **Actions** tab kholo.
3. `Build Android APK` workflow apne aap chalu ho jayega (har push pe chalta hai).
   Manually chalane ke liye: **Actions → Build Android APK → Run workflow**.
   Workflow sab kuch khud karta hai — Godot 4.2.2 download, export templates install,
   keystore, APK export, upload. Kisi third-party action pe depend nahi karta.
4. ~2-4 minute wait. Green tick aa gaya to APK ready hai.
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
| Chalna | `W A S D` (ya arrow keys) | Left-bottom **joystick** |
| Dekhna | Mouse | Screen ke **right half pe swipe** |
| Firing | Left click / Enter (hold = auto fire) | **FIRE** button (bottom-right) |
| Gun badalna | `Q` pichhla / `E` agla / `mouse wheel`, `1-9` seedha gun | **SWAP** button (agla gun) |
| Poori gun list (28) | `G` | **GUNS** button |
| Reload | `R` (khali hone pe khud bhi hota hai) | **RELOAD** button |
| Jump | `Space` | **JUMP** button |
| Mouse free/capture | `Esc` / click | — |
| Restart (marne ke baad) | `TAP TO RESTART` button | `TAP TO RESTART` button |

---

## 3. Gameplay rules (jo maanga gaya tha)

- First-person camera, **FOV 75**, player ki head height pe
- Player **100 HP** se shuru, enemy touch = **-10 HP**
- Enemy marne pe **+10 score**
- Goli **2 second** me gayab, enemy 2 goli me marta hai, takrayi to damage deti hai
- Enemies random (8 fixed puntos me se, player se door) spawn hote hain aur chal ke paas aate hain
- HP 0 → **GAME OVER** screen + restart button
- Zameen 40×40 (grid shader), cover boxes/pillars, boundary walls, DirectionalLight with shadows
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
- **Skin colours**: sirf 5 base models bante hain (pistol / smg / rifle / sniper / shotgun),
  aur colour badalne se 28 different guns ban jate hain. Koi texture nahi — sirf
  `StandardMaterial3D` ka `albedo_color`.
- Reload **1.2 s**, magazine khali hone pe **khud** reload hota hai.
- `GUNS` button (ya PC pe `G`) se poori list khulti hai — har button pe us gun ka skin
  colour dikhta hai, tap karo aur gun equip.
- Ammo poora bhara milta hai (reserve ammo system nahi hai) — simple rakhne ke liye.
- Enemy ka HP **100** hai (pehle 20 tha) taaki chhoti gun aur sniper me farq mehsoos ho.
  Wapas 20 karna ho to `scripts/enemy.gd` me `max_health = 100.0` ki jagah `20.0` kar do.

---

## 4. Files (kya kya hai aur kis kaam ka)

```
project.godot                  # Project settings: naam, 1280x720, mobile renderer, input keys (WASD/jump/fire), landscape orientation
export_presets.cfg             # Android export preset (naam "Android", arm64-v8a, APK, signed) — isi ko Actions use karta hai
icon.svg                       # Launcher icon (hand-made SVG, koi download nahi)

scenes/main.tscn               # Main scene: sky + sun + player + HUD + timer (baaki duniya code me banti hai)
scenes/player.tscn             # Player body + head + camera (FOV 75) + gun model
scenes/enemy.tscn              # Enemy (capsule + head + visor) + wall-check ray
scenes/bullet.tscn             # Goli ka chhota glowing sphere
scenes/hud.tscn                # Crosshair, HP bar, score, GAME OVER panel, joystick + FIRE/JUMP buttons

scripts/main.gd                # Game manager: arena banata hai, enemies spawn karta hai, score + game over
scripts/weapon_data.gd         # 28 weapons ke stats + skin colours (sirf data — yahan numbers badlo)
scripts/weapon_manager.gd      # Gun switching, ammo, reload, model lagana (signals HUD ko bhejta hai)
scripts/assets.gd              # 5 weapon models — sab box/cylinder/cone/sphere se, koi texture nahi
scripts/player.gd              # Movement (WASD/joystick), look (mouse/swipe), jump, firing, health/damage
scripts/enemy.gd               # Player ko follow karta hai, touch pe damage, flash + death
scripts/bullet.gd              # Ray-check wali goli (2 sec lifetime, enemy ko damage)
scripts/hud.gd                 # HUD values, buttons ke signals, damage flash, game over screen
scripts/joystick.gd            # On-screen virtual joystick (khud draw karta hai, koi image nahi)

.github/workflows/build-apk.yml # GitHub Actions: Godot 4.2.2 download + keystore + APK export + upload
```

---

## 5. Kya-kya tweak karna hai kahan

| Kya chahiye | Kahan badlo |
|---|---|
| Player speed / jump | `scripts/player.gd` → `move_speed`, `jump_velocity` |
| Firing speed / damage | `scripts/player.gd` → `fire_cooldown`, `bullet_damage` |
| Mouse / touch sensitivity | `scripts/player.gd` → `mouse_sensitivity`, `touch_sensitivity` |
| Enemy speed / HP / damage | `scenes/enemy.tscn` khologe to inspector me dikhega, ya `scripts/enemy.gd` ke `@export` defaults |
| Kitne enemies + spawn speed | `scenes/main.tscn` → `Main` node ke inspector me (`max_enemies`, `spawn_interval`) |
| Maidan ka size / cover boxes | `scripts/main.gd` → `arena_size` aur `_obstacles` list |
| Kisi bhi gun ka damage / ammo / speed | `scripts/weapon_data.gd` → us gun ki line (ek hi line me sab hai) |
| Gun ka rang (skin) | `scripts/weapon_data.gd` → wahi line, `GOLD`/`BLACK` jaise colour naam |
| Naye colour add karne ho | `scripts/weapon_data.gd` ke top pe `const MY_COLOR := Color(...)` |
| Reload time | `scripts/weapon_manager.gd` → `reload_time` (default 1.2) |
| Gun ka size screen pe | `scenes/player.tscn` → `Head/Camera3D/WeaponHolder` ki position, aur `weapon_manager.gd` ka `model_scale` (0.7) |
| Enemy ka HP | `scripts/enemy.gd` → `max_health` (abhi 100) |
| Score per kill | `scripts/main.gd` → `_on_enemy_died()` me `score += 10` |
| HUD ka rang / button size | `scenes/hud.tscn` ke stylebox + offsets |

Tip: har script ke `@export` variables Godot editor me Inspector me dikhte hain — code chhue bina values badal sakte ho.

---

## 6. Kuch galat ho to (troubleshooting)

| Problem | Kya karo |
|---|---|
| Actions me **export** step fail | Log me `keystore` ya `Android SDK` word dhundo. Is repo me keystore step pehle se hai, so iska matlab usually SDK/build-tools ka issue hai — log paste karo, fix mil jayega |
| Actions me **import** step me JS/JSON error | `.tscn` file me syntax issue — log ki line paste karo |
| Phone pe "App not installed" | Purana app uninstall karo (test keystore badal jata hai), ya Settings me "unknown sources" allow karo |
| Gun badalne/equip karne ke liye mobile pe | **SWAP** (agla gun) ya **GUNS** (poori list) — PC pe `Q`/`E`/`G`/`1-9` |
| Gun-picker khulta hai par tap kaam nahi karta | Pehli ungli joystick pe hai to doosri ungli ke tap ko Android/Godot mouse me nahi badalta — joystick chhod kar tap karo |
| Game khulta hai par touch kaam nahi karta | Confirm karo ki build **Android** ke liye hua (PC/other platform ke liye nahi) aur `hud.tscn` me `TouchControls` node hai |
| Game crash / black screen | Android me `adb logcat` chalao ya phone pe crash dialog ka text bhej do |
| PC pe test karna hai | PC pe **Godot 4.2.2** install karo (free, ~100 MB) → `project.godot` import karo → `F5` dabao |
| Build fail hua par log nahi dikh raha | Fail hue commit ke neeche ek **comment** post hota hai (workflow ka aakhri step) — usme poora build log hai. Ya Actions run page pe failed step kholo |
| Performance kam hai | `project.godot` me `renderer/rendering_method="gl_compatibility"` kar do, aur `scripts/main.gd` me `max_enemies` 8 → 4 |

---

## 7. Aage kya add kar sakte ho

- Sound: `AudioStreamPlayer` + procedurally generated beeps (`AudioStreamGenerator`) ya free `.wav` add karke
- Reload + ammo system, headshot bonus, enemy health bar
- Multiple weapons (2-3 gun models already code se banti hain)
- Waves / levels, high score save (`user://` me JSON)
- Enemy ko dodge karna sikhana, ya sniper enemy

---

## Credit / License

Sab code is repo me likha gaya hai — koi third-party asset nahi.
Game code: MIT style, jo chaho karo. Godot Engine ka apna license (MIT) hai.
