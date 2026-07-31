extends Node
## StorageManager — stock general de la empresa (almacén central).
##
## Modelo V1: existe un único stock de empresa (una Inventory) donde aterrizan
## las compras y desde donde se venden/entregan productos. Los edificios de
## almacén colocados AUMENTAN la capacidad total; así el jugador entiende con
## claridad "cuánto tiene" (spec §13) y la capacidad limita el crecimiento.

const BASE_CAPACITY := 400

var stock: Inventory
var _storage_buildings: Array = []   # buildings que aportan capacidad

func _ready() -> void:
	stock = Inventory.new(BASE_CAPACITY)

func _recompute_capacity() -> void:
	var cap := BASE_CAPACITY
	for b in _storage_buildings:
		if is_instance_valid(b):
			cap += int(b.get_meta("capacity", 0))
	# Tecnología de la rama Capacidad multiplica el almacenamiento total.
	if GameManager.upgrades:
		cap = int(round(cap * GameManager.upgrades.storage_mult()))
	stock.capacity = cap

## Recalcula la capacidad (p.ej. tras comprar una tecnología de almacenamiento).
func refresh_capacity() -> void:
	_recompute_capacity()

func register_storage(building: Node, capacity: int) -> void:
	building.set_meta("capacity", capacity)
	_storage_buildings.append(building)
	_recompute_capacity()

func unregister_storage(building: Node) -> void:
	_storage_buildings.erase(building)
	_recompute_capacity()

# --- API de stock -----------------------------------------------------------

func count(item_id: String) -> int:
	return stock.count(item_id)

func total() -> int:
	return stock.total()

func capacity() -> int:
	return stock.capacity

func fill_ratio() -> float:
	return stock.fill_ratio()

## Ingresa ítems (compras, salida de producción). Devuelve cuánto entró.
func deposit(item_id: String, n: int) -> int:
	return stock.add(item_id, n)

## Retira ítems (ventas, entrada de producción). Devuelve cuánto salió.
func withdraw(item_id: String, n: int) -> int:
	return stock.remove(item_id, n)

func has_amount(item_id: String, n: int) -> bool:
	return stock.has_amount(item_id, n)

# --- Interfaz de puerto (para cintas) ---------------------------------------
func port_provide_peek() -> Dictionary:
	return stock.provide_peek()

func port_provide_take(item_id: String, n: int) -> int:
	return stock.remove(item_id, n)

func port_receive_can(_item_id: String, n: int) -> int:
	return min(n, stock.free_space())

func port_receive_give(item_id: String, n: int) -> int:
	return stock.add(item_id, n)

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "stock": stock.to_dict() }

func from_dict(data: Dictionary) -> void:
	if data.has("stock"):
		stock.from_dict(data["stock"])
