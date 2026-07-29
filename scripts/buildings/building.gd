extends Node3D
class_name Building
## Building — estructura colocable no productiva (spec §10 energía, §9 almacén,
## §11 mantenimiento).
##
## Tipos V1 (def en data/buildings/buildings.json):
##   * generator  — produce energía (consume combustible del stock).
##   * substation — aumenta la capacidad eléctrica.
##   * small/large_storage — aumenta la capacidad del stock y sirve de puerto
##     de carga/descarga para las cintas.
##   * workshop   — mejora el mantenimiento.
##
## El modelo 3D es un placeholder por código, sustituible por el asset final.

var building_id: String = ""
var def: Dictionary = {}
var category: String = ""
var grid_origin: Vector2i = Vector2i.ZERO
var grid_size: Vector2i = Vector2i(2, 2)
var uid: int = 0

# Nodos de logística (divisor/unificador/filtro): buffer interno propio.
var buffer: Inventory = null
var is_filter: bool = false
var filter_item: String = ""

func setup(id: String, origin: Vector2i) -> void:
	building_id = id
	def = _load_def(id)
	category = String(def.get("category", ""))
	grid_origin = origin
	var s: Array = def.get("size", [2, 2])
	grid_size = Vector2i(int(s[0]), int(s[1]))
	if category == "logistics":
		buffer = Inventory.new(int(def.get("buffer", 12)))
		is_filter = bool(def.get("is_filter", false))
	set_meta("building_uid", uid)
	_build_visual()

func _load_def(id: String) -> Dictionary:
	var path := "res://data/buildings/buildings.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return (data.get("buildings", {}) as Dictionary).get(id, {})
	return {}

func display_name() -> String:
	return String(def.get("name", building_id))

# --- Puertos de cinta -------------------------------------------------------
## Almacenes → stock general de la empresa.
## Logística (divisor/unificador/filtro) → buffer interno propio, permitiendo
## que varias cintas converjan (unificar) o salgan (dividir) desde un mismo nodo.
func is_storage() -> bool:
	return category == "storage"

func is_relay() -> bool:
	return category == "logistics"

func provider_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, d)

func receiver_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, -d)

func port_provide_peek() -> Dictionary:
	if is_storage():
		return GameManager.storage.port_provide_peek()
	if is_relay():
		return buffer.provide_peek()
	return {}

