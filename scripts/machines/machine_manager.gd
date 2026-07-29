extends Node
## MachineManager — registro y ciclo de vida de las máquinas.
##
## Crea/instancia máquinas en el mundo, las registra para que otros sistemas
## (energía, mantenimiento, producción, automatización) las recorran, y las
## elimina devolviendo materiales al stock.

const MachineScript := preload("res://scripts/machines/machine.gd")

var machines: Array = []          # Array[Machine]
var _next_uid: int = 1
var _container: Node3D

func set_container(node: Node3D) -> void:
	_container = node

## Crea una máquina de tipo `machine_id` con esquina en `origin` (celdas).
func create_machine(machine_id: String, origin: Vector2i) -> Machine:
	var m: Machine = MachineScript.new()
	m.uid = _next_uid
	_next_uid += 1
	if _container:
		_container.add_child(m)
	m.setup(machine_id, origin)
	m.global_position = GameManager.grid.cell_to_world(origin) + _size_offset(m)
	machines.append(m)
	EventBus.machine_placed.emit(m)
	return m

func _size_offset(m: Machine) -> Vector3:
	# cell_to_world da el centro de la celda origin; desplazamos al centro del área.
	var cell := GameState.CELL_SIZE
	return Vector3((m.grid_size.x - 1) * cell * 0.5, 0.0, (m.grid_size.y - 1) * cell * 0.5)

func remove_machine(m: Machine) -> void:
	if not machines.has(m):
		return
	# Devuelve buffers al stock.
	for item_id in m.input_buffer.items.keys():
		GameManager.storage.deposit(item_id, m.input_buffer.count(item_id))
	for item_id in m.output_buffer.items.keys():
		GameManager.storage.deposit(item_id, m.output_buffer.count(item_id))
	GameManager.grid.free_area(m.grid_origin, m.grid_size)
	machines.erase(m)
	EventBus.machine_removed.emit(m)
	m.queue_free()

func count() -> int:
	return machines.size()

func total_power_draw() -> float:
	var p := 0.0
	for m in machines:
		if m.enabled and m.state == Machine.State.RUNNING:
			p += m.power_draw
	return p

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var arr: Array = []
	for m in machines:
		arr.append(m.to_dict())
	return { "machines": arr, "next_uid": _next_uid }

func from_dict(data: Dictionary) -> void:
	for m in machines.duplicate():
		remove_machine(m)
	_next_uid = int(data.get("next_uid", 1))
	for md in data.get("machines", []):
		var origin := Vector2i(int(md["origin"][0]), int(md["origin"][1]))
		var m := create_machine(String(md["machine_id"]), origin)
		GameManager.grid.occupy_area(origin, m.grid_size, m.uid)
		m.apply_dict(md)
