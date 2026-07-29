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

	var mat_steel := _mat(Color(0.55, 0.57, 0.6), 0.35, 0.9)
	match category:
		"storage": _build_storage(w, d, height, mat, mat_dark, mat_steel)
		"energy":
			if def.has("power_output"):
				_build_generator(w, d, height, mat, mat_dark, mat_steel)
			else:
				_build_substation(w, d, height, mat, mat_dark, mat_steel)
		"maintenance": _build_workshop(w, d, height, mat, mat_dark, mat_steel)
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
func _build_storage(w: float, d: float, height: float, mat: Material, mat_dark: Material, steel: Material) -> void:
	# Nave con muro nervado, tejado a dos aguas y silos con tubería de carga.
	_box(Vector3(w * 0.92, height, d * 0.92), Vector3(0, height * 0.5, 0), mat)
	# Nervaduras verticales de chapa.
	var ribs := int(w / 0.8)
	for i in range(ribs + 1):
		var x := lerpf(-w * 0.45, w * 0.45, float(i) / float(ribs))
		_box(Vector3(0.08, height * 0.95, 0.06), Vector3(x, height * 0.5, d * 0.46 + 0.01), mat_dark)
	# Tejado a dos aguas.
	for sx in [-1, 1]:
		var slope := _box(Vector3(w * 0.5, 0.15, d * 0.98), Vector3(sx * w * 0.24, height + 0.35, 0), mat_dark)
		slope.rotation.z = sx * deg_to_rad(18)
	# Puerta de carga segmentada.
	var doormat := _mat(Color(0.32, 0.34, 0.37), 0.6, 0.3)
	for i in range(4):
		_box(Vector3(w * 0.34, height * 0.16, 0.08), Vector3(0, height * 0.12 + i * height * 0.17, d * 0.46 + 0.03), doormat)
	# Indicador de nivel emisivo.
	_box(Vector3(0.12, height * 0.7, 0.06), Vector3(w * 0.4, height * 0.5, d * 0.46 + 0.02), _emit(Color(0.3, 0.85, 0.5), 1.0))
	# Silos con tapa cónica, aros y tubería de carga.
	var r: float = min(w, d) * 0.19
	for sx in [-1, 1]:
		var sxp: float = sx * w * 0.26
		_cyl(r, r, height * 0.8, Vector3(sxp, height + height * 0.4, -d * 0.1), steel)
		for k in range(3):
			_cyl(r * 1.06, r * 1.06, 0.08, Vector3(sxp, height + 0.2 + k * height * 0.3, -d * 0.1), mat_dark)
		_cyl(0.02, r, height * 0.2, Vector3(sxp, height + height * 0.9, -d * 0.1), mat_dark)
		# Tubería de carga desde el caballete.
		var pipe := _cyl(0.09, 0.09, w * 0.28, Vector3(sxp * 0.5, height + height * 0.7, -d * 0.1), mat_dark)
		pipe.rotation.z = deg_to_rad(90)
	_ladder(Vector3(-w * 0.26 - r, 0.2, -d * 0.1 + r), height * 1.1, mat_dark)

func _build_generator(w: float, d: float, height: float, mat: Material, mat_dark: Material, steel: Material) -> void:
	# Grupo electrógeno: bloque motor, radiador con rejilla, escapes y depósito.
	_box(Vector3(w * 0.9, height, d * 0.85), Vector3(0, height * 0.5, 0), mat)
	_box(Vector3(w * 0.5, height * 0.4, d * 0.5), Vector3(-w * 0.1, height + 0.2, 0), mat_dark) # tapa motor
	# Radiador frontal con aletas.
	_box(Vector3(w * 0.3, height * 0.7, 0.1), Vector3(w * 0.42, height * 0.5, 0), mat_dark)
	for i in range(6):
		_box(Vector3(0.04, height * 0.6, 0.5), Vector3(w * 0.45, height * 0.5, -d * 0.25 + i * d * 0.1), mat_dark)
	# Dos chimeneas de escape con sombrerete + humo.
	for sx in [-1, 1]:
		var stkx: float = sx * w * 0.2
		_cyl(0.22, 0.28, height * 0.9, Vector3(stkx, height + height * 0.45, -d * 0.3), mat_dark)
		_cyl(0.34, 0.34, 0.1, Vector3(stkx, height + height * 0.9, -d * 0.3), mat_dark)
	add_child(_make_exhaust(Vector3(w * 0.2, height + height * 0.95, -d * 0.3)))
	# Depósito de combustible horizontal con aros.
	var tank := _cyl(0.5, 0.5, w * 0.5, Vector3(0, 0.6, d * 0.42), _mat(Color(0.7, 0.4, 0.15), 0.5, 0.4))
	tank.rotation.z = deg_to_rad(90)
	# Baliza y rejilla emisiva de energía.
	_box(Vector3(w * 0.5, 0.14, 0.06), Vector3(0, height * 0.25, d * 0.43 + 0.02), _emit(Color(1.0, 0.85, 0.2), 1.2))
	var beacon := _emit(Color(1.0, 0.6, 0.1), 2.0)
	_cyl(0.14, 0.14, 0.2, Vector3(w * 0.38, height + 0.5, 0), beacon)

