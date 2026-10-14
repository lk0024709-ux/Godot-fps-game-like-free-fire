extends Node
##
## WeaponManager — weapon switching, ammo, reload aur model banane ka kaam.
## Ye Node player ke andar chalta hai (player.gd isko bana ke add karta hai).
##
## Signals:
##   weapon_changed(name, ammo, ammo_max) -> HUD naam + ammo dikhata hai
##   ammo_changed(ammo)                   -> HUD sirf ammo number badalta hai
##   reload_started(reload_time) / reload_finished()
##   index_changed(index)                 -> gun-picker me current gun highlight
##

signal weapon_changed(weapon_name: String, ammo: int, ammo_max: int)
signal ammo_changed(ammo: int)
signal reload_started(reload_time: float)
signal reload_finished()
signal index_changed(index: int)

const ASSETS := preload("res://scripts/assets.gd")
const DATA := preload("res://scripts/weapon_data.gd")

@export var start_index: int = 0        ## shuru me kaunsa weapon (0 = Desert Eagle)
@export var reload_time: float = 1.2    ## spec: 1.2 second
@export var model_scale: float = 0.7    ## view-model ka size

var weapons: Array[Dictionary] = []     ## saare 28 weapons (weapon_data.gd se)
var current_index: int = 0
var current_ammo: int = 0
var reloading: bool = false

var holder: Node3D = null               ## jisme model add hota hai (player ke camera pe)
var muzzle: Node3D = null               ## muzzle flash node (naam "Muzzle")

var _reload_left: float = 0.0
var _model: Node3D = null
var _equipped: bool = false             ## pehli baar weapon lag gaya?


func _ready() -> void:
	weapons = DATA.get_weapons()
	switch_weapon(start_index)


func _process(delta: float) -> void:
	if not reloading:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		reloading = false
		current_ammo = get_ammo_max()
		ammo_changed.emit(current_ammo)
		reload_finished.emit()


# ============================================================ INFO / GETTERS =

func get_current() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[clampi(current_index, 0, weapons.size() - 1)]


func get_current_name() -> String:
	return String(get_current().get("name", "?"))


func get_ammo_max() -> int:
	return int(get_current().get("ammo", 0))


func get_fire_delay() -> float:
	return float(get_current().get("fire_rate", 0.1))


## Auto weapon hai? (dabaye rakhne pe lagatar chalti rehti hai)
func is_auto() -> bool:
	return bool(get_current().get("auto", false))


func get_weapon_count() -> int:
	return weapons.size()


# ========================================================== SHOOTING / AMMO ==

## Goli chala sakte hain? (reload chal raha ho ya magazine khali ho -> nahi)
func can_shoot() -> bool:
	return not reloading and current_ammo > 0


## Ek goli kam karo. Magazine khali ho gayi to khud reload shuru.
func consume_ammo() -> void:
	if current_ammo <= 0:
		return
	current_ammo -= 1
	ammo_changed.emit(current_ammo)
	if current_ammo <= 0:
		start_reload()


func start_reload() -> void:
	if reloading or current_ammo >= get_ammo_max():
		return
	reloading = true
	_reload_left = reload_time
	reload_started.emit(reload_time)


## Reload beech me rok do (weapon badalne pe)
func cancel_reload() -> void:
	if reloading:
		reloading = false
		_reload_left = 0.0


# ============================================================== SWITCHING ====

## Kisi bhi index pe jao (index range ke bahar ho to round ho jata hai)
func switch_weapon(index: int) -> void:
	if weapons.is_empty():
		return
	var count := weapons.size()
	var target := ((index % count) + count) % count
	if target == current_index and _equipped:
		return                       # wahi weapon dobara -> kuch nahi karo

	current_index = target
	cancel_reload()
	current_ammo = get_ammo_max()
	_equipped = true
	build_model()
	weapon_changed.emit(get_current_name(), current_ammo, get_ammo_max())
	index_changed.emit(current_index)


func next_weapon() -> void:
	switch_weapon(current_index + 1)


func prev_weapon() -> void:
	switch_weapon(current_index - 1)


# ================================================================= MODEL =====

## Player apna weapon-holder node de deta hai -> model usme lagta hai
func set_holder(new_holder: Node3D) -> void:
	holder = new_holder
	build_model()


## Current weapon ka model banata hai (shape + skin colours assets.gd se)
func build_model() -> void:
	if holder == null or not is_instance_valid(holder):
		return
	if _model != null and is_instance_valid(_model):
		holder.remove_child(_model)
		_model.queue_free()
	_model = null
	muzzle = null

	var weapon := get_current()
	if weapon.is_empty():
		return

	_model = ASSETS.build_weapon_model(
			String(weapon.get("shape", "rifle")),
			weapon.get("body", Color.WHITE),
			weapon.get("accent", Color.BLACK))
	if _model == null:
		return

	_model.scale = Vector3.ONE * model_scale
	holder.add_child(_model)
	muzzle = _model.find_child("Muzzle", true, false)
