extends Node3D
class_name Conveyor
## Conveyor — cinta transportadora que mueve ítems entre dos puertos (spec §9).
##
## Conecta un proveedor (salida de máquina / almacén) con un receptor (entrada
## de máquina / almacén). Toma ítems del origen, los desplaza visiblemente por
## la banda y los deposita en el destino. Los "paquetes" son meshes reutilizados
## y limitados en número, evitando instanciar miles de objetos (spec §25).

const MAX_PACKAGES := 8
const BELT_HEIGHT := 1.3

var source: Node                 # provee (port_provide_*)
var sink: Node                   # recibe (port_receive_*)
var throughput: float = 1.5      # ítems por segundo
var uid: int = 0

var _from: Vector3
var _to: Vector3
var _length: float = 1.0
var _accum: float = 0.0
var _packages: Array = []        # [{item_id, t, mesh}]
var _travel_time: float = 1.0

func setup(src: Node, dst: Node) -> void:
	source = src
	sink = dst
	_from = _provider_pos(src)
	_to = _receiver_pos(dst)
	_length = maxf(0.5, _from.distance_to(_to))
	_travel_time = _length / (throughput * 2.0 + 2.0)
	_build_belt()

func _ready() -> void:
	EventBus.tick.connect(_on_tick)

func _provider_pos(n: Node) -> Vector3:
	if n.has_method("provider_port_position"):
		return n.provider_port_position()
	return (n as Node3D).global_position + Vector3(0, BELT_HEIGHT, 0)

func _receiver_pos(n: Node) -> Vector3:
	if n.has_method("receiver_port_position"):
		return n.receiver_port_position()
	return (n as Node3D).global_position + Vector3(0, BELT_HEIGHT, 0)

# --- Simulación de transporte ----------------------------------------------
func _effective_speed_mult() -> float:
	if GameManager.upgrades:
		return GameManager.upgrades.conveyor_speed_mult()
	return 1.0

func _on_tick(delta: float) -> void:
	if not is_instance_valid(source) or not is_instance_valid(sink):
		return
	var speed_mult := _effective_speed_mult()
	# Avanza paquetes.
	for pkg in _packages:
		if pkg.t < 1.0:
			pkg.t = minf(1.0, pkg.t + delta * speed_mult / _travel_time)
			_update_pkg_transform(pkg)
	# Entrega paquetes que llegaron al final.
	for pkg in _packages.duplicate():
		if pkg.t >= 1.0:
			var accepted: int = sink.port_receive_give(pkg.item_id, 1)
			if accepted > 0:
				_free_pkg(pkg)
	# Toma nuevos ítems del origen según el ritmo.
	_accum += delta * throughput * speed_mult
	while _accum >= 1.0 and _packages.size() < MAX_PACKAGES:
		_accum -= 1.0
		if not _try_load():
			break

func _try_load() -> bool:
	var avail: Dictionary = source.port_provide_peek()
	for item_id in avail.keys():
		if int(avail[item_id]) <= 0:
			continue
		# ¿El destino acepta este ítem?
		if sink.port_receive_can(item_id, 1) <= 0:
			continue
		if source.port_provide_take(item_id, 1) > 0:
			_spawn_pkg(item_id)
			return true
	return false

# --- Visual -----------------------------------------------------------------
func _build_belt() -> void:
	var mid := (_from + _to) * 0.5
	global_position = mid
	var dir := (_to - _from)
	dir.y = 0

	# Estructura metálica de la cinta.
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.22, 0.23, 0.25)
	frame_mat.roughness = 0.5
	frame_mat.metallic = 0.85
	var frame := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(0.8, 0.16, _length)
	frame.mesh = fbm
	frame.material_override = frame_mat
	add_child(frame)

	# Superficie de banda con textura desplazándose (shader).
	var belt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.66, 0.06, _length)
	belt.mesh = bm
	belt.position = Vector3(0, 0.11, 0)
	belt.material_override = _make_belt_material()
	add_child(belt)

	# Rieles laterales.
	for sx in [-1, 1]:
		var rail := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.07, 0.16, _length)
		rail.mesh = rbm
		rail.material_override = frame_mat
		rail.position = Vector3(sx * 0.37, 0.14, 0)
		add_child(rail)

	# Patas de soporte a lo largo del trazado.
	var legs := maxi(2, int(_length / 3.0))
	for i in range(legs + 1):
		var t := float(i) / float(legs)
		var z := lerpf(-_length * 0.5, _length * 0.5, t)
		var leg := MeshInstance3D.new()
		var lbm := BoxMesh.new()
		lbm.size = Vector3(0.12, BELT_HEIGHT, 0.12)
		leg.mesh = lbm
		leg.material_override = frame_mat
		leg.position = Vector3(0, -BELT_HEIGHT * 0.5, z)
		add_child(leg)

	# Orienta la banda hacia el destino (su eje Z local queda alineado con el trazado).
	if dir.length() > 0.01:
		look_at(_to, Vector3.UP)

func _make_belt_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float scroll_speed = 1.2;
void fragment() {
	float v = UV.y * 24.0 + TIME * scroll_speed;
	float stripe = step(0.5, fract(v));
	vec3 a = vec3(0.10, 0.10, 0.12);
	vec3 b = vec3(0.17, 0.17, 0.20);
	ALBEDO = mix(a, b, stripe);
	ROUGHNESS = 0.8;
	METALLIC = 0.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

func _spawn_pkg(item_id: String) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.4, 0.4)
	mesh.mesh = bm
	mesh.material_override = _item_material(item_id)
	add_child(mesh)
	var pkg := { "item_id": item_id, "t": 0.0, "mesh": mesh }
	_packages.append(pkg)
	_update_pkg_transform(pkg)

func _update_pkg_transform(pkg: Dictionary) -> void:
	var world := _from.lerp(_to, pkg.t) + Vector3(0, 0.35, 0)
	(pkg.mesh as MeshInstance3D).global_position = world

func _free_pkg(pkg: Dictionary) -> void:
	if is_instance_valid(pkg.mesh):
		pkg.mesh.queue_free()
	_packages.erase(pkg)

func _item_material(item_id: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match ItemDB.category(item_id):
		"metals": m.albedo_color = Color(0.7, 0.72, 0.75)
		"minerals": m.albedo_color = Color(0.5, 0.4, 0.35)
		"components": m.albedo_color = Color(0.4, 0.6, 0.8)
		"finished": m.albedo_color = Color(0.85, 0.7, 0.3)
		"energy": m.albedo_color = Color(0.9, 0.5, 0.2)
		"chemicals": m.albedo_color = Color(0.6, 0.85, 0.4)
		_: m.albedo_color = Color(0.6, 0.6, 0.6)
	m.metallic = 0.2
	m.roughness = 0.6
	return m

# --- Serialización ----------------------------------------------------------
func endpoints_uids() -> Dictionary:
	return {
		"uid": uid,
		"source_kind": _node_kind(source),
		"source_uid": _node_uid(source),
		"sink_kind": _node_kind(sink),
		"sink_uid": _node_uid(sink),
		"throughput": throughput,
	}

func _node_kind(n: Node) -> String:
	if n is Machine: return "machine"
	if n.has_meta("building_uid"): return "building"
	return "storage"

func _node_uid(n: Node) -> int:
	if n is Machine: return (n as Machine).uid
	if n.has_meta("building_uid"): return int(n.get_meta("building_uid"))
	return -1
