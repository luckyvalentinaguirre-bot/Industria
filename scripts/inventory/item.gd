extends RefCounted
class_name ItemDB
## ItemDB — base de datos estática de ítems de Industria.
##
## Carga y unifica las definiciones de data/resources/resources.json y
## data/products/products.json en una única tabla id -> info. Es sólo lectura:
## los JSON son la fuente de datos configurable, aquí no hay lógica de juego.
##
## Uso: ItemDB.get_info("iron_ingot").name / .base_price / .category / .unit

const RESOURCES_PATH := "res://data/resources/resources.json"
const PRODUCTS_PATH := "res://data/products/products.json"

static var _items: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_file(RESOURCES_PATH)
	_load_file(PRODUCTS_PATH)

static func _load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ItemDB: no existe %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("ItemDB: JSON inválido en %s" % path)
		return
	for group_key in data.keys():
		if String(group_key).begins_with("_"):
			continue
		var group: Variant = data[group_key]
		if typeof(group) != TYPE_DICTIONARY:
			continue
		for item_id in group.keys():
			_items[item_id] = group[item_id]

## Devuelve el diccionario de info del ítem, o {} si no existe.
static func get_info(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _items.get(item_id, {})

static func has(item_id: String) -> bool:
	_ensure_loaded()
	return _items.has(item_id)

static func display_name(item_id: String) -> String:
	return String(get_info(item_id).get("name", item_id))

static func base_price(item_id: String) -> float:
	return float(get_info(item_id).get("base_price", 0.0))

static func category(item_id: String) -> String:
	return String(get_info(item_id).get("category", ""))

static func all_ids() -> Array:
	_ensure_loaded()
	return _items.keys()
