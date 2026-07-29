extends Node3D
class_name Vehicle
## Vehicle — camión que recorre la fábrica (spec §4 "vehículos desplazándose").
##
## Modelo 3D generado por código (cabina, remolque, ruedas). Sigue una lista de
## puntos y se elimina al terminar el recorrido. Lo usa VehicleManager para
## representar entregas de proveedores y despachos a clientes.
##
## Nota de estructura: dominio propio (paralelo a assets/scenes/vehicles).

var _waypoints: Array = []
var _idx: int = 0
var _speed: float = 9.0
var kind: String = "truck"
var loop: bool = false

func setup(waypoints: Array, color: Color, p_kind: String = "truck", p_loop: bool = false) -> void:
	_waypoints = waypoints
	kind = p_kind
	loop = p_loop
	if kind == "forklift":
		_speed = 4.5
	if _waypoints.size() > 0:
		global_position = _waypoints[0]
		_idx = 1
	if kind == "forklift":
		_build_forklift(color)
	else:
		_build_visual(color)

func _process(delta: float) -> void:
	if _idx >= _waypoints.size():
		if loop and _waypoints.size() > 1:
			_idx = 0
		else:
			queue_free()
			return
	var target: Vector3 = _waypoints[_idx]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.6:
		_idx += 1
		return
	var dir := to.normalized()
	global_position += dir * _speed * delta
	# Orientación suave hacia el rumbo.
	var look := global_position + dir
	var tf := global_transform.looking_at(look, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(tf.basis, clampf(delta * 6.0, 0, 1))

func _build_visual(color: Color) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = color
	body.roughness = 0.5
	body.metallic = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.7
	var cargo := StandardMaterial3D.new()
	cargo.albedo_color = Color(0.55, 0.56, 0.58)
	cargo.roughness = 0.6
	cargo.metallic = 0.5

	# Cabina.
	_box(Vector3(1.8, 1.4, 1.8), Vector3(0, 1.1, 1.9), body)
	_box(Vector3(1.7, 0.7, 0.1), Vector3(0, 1.5, 2.85), dark)   # parabrisas
	# Remolque de carga.
	_box(Vector3(2.0, 1.8, 3.6), Vector3(0, 1.3, -0.9), cargo)
	_box(Vector3(2.05, 0.15, 3.65), Vector3(0, 2.25, -0.9), dark)
	# Chasis.
	_box(Vector3(1.9, 0.3, 5.6), Vector3(0, 0.5, 0.4), dark)
	# Ruedas.
	for wz in [2.0, -0.4, -1.6]:
		for wx in [-1, 1]:
			var wheel := _cyl(0.4, 0.4, 0.3, Vector3(wx * 0.95, 0.4, wz), dark)
			wheel.rotation_degrees = Vector3(0, 0, 90)
	# Faros.
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 0.95, 0.7)
	head.emission_enabled = true
	head.emission = Color(1, 0.95, 0.7)
	head.emission_energy_multiplier = 2.0
	for hx in [-0.6, 0.6]:
		_box(Vector3(0.25, 0.25, 0.05), Vector3(hx, 0.9, 2.85), head)

func _build_forklift(color: Color) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = color
	body.roughness = 0.5
	body.metallic = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.7
	var fork := StandardMaterial3D.new()
	fork.albedo_color = Color(0.5, 0.5, 0.55)
	fork.roughness = 0.4
	fork.metallic = 0.8
	# Cuerpo / contrapeso.
	_box(Vector3(1.3, 1.0, 1.8), Vector3(0, 0.9, -0.6), body)
	_box(Vector3(1.2, 0.7, 0.8), Vector3(0, 1.5, -1.1), dark)   # bloque motor trasero
	# Jaula del conductor.
	for sx in [-1, 1]:
		for sz in [-0.2, 0.9]:
			_cyl(0.05, 0.05, 1.4, Vector3(sx * 0.55, 2.0, sz), dark)
	_box(Vector3(1.3, 0.08, 1.3), Vector3(0, 2.7, 0.35), dark)
	# Mástil delantero.
	for sx in [-1, 1]:
		_box(Vector3(0.12, 2.4, 0.12), Vector3(sx * 0.4, 1.4, 1.0), dark)
	# Horquillas.
	for sx in [-1, 1]:
		_box(Vector3(0.15, 0.08, 1.1), Vector3(sx * 0.3, 0.35, 1.6), fork)
	# Ruedas.
	for wz in [0.2, -1.1]:
		for wx in [-1, 1]:
			var wheel := _cyl(0.35, 0.35, 0.28, Vector3(wx * 0.65, 0.35, wz), dark)
			wheel.rotation_degrees = Vector3(0, 0, 90)
	# Baliza ámbar.
	var beacon := StandardMaterial3D.new()
	beacon.albedo_color = Color(0.95, 0.6, 0.1)
	beacon.emission_enabled = true
	beacon.emission = Color(0.95, 0.55, 0.1)
	beacon.emission_energy_multiplier = 2.0
	_cyl(0.1, 0.1, 0.18, Vector3(0, 2.8, 0.35), beacon)

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _cyl(tr: float, br: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tr
	cm.bottom_radius = br
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
