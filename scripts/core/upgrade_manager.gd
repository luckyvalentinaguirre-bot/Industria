extends Node
## UpgradeManager — mejoras globales de la empresa (spec §26 "mejorar la línea").
##
## Mejoras data-driven (data/upgrades/upgrades.json) que el jugador compra con
## dinero. Cada una aplica un multiplicador global que los sistemas consultan:
## velocidad de máquinas, consumo eléctrico, desgaste, velocidad de cintas y
## precio de venta. Algunas requieren una mejora previa (progresión por niveles).
##
## Nota de estructura: progresión global de la partida → vive en scripts/core/.

var defs: Dictionary = {}
var owned: Dictionary = {}          # id -> true

# Multiplicadores acumulados (se recalculan al comprar/cargar).
var _machine_speed: float = 1.0
var _power_draw: float = 1.0
var _wear: float = 1.0
var _conveyor_speed: float = 1.0
var _sell: float = 1.0
var _storage: float = 1.0

func _ready() -> void:
	defs = _load().get("upgrades", {})
	_recompute()

func _load() -> Dictionary:
	var path := "res://data/upgrades/upgrades.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

# --- Consultas de disponibilidad --------------------------------------------
func is_owned(id: String) -> bool:
	return owned.has(id)

func is_available(id: String) -> bool:
	if is_owned(id) or not defs.has(id):
		return false
	var req := String(defs[id].get("requires", ""))
	return req == "" or is_owned(req)

func cost(id: String) -> int:
	return int(defs.get(id, {}).get("cost", 0))

# --- Compra -----------------------------------------------------------------
func buy(id: String) -> bool:
	if not is_available(id):
		return false
	if not GameManager.economy.spend(cost(id), "construction"):
		return false
	owned[id] = true
	_recompute()
	EventBus.notify.emit("Mejora adquirida: %s" % String(defs[id].get("name", id)), "success")
	return true

func _recompute() -> void:
	_machine_speed = 1.0
	_power_draw = 1.0
	_wear = 1.0
	_conveyor_speed = 1.0
	_sell = 1.0
	_storage = 1.0
	for id in owned.keys():
		# Soporta 'effects' (lista, con trade-offs) o el 'effect' único legado.
		var list: Array = defs.get(id, {}).get("effects", [])
		if list.is_empty() and defs.get(id, {}).has("effect"):
			list = [defs[id]["effect"]]
		for eff in list:
			var v := float(eff.get("value", 1.0))
			match String(eff.get("type", "")):
				"machine_speed": _machine_speed *= v
				"power_draw": _power_draw *= v
				"wear": _wear *= v
				"conveyor_speed": _conveyor_speed *= v
				"sell": _sell *= v
				"storage": _storage *= v
	# Aplica la capacidad de almacenamiento recalculada.
	if GameManager.storage and GameManager.storage.has_method("refresh_capacity"):
		GameManager.storage.refresh_capacity()

# --- Multiplicadores (los consultan los sistemas) ---------------------------
func machine_speed_mult() -> float: return _machine_speed
func power_draw_mult() -> float: return _power_draw
func wear_mult() -> float: return _wear
func conveyor_speed_mult() -> float: return _conveyor_speed
func sell_mult() -> float: return _sell
func storage_mult() -> float: return _storage

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "owned": owned.duplicate() }

func from_dict(data: Dictionary) -> void:
	owned = (data.get("owned", {}) as Dictionary).duplicate()
	_recompute()
