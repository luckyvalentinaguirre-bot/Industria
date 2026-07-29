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

func setup(id: String, origin: Vector2i) -> void:
	building_id = id
	def = _load_def(id)
	category = String(def.get("category", ""))
	grid_origin = origin
	var s: Array = def.get("size", [2, 2])
	grid_size = Vector2i(int(s[0]), int(s[1]))
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

# --- Puertos de cinta (sólo almacenes: dan/reciben del stock general) --------
func is_storage() -> bool:
	return category == "storage"

func provider_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, d)

func receiver_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, -d)

func port_provide_peek() -> Dictionary:
	if is_storage():
		return GameManager.storage.port_provide_peek()
	return {}

func port_provide_take(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_provide_take(item_id, n)
	return 0

func port_receive_can(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_receive_can(item_id, n)
	return 0

func port_receive_give(item_id: String, n: int) -> int:
	if is_storage():
		return GameManager.storage.port_receive_give(item_id, n)
	return 0

# --- Modelo 3D placeholder --------------------------------------------------
func _build_visual() -> void:
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var color := _category_color()
	var height := _category_height()

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w * 0.92, height, d * 0.92)
	body.mesh = bm
	body.position = Vector3(0, height * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.metallic = 0.25
	body.material_override = mat
	add_child(body)

	# Detalle según tipo.
	if category == "energy":
		var stack := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.45
		cm.height = 2.5
		stack.mesh = cm
		stack.position = Vector3(w * 0.28, height + 1.25, d * 0.28)
		stack.material_override = mat
		add_child(stack)

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

func _category_color() -> Color:
	match category:
		"energy": return Color(0.8, 0.7, 0.2)
		"storage": return Color(0.45, 0.5, 0.55)
		"maintenance": return Color(0.3, 0.6, 0.6)
		_: return Color(0.5, 0.5, 0.5)

func _category_height() -> float:
	match category:
		"storage": return 4.5
		"energy": return 3.0
		_: return 2.5

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"building_id": building_id,
		"origin": [grid_origin.x, grid_origin.y],
	}