func port_provide_take(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_provide_take(item_id, n)
	if is_relay():
		return buffer.remove(item_id, n)
	return 0

func port_receive_can(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_receive_can(item_id, n)
	if is_relay():
		if is_filter and filter_item != "" and item_id != filter_item:
			return 0
		return min(n, buffer.free_space())
	return 0

func port_receive_give(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_receive_give(item_id, n)
	if is_relay():
		if is_filter and filter_item != "" and item_id != filter_item:
			return 0
		# Un filtro sin item fijado se auto-configura con el primer ítem recibido.
		if is_filter and filter_item == "":
			filter_item = item_id
		return buffer.add(item_id, n)
	return 0

# --- Modelo 3D placeholder --------------------------------------------------
func _build_visual() -> void:
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var color := _category_color()
	var height := _category_height()

	var mat := _mat(color, 0.7, 0.3)
	var mat_dark := _mat(Color(0.14, 0.15, 0.17), 0.5, 0.8)
	var mat_concrete := _mat(Color(0.24, 0.24, 0.26), 0.95, 0.0)

	# Losa base común.
	_box(Vector3(w * 0.98, 0.25, d * 0.98), Vector3(0, 0.12, 0), mat_concrete)

	match category:
		"storage": _build_storage(w, d, height, mat, mat_dark)
		"energy": _build_energy(w, d, height, mat, mat_dark)
		"maintenance": _build_workshop(w, d, height, mat, mat_dark)
		"logistics": _build_relay(w, d, mat, mat_dark)
		_:
			_box(Vector3(w * 0.9, height, d * 0.9), Vector3(0, height * 0.5, 0), mat)

	# Colisión para selección (capa 2).
	var pick := StaticBody3D.new()
	pick.collision_layer = 2
	pick.collision_mask = 0
	pick.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, maxf(height, 2.0), d)
	cs.shape = box
	cs.position = Vector3(0, height * 0.5, 0)
	pick.add_child(cs)
	pick.set_meta("building", self)
	add_child(pick)

# --- Siluetas por categoría -------------------------------------------------
func _build_storage(w: float, d: float, height: float, mat: Material, mat_dark: Material) -> void:
	# Nave con silos cilíndricos encima.
	_box(Vector3(w * 0.92, height, d * 0.92), Vector3(0, height * 0.5, 0), mat)
	# Franja superior oscura.
	_box(Vector3(w * 0.94, 0.3, d * 0.94), Vector3(0, height, 0), mat_dark)
	var r: float = min(w, d) * 0.2
	for sx in [-1, 1]:
		var silo := _cyl(r, r, height * 0.7, Vector3(sx * w * 0.24, height + height * 0.35, 0), mat)
		# Tapa cónica.
		_cyl(0.02, r, height * 0.18, Vector3(sx * w * 0.24, height + height * 0.7 + height * 0.09, 0), mat_dark)
	# Puerta.
	_box(Vector3(w * 0.3, height * 0.6, 0.1), Vector3(0, height * 0.3, d * 0.46 + 0.02), mat_dark)

func _build_energy(w: float, d: float, height: float, mat: Material, mat_dark: Material) -> void:
	_box(Vector3(w * 0.9, height, d * 0.9), Vector3(0, height * 0.5, 0), mat)
	# Dos chimeneas de escape.
	for sx in [-1, 1]:
		_cyl(0.28, 0.36, height * 0.9, Vector3(sx * w * 0.28, height + height * 0.4, -d * 0.28), mat_dark)
	# Ventiladores de refrigeración al frente.
	for sx in [-1, 1]:
		var ring := _cyl(0.5, 0.5, 0.12, Vector3(sx * w * 0.22, height * 0.55, d * 0.46), mat_dark)
		ring.rotation_degrees = Vector3(90, 0, 0)
	# Rejilla emisiva (indicador de energía).
	var glow := _mat(Color(0.9, 0.8, 0.2), 0.4, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.85, 0.2)
	glow.emission_energy_multiplier = 1.2
	_box(Vector3(w * 0.5, 0.12, 0.06), Vector3(0, height * 0.2, d * 0.46 + 0.02), glow)

func _build_workshop(w: float, d: float, height: float, mat: Material, mat_dark: Material) -> void:
	_box(Vector3(w * 0.9, height, d * 0.9), Vector3(0, height * 0.5, 0), mat)
	# Tejado a dos aguas (prisma girado).
	var roof := _box(Vector3(w * 0.95, 0.5, d * 0.95), Vector3(0, height + 0.2, 0), mat_dark)
	roof.rotation_degrees = Vector3(0, 0, 12)
	# Puerta de garaje.
	var doormat := _mat(Color(0.3, 0.32, 0.35), 0.6, 0.3)
	_box(Vector3(w * 0.5, height * 0.7, 0.1), Vector3(0, height * 0.35, d * 0.46 + 0.02), doormat)

func _build_relay(w: float, d: float, mat: Material, mat_dark: Material) -> void:
	# Pequeño concentrador con "collar" luminoso indicando su función.
	_box(Vector3(w * 0.7, 0.7, d * 0.7), Vector3(0, 0.5, 0), mat_dark)
	var top := _mat(Color(0.35, 0.65, 0.8) if not is_filter else Color(0.7, 0.45, 0.75), 0.4, 0.2)
	top.emission_enabled = true
	top.emission = top.albedo_color
	top.emission_energy_multiplier = 1.0
	_box(Vector3(w * 0.85, 0.18, d * 0.85), Vector3(0, 0.95, 0), top)
	_cyl(0.18, 0.18, 0.5, Vector3(0, 1.2, 0), mat_dark)

# --- Helpers de malla -------------------------------------------------------
func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _category_color() -> Color:
	match category:
		"energy": return Color(0.8, 0.7, 0.2)
		"storage": return Color(0.45, 0.5, 0.55)
		"maintenance": return Color(0.3, 0.6, 0.6)
		"logistics":
			return Color(0.7, 0.45, 0.75) if is_filter else Color(0.35, 0.65, 0.8)
		_: return Color(0.5, 0.5, 0.5)

func _category_height() -> float:
	match category:
		"storage": return 4.5
		"energy": return 3.0
		"logistics": return 1.0
		_: return 2.5

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"building_id": building_id,
		"origin": [grid_origin.x, grid_origin.y],
		"filter_item": filter_item,
	}
