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
