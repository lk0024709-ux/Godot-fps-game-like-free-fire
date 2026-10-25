extends Node3D
## Lightweight NPC loot marker. One shared-style visual, no collision or per-frame work.

var consumed: bool = false
var weapon_name: String = "Loot Rifle"


func _ready() -> void:
	add_to_group("loot_weapon")
	set_meta("loot_weapon", true)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponVisual"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.72, 0.12, 0.18)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.68, 0.16)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.18, 0.02)
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.rotation.y = 0.35
	add_child(mesh_instance)


func consume() -> bool:
	if consumed:
		return false
	consumed = true
	visible = false
	queue_free()
	return true
