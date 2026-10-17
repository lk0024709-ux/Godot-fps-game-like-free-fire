# Home screen images

| File | Size | Kaam |
|---|---|---|
| `home_bg.png` | 1672 x 941 (16:9) | Home lobby ka background. `scripts/home.gd` ise `STRETCH_KEEP_ASPECT_COVERED` se poori screen pe bichhata hai. |
| `home_logo.png` | ~250 x 100 | (Optional) top-left logo. File na ho to game `icon.svg` + "INDUS / BATTLE ROYALE" text lockup dikhata hai. |

## Badalna kaise hai

1. Naya background: koi bhi 16:9 PNG isi naam se replace kar do (`home_bg.png`).
2. Naya logo: transparent PNG `home_logo.png` naam se isi folder me daal do.
3. `project.godot` me `config/icon` abhi bhi `res://icon.svg` hai — APK ka launcher icon
   badalna ho to wahi `icon.svg` replace karo.

Godot build ke waqt (`--import`) in dono ko apne aap import karta hai; `.import` files
repo me commit nahi hoti (`.gitignore` me `*.import` hai).
