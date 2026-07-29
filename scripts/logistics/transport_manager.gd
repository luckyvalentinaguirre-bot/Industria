extends Node
## TransportManager — gestión de cintas transportadoras.
##
## Crea y mantiene las cintas que conectan puertos (máquinas/almacenes). Provee
## consultas para la reconstrucción tras cargar partida.

const ConveyorScript := preload("res://scripts/logistics/conveyor.gd")
const COST := 350

var conveyors: Array = []         # Array[Conveyor]
var _next_uid: int = 1
var _container: Node3D

func set_container(node: Node3D) -> void:
	_container = node

## Conecta origen->destino con una cinta. Cobra el costo. Devuelve la cinta o null.
func create_conveyor(source: Node, sink: Node, charge: bool = true) -> Conveyor:
	if source == sink or source == null or sink == null:
		return null
	if charge and not GameManager.economy.spend(COST, "construction"):
		return null
	var c: Conveyor = ConveyorScript.new()
	c.uid = _next_uid
	_next_uid += 1
	if _container:
		_container.add_child(c)
	c.setup(source, sink)
	conveyors.append(c)
	EventBus.conveyor_placed.emit(c)
	EventBus.notify.emit("Cinta conectada", "success")
	return c

func remove_conveyor(c: Conveyor) -> void:
	conveyors.erase(c)
	if is_instance_valid(c):
		c.queue_free()

func count() -> int:
	return conveyors.size()

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var arr: Array = []
	for c in conveyors:
		arr.append(c.endpoints_uids())
	return { "conveyors": arr, "next_uid": _next_uid }

func from_dict(data: Dictionary) -> void:
	for c in conveyors.duplicate():
		remove_conveyor(c)
	_next_uid = int(data.get("next_uid", 1))
	for cd in data.get("conveyors", []):
		var src := _resolve(cd.get("source_kind", ""), int(cd.get("source_uid", -1)))
		var dst := _resolve(cd.get("sink_kind", ""), int(cd.get("sink_uid", -1)))
		if src and dst:
			var c := create_conveyor(src, dst, false)
			if c:
				c.throughput = float(cd.get("throughput", c.throughput))

func _resolve(kind: String, uid: int) -> Node:
	match kind:
		"machine":
			for m in GameManager.machines.machines:
				if m.uid == uid:
					return m
		"building":
			for b in GameManager.buildings.buildings:
				if int(b.get_meta("building_uid", -1)) == uid:
					return b
	return null
