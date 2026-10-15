extends Area3D
##
## Bullet (goli) — damage system (spec: Area3D + @export damage)
##
## Shooter se spawn hoti hai, apni "direction" me seedha aage badhti hai
## (26 unit/second default, max_life 2.5 second — dono @export hain aur weapon
##  apni speed bhej deta hai: sniper tez, shotgun dheemi).
##
## Hit kaise pakadta hai — DO tarike (dono ek hi jagah damage dete hain):
##   1) Area3D ka body_entered signal  -> spec wala tarika
##   2) har physics frame ek chhoti ray (pichli jagah -> agli jagah)
##      -> isse tez goli deewar/enemy ke aar-paar NAHI nikalti. Mobile pe FPS
##         kam ho to Area3D overlap miss ho sakta hai; ray use bacha leta hai.
##
## Damage ka rule: pehle take_damage() (HP kam hota hai, marne pe die() khud
## call ho jata hai), aur agar kisi cheez me sirf die() hai to wahi.
## Player ko chhod dete hain (friendly fire off).
## Visual: peela emissive sphere — bullet.tscn me (koi texture nahi).
##

@export var speed: float = 26.0        ## metres per second
@export var damage: float = 10.0       ## kitna HP katega (weapon se aata hai)
@export var max_life: float = 2.5      ## itne second baad gayab
@export var target_group: String = "enemy"   ## is group ko damage hota hai

var direction: Vector3 = Vector3.FORWARD   ## player.gd set karta hai
var shooter = null                         ## jisne goli chalayi (khud ko na maare)

var _life: float = 2.5
var _spent: bool = false                   ## ek baar lagi -> dobara damage nahi


func _ready() -> void:
	_life = max_life
	monitoring = true
	monitorable = true
	# 1 = duniya (zameen / deewar / crate), 4 = enemy ka layer (enemy.tscn me 4)
	collision_mask = 1 | 4
	body_entered.connect(_on_body_entered)
	face_direction()


## Goli ko uski direction me ghumata hai (tracer theek dikhe)
func face_direction() -> void:
	if direction.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	# Agar goli bilkul seedhi upar/niche ja rahi ho to look_at() error deta hai
	if absf(direction.normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	look_at(global_position + direction.normalized(), up)


func _physics_process(delta: float) -> void:
	if _spent:
		return

	var from_pos := global_position
	var to_pos := from_pos + direction * speed * delta

	# 1) Ray-cast: agle frame wali jagah tak kuch aata hai kya?
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1 | 4
	if shooter is CollisionObject3D and is_instance_valid(shooter):
		query.exclude = [(shooter as CollisionObject3D).get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position = to_pos   # kuch nahi mila -> aage badho
	else:
		_apply_hit(hit.get("collider"))
		return

	# 2) Purani goli delete
	_life -= delta
	if _life <= 0.0:
		queue_free()


## spec: Area3D ka body_entered -> us body ko damage
func _on_body_entered(body: Node3D) -> void:
	_apply_hit(body)


## Kuch lag gaya -> damage do (aur goli gayab).
## Enemy ke paas take_damage() hai (HP kam karta hai, marne pe die() khud call
## hota hai). Kisi aur cheez ke paas sirf die() ho to wahi call kar dete hain.
## Player / apni hi goli -> kuch nahi (friendly fire off).
func _apply_hit(collider) -> void:
	if _spent:
		return
	if collider == null or not (collider is Node):
		return
	if collider == shooter:
		return                                  # apni hi goli se damage nahi

	if (collider as Node).is_in_group(target_group):
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		elif collider.has_method("die"):
			collider.die()
	elif (collider as Node).is_in_group("enemy") or (collider as Node).is_in_group("player"):
		return                                   # doosri team -> kuch nahi

	# yahan aaye = kuch lag gaya (enemy / deewar / zameen) -> goli khatam
	_spent = true
	queue_free()
