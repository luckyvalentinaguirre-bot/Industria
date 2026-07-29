extends Node
## BuildingManager — registro y ciclo de vida de edificios/estructuras.
##
## Paralelo a MachineManager pero para estructuras no productivas (energía,
## almacenamiento, mantenimiento). Al colocar/eliminar, registra sus efectos en
## los sistemas correspondientes (capacidad eléctrica, capacidad de stock...).

const BuildingScript := preload("res://scripts/buildings/building.gd")

var buildings: Array = []
var _next_uid: int = 1
var _container: Node3D

func set_container(node: Node3D) -> void:
	_container = node

func create_building(building_id: String, origin: Vector2i) -> Building:
	var b: Building = BuildingScript.new()
	b.uid = _next_uid
	_next_uid += 1
	if _container:
		_container.add_child(b)
	b.setup(building_id, origin)
	b.global_position = GameManager.grid.cell_to_world(origin) + _size_offset(b)
	buildings.append(b)
	_register_effects(b)
	EventBus.building_placed.emit(b)
	return b

func _size_offset(b: Building) -> Vector3:
	var cell := GameState.CELL_SIZE
	return Vector3((b.grid_size.x - 1) * cell * 0.5, 0.0, (b.grid_size.y - 1) * cell * 0.5)

func _register_effects(b: Building) -> void:
	match b.category:
		"storage":
			GameManager.storage.register_storage(b, int(b.def.get("capacity", 0)))
		"energy":
			GameManager.power.register_building(b)
		"maintenance":
			pass  # el descuento se calcula por conteo en WorkerManager/Maintenance

func _unregister_effects(b: Building) -> void:
	match b.category:
		"storage":
			GameManager.storage.unregister_storage(b)
		"energy":
			GameManager.power.unregister_building(b)

func remove_building(b: Building) -> void:
	if not buildings.has(b):
		return
	_unregister_effects(b)
	GameManager.grid.free_area(b.grid_origin, b.grid_size)
	buildings.erase(b)
	EventBus.building_removed.emit(b)
	b.queue_free()

func count_category(cat: String) -> int:
	var n := 0
	for b in buildings:
		if b.category == cat:
			n += 1
	return n

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var arr: Array = []
	for b in buildings:
		arr.append(b.to_dict())
	return { "buildings": arr, "next_uid": _next_uid }

func from_dict(data: Dictionary) -> void:
	for b in buildings.duplicate():
		remove_building(b)
	_next_uid = int(data.get("next_uid", 1))
	for bd in data.get("buildings", []):
		var origin := Vector2i(int(bd["origin"][0]), int(bd["origin"][1]))
		var b := create_building(String(bd["building_id"]), origin)
		GameManager.grid.occupy_area(origin, b.grid_size, b.uid)
