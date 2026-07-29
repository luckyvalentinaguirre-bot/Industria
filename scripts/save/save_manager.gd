extends Node
## SaveManager — guardado y carga de la partida (spec §20).
##
## Serializa el estado global y el de cada manager a un JSON en user://. El orden
## de carga respeta las dependencias: primero edificios y stock, luego máquinas,
## después cintas (que referencian a ambos), y por último el resto.

const SAVE_PATH := "user://industria_save.json"
const SAVE_VERSION := 1
const AUTOSAVE_EVERY_DAYS := 2

var _days_since_autosave: int = 0

func _ready() -> void:
	EventBus.day_passed.connect(_on_day_passed)

func _on_day_passed(_day: int) -> void:
	# Autoguardado periódico (spec §20).
	_days_since_autosave += 1
	if _days_since_autosave >= AUTOSAVE_EVERY_DAYS and GameManager.world != null:
		_days_since_autosave = 0
		save_game(true)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(silent: bool = false) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"state": GameState.to_dict(),
		"buildings": GameManager.buildings.to_dict(),
		"storage": GameManager.storage.to_dict(),
		"machines": GameManager.machines.to_dict(),
		"conveyors": GameManager.transport.to_dict(),
		"workers": GameManager.workers.to_dict(),
		"contracts": GameManager.contracts.to_dict(),
		"production": GameManager.production.to_dict(),
		"market": GameManager.market.to_dict(),
		"rules": GameManager.rules.to_dict(),
		"objectives": GameManager.objectives.to_dict(),
		"upgrades": GameManager.upgrades.to_dict(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		EventBus.notify.emit("No se pudo guardar la partida", "error")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	EventBus.game_saved.emit()
	EventBus.notify.emit("Autoguardado" if silent else "Partida guardada", "info" if silent else "success")
	return true

func load_game() -> bool:
	if not has_save():
		EventBus.notify.emit("No hay partida guardada", "warning")
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		EventBus.notify.emit("Archivo de guardado dañado", "error")
		return false

	GameState.from_dict(data.get("state", {}))
	# Orden por dependencias.
	GameManager.buildings.from_dict(data.get("buildings", {}))
	GameManager.storage.from_dict(data.get("storage", {}))
	GameManager.machines.from_dict(data.get("machines", {}))
	GameManager.transport.from_dict(data.get("conveyors", {}))
	GameManager.workers.from_dict(data.get("workers", {}))
	GameManager.contracts.from_dict(data.get("contracts", {}))
	GameManager.production.from_dict(data.get("production", {}))
	GameManager.market.from_dict(data.get("market", {}))
	GameManager.rules.from_dict(data.get("rules", {}))
	GameManager.objectives.from_dict(data.get("objectives", {}))
	GameManager.upgrades.from_dict(data.get("upgrades", {}))

	# Reemite estado a la UI.
	EventBus.money_changed.emit(GameState.money)
	EventBus.debt_changed.emit(GameState.debt)
	EventBus.reputation_changed.emit(GameState.reputation)
	EventBus.game_loaded.emit()
	EventBus.notify.emit("Partida cargada", "success")
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