func _build_substation(w: float, d: float, height: float, mat: Material, mat_dark: Material, steel: Material) -> void:
	# Subestación: transformadores con aletas, aisladores cerámicos y barras.
	for sx in [-1, 1]:
		var tx: float = sx * w * 0.22
		_box(Vector3(w * 0.32, height, d * 0.5), Vector3(tx, height * 0.5, 0), mat)
		# Aletas de refrigeración.
		for i in range(5):
			_box(Vector3(0.05, height * 0.8, d * 0.55), Vector3(tx + sx * (0.18 + i * 0.05), height * 0.5, 0), mat_dark)
		# Aisladores cerámicos (discos apilados) en la tapa.
		var cer := _mat(Color(0.8, 0.78, 0.7), 0.4, 0.0)
		for k in range(4):
			_cyl(0.14 - k * 0.01, 0.16 - k * 0.01, 0.12, Vector3(tx, height + 0.1 + k * 0.16, 0), cer)
	# Barras conductoras horizontales.
	var bar := _cyl(0.05, 0.05, w * 0.5, Vector3(0, height + 0.7, 0), steel)
	bar.rotation.z = deg_to_rad(90)
	# Cartel de peligro eléctrico.
	_box(Vector3(0.5, 0.5, 0.05), Vector3(0, 1.4, d * 0.42), _emit(Color(0.9, 0.8, 0.1), 0.8))
	# Vallado perimetral de postes.
	for i in range(6):
		var ang := TAU * i / 6.0
		_cyl(0.04, 0.04, 1.2, Vector3(cos(ang) * w * 0.42, 0.6, sin(ang) * d * 0.42), mat_dark)

func _build_workshop(w: float, d: float, height: float, mat: Material, mat_dark: Material, steel: Material) -> void:
	_box(Vector3(w * 0.9, height, d * 0.9), Vector3(0, height * 0.5, 0), mat)
	# Tejado a dos aguas.
	for sx in [-1, 1]:
		var slope := _box(Vector3(w * 0.52, 0.15, d * 0.95), Vector3(sx * w * 0.24, height + 0.4, 0), mat_dark)
		slope.rotation.z = sx * deg_to_rad(20)
	# Puerta de garaje segmentada.
	var doormat := _mat(Color(0.3, 0.32, 0.35), 0.6, 0.3)
	for i in range(4):
		_box(Vector3(w * 0.5, height * 0.16, 0.08), Vector3(0, height * 0.12 + i * height * 0.17, d * 0.46 + 0.02), doormat)
	# Ventanas laterales emisivas.
	for i in range(3):
		_box(Vector3(0.05, height * 0.35, d * 0.2), Vector3(-w * 0.46, height * 0.6, -d * 0.28 + i * d * 0.28), _emit(Color(0.5, 0.7, 0.85), 0.6))
	# Grúa pluma (jib crane): poste, brazo y gancho.
	_cyl(0.12, 0.14, height + 1.0, Vector3(w * 0.3, (height + 1.0) * 0.5, -d * 0.3), steel)
	var arm := _box(Vector3(0.12, 0.12, d * 0.5), Vector3(w * 0.3, height + 0.9, -d * 0.05), steel)
	_cyl(0.03, 0.03, 0.7, Vector3(w * 0.3, height + 0.5, d * 0.15), mat_dark)
	_box(Vector3(0.12, 0.12, 0.12), Vector3(w * 0.3, height + 0.15, d * 0.15), mat_dark) # gancho

func _build_relay(w: float, d: float, mat: Material, mat_dark: Material) -> void:
	# Concentrador con collar luminoso y muescas direccionales.
	_box(Vector3(w * 0.7, 0.7, d * 0.7), Vector3(0, 0.5, 0), mat_dark)
	var top := _emit(Color(0.35, 0.65, 0.8) if not is_filter else Color(0.7, 0.45, 0.75), 1.0)
	_box(Vector3(w * 0.85, 0.18, d * 0.85), Vector3(0, 0.95, 0), top)
	# Muescas de dirección en los cuatro lados.
	for a in range(4):
		var ang := TAU * a / 4.0
		_box(Vector3(0.3, 0.12, 0.5), Vector3(cos(ang) * w * 0.4, 0.6, sin(ang) * d * 0.4), top).rotation.y = -ang
	_cyl(0.15, 0.18, 0.6, Vector3(0, 1.25, 0), mat_dark)

# --- Helpers de detalle -----------------------------------------------------
func _emit(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.4, 0.0)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _ladder(base: Vector3, height: float, mat: Material) -> void:
	for side in [-1, 1]:
		_cyl(0.03, 0.03, height, base + Vector3(side * 0.16, height * 0.5, 0), mat)
	var rungs := int(height / 0.35)
	for i in range(rungs):
		_cyl(0.02, 0.02, 0.34, base + Vector3(0, 0.3 + i * 0.35, 0), mat).rotation.z = deg_to_rad(90)

func _make_exhaust(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 2.2
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3(0, 0.3, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.2
	dot.height = 0.4
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.3, 0.3, 0.32, 0.35)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

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
