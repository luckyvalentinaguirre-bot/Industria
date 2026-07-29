extends Node3D
class_name Worker
## Worker — trabajador físico en el mundo 3D (spec §12).
##
## Placeholder 3D (cápsula con color por especialidad) que deambula por la
## fábrica entre las máquinas, dando vida a la escena. Sus efectos de juego
## (productividad, calidad, mantenimiento) los agrega WorkerManager.

var type_id: String = "operator"
var worker_name: String = "Operario"
var salary: float = 90.0
var specialty: String = "production"
var productivity: float = 1.0
var experience: float = 0.0

var _speed: float = 2.2
var _target: Vector3
var _has_target: bool = false

func setup(id: String, def: Dictionary) -> void:
	type_id = id
	worker_name = String(def.get("name", id))
	salary = float(def.get("salary", 90.0))
	specialty = String(def.get("specialty", "production"))
	productivity = float(def.get("base_productivity", 1.0))
	_build_visual()

func _process(delta: float) -> void:
	if not _has_target:
		_pick_target()
		return
	var dir := _target - global_position
	dir.y = 0
	if dir.length() < 0.4:
		_has_target = false
		return
	global_position += dir.normalized() * _speed * delta
	look_at(global_position + dir, Vector3.UP)

func _pick_target() -> void:
	var machines: Array = GameManager.machines.machines if GameManager.machines else []
	if machines.size() > 0 and randf() < 0.7:
		var m = machines[randi() % machines.size()]
		if is_instance_valid(m):
			_target = m.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			_has_target = true
			return
	# Deambular aleatorio dentro de la fábrica.
	var extent := GameState.grid_size.x * GameState.CELL_SIZE * 0.3
	_target = Vector3(randf_range(-extent, extent), 0, randf_range(-extent, extent))
	_has_target = true

func _build_visual() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	body.mesh = cap
	body.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _specialty_color()
	mat.roughness = 0.7
	body.material_override = mat
	add_child(body)
	# Casco.
	var helmet := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.4
	helmet.mesh = hm
	helmet.position = Vector3(0, 1.7, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.95, 0.8, 0.2)
	helmet.material_override = hmat
	add_child(helmet)

func _specialty_color() -> Color:
	match specialty:
		"production": return Color(0.3, 0.5, 0.8)
		"maintenance": return Color(0.8, 0.4, 0.2)
		"quality": return Color(0.4, 0.7, 0.4)
		"logistics": return Color(0.6, 0.4, 0.7)
		_: return Color(0.6, 0.6, 0.6)

func to_dict() -> Dictionary:
	return { "type_id": type_id, "experience": experience }
