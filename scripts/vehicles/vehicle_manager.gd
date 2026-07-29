extends Node
## VehicleManager — despacho de camiones de entrada/salida (spec §4).
##
## Al recibir una entrega de proveedor entra un camión; al completar un contrato
## sale uno. Recorren una ruta desde/ hacia el portón y luego se eliminan. Se
## limita el número simultáneo para no sobrecargar la escena (spec §25).

const VehicleScript := preload("res://scripts/vehicles/vehicle.gd")
const MAX_VEHICLES := 5

var _container: Node3D
var _active: Array = []

func _ready() -> void:
	EventBus.delivery_arrived.connect(_on_delivery)
	EventBus.contract_completed.connect(_on_contract)

func set_container(node: Node3D) -> void:
	_container = node

func _gate() -> float:
	return GameState.grid_size.x * GameState.CELL_SIZE * 0.5   # borde del recinto

func _cleanup() -> void:
	_active = _active.filter(func(v): return is_instance_valid(v))

func _spawn(route: Array, color: Color) -> void:
	_cleanup()
	if _container == null or _active.size() >= MAX_VEHICLES:
		return
	var v: Vehicle = VehicleScript.new()
	_container.add_child(v)
	v.setup(route, color)
	_active.append(v)

func _on_delivery(_item: String, _qty: int) -> void:
	# Entra desde el portón oeste, llega a la zona de carga y se marcha.
	var g := _gate()
	_spawn([
		Vector3(-g, 0, 6), Vector3(-6, 0, 6), Vector3(-6, 0, 11),
		Vector3(-14, 0, 6), Vector3(-g, 0, 6),
	], Color(0.3, 0.5, 0.85))

func _on_contract(_c: Resource) -> void:
	# Sale cargado hacia el portón este.
	var g := _gate()
	_spawn([
		Vector3(6, 0, 11), Vector3(6, 0, 6), Vector3(g, 0, 6),
	], Color(0.35, 0.7, 0.4))
