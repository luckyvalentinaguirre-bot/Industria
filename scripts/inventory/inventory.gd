extends RefCounted
class_name Inventory
## Inventory — contenedor de ítems (id -> cantidad) con capacidad opcional.
##
## Estructura de datos reutilizable por almacenes, buffers de máquina y el stock
## general de la empresa. Expone la interfaz de "puerto" que usan las cintas:
## provide_* (dar ítems) y receive_* (aceptar ítems).

signal changed()

var items: Dictionary = {}      # item_id -> int
var capacity: int = 0           # 0 = ilimitado

func _init(cap: int = 0) -> void:
	capacity = cap

# --- Consultas --------------------------------------------------------------

func count(item_id: String) -> int:
	return int(items.get(item_id, 0))

func total() -> int:
	var t := 0
	for v in items.values():
		t += int(v)
	return t

func is_empty() -> bool:
	return total() == 0

func free_space() -> int:
	if capacity <= 0:
		return 1 << 30
	return max(0, capacity - total())

func fill_ratio() -> float:
	if capacity <= 0:
		return 0.0
	return float(total()) / float(capacity)

func has_amount(item_id: String, n: int) -> bool:
	return count(item_id) >= n

## ¿Contiene todos los ítems de un diccionario {id: cantidad}?
func has_all(needed: Dictionary) -> bool:
	for id in needed.keys():
		if count(id) < int(needed[id]):
			return false
	return true

# --- Modificación -----------------------------------------------------------

## Añade hasta `n` respetando capacidad. Devuelve cuánto entró realmente.
func add(item_id: String, n: int) -> int:
	if n <= 0:
		return 0
	var space := free_space()
	var added: int = min(n, space)
	if added <= 0:
		return 0
	items[item_id] = count(item_id) + added
	changed.emit()
	return added

## Quita hasta `n`. Devuelve cuánto salió realmente.
func remove(item_id: String, n: int) -> int:
	if n <= 0:
		return 0
	var have := count(item_id)
	var taken: int = min(n, have)
	if taken <= 0:
		return 0
	if taken >= have:
		items.erase(item_id)
	else:
		items[item_id] = have - taken
	changed.emit()
	return taken

## Consume un conjunto {id: cantidad} sólo si están todos disponibles.
func consume_all(needed: Dictionary) -> bool:
	if not has_all(needed):
		return false
	for id in needed.keys():
		remove(id, int(needed[id]))
	return true

func clear() -> void:
	items.clear()
	changed.emit()

# --- Interfaz de puerto (para cintas / logística) ---------------------------

## Ítems disponibles para entregar (todo el contenido).
func provide_peek() -> Dictionary:
	return items.duplicate()

func provide_take(item_id: String, n: int) -> int:
	return remove(item_id, n)

func receive_can(item_id: String, n: int) -> int:
	return min(n, free_space())

func receive_give(item_id: String, n: int) -> int:
	return add(item_id, n)

# --- Serialización ----------------------------------------------------------

func to_dict() -> Dictionary:
	return { "items": items.duplicate(), "capacity": capacity }

func from_dict(data: Dictionary) -> void:
	capacity = int(data.get("capacity", capacity))
	items.clear()
	var stored: Variant = data.get("items", {})
	if stored is Dictionary:
		for k in stored.keys():
			items[k] = int(stored[k])
	changed.emit()
