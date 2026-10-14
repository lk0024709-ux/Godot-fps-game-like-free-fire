extends Node3D
##
## Bullet (goli) — damage system
## Shooter se spawn hoti hai, apni "direction" me seedha aage badhti hai.
## Raaste me jo pehli cheez (enemy / deewar / zameen) mile usse damage deti hai
## aur khud delete ho jaati hai. max_life second tak kuch na lage to bhi delete.
##
## Har physics frame pe ray-cast hota hai (pichli jagah se nayi jagah tak),
## isliye tez goli bhi deewar/enemy ke aar-paar nahi nikalti (no tunnelling).
## (Area3D + body_entered wale tarike me tez goli chhoot jati hai, isliye
##  ye ray-sweep tarika zyada bharosemand hai — baaki API wahi hai: damage,
##  die() / take_damage().)
##

@export var speed: float = 26.0        ## metres per second (weapon apni speed deta hai)
@export var damage: float = 10.0       ## kitna HP katega (weapon se aata hai)
@export var max_life: float = 2.5      ## itne second baad gayab

var direction: Vector3 = Vector3.FORWARD   ## player.gd set karta hai
var shooter = null                         ## jisne goli chalayi (khud ko na maare)

var _life: float = 2.5


func _ready() -> void:
	_life = max_life
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
	var from_pos := global_position
	var to_pos := from_pos + direction * speed * delta

	# 1) Ray-cast: agle frame wali jagah tak kuch aata hai kya?
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if shooter is CollisionObject3D:
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


## Kuch lag gaya -> damage do.
## Enemy ke paas take_damage() hai (HP kam karta hai, marne pe die() khud call hota
## hai). Kisi aur cheez ke paas sirf die() ho to wahi call kar dete hain.
## Player ko jaan-boojh kar chhod dete hain (friendly fire off) — warna goli
## player ke die() ko call karke khud hi maar deti.
func _apply_hit(collider) -> void:
	if collider is Node and not collider.is_in_group("player"):
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		elif collider.has_method("die"):
			collider.die()
	# zameen / deewar / player -> bas gayab ho jao
	queue_free()
