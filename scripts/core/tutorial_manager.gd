extends Node
## TutorialManager — tutorial progresivo que enseña jugando (spec Fase 3 §1).
##
## Muestra un paso a la vez; cada paso se completa con una acción REAL del juego
## (colocar máquina, conectar cinta, producir, cumplir contrato...) detectada por
## señales del EventBus. Se puede saltar. No bloquea la jugabilidad: sólo guía.
##
## Nota de estructura: progresión/onboarding → vive en scripts/core/.

const STEPS := [
	{ "id": "repair", "text": "Repará la fundición averiada: seleccionala y pulsá Reparar.", "reward": 1500 },
	{ "id": "conveyor", "text": "Conectá el almacén a la fundición con una Cinta transportadora.", "reward": 1500 },
	{ "id": "produce", "text": "Comprá mineral de hierro (Finanzas) y producí tu primer lingote.", "reward": 2000 },
	{ "id": "contract", "text": "Aceptá y completá tu primer contrato (📄 Contratos).", "reward": 2500 },
	{ "id": "second_machine", "text": "Ampliá tu fábrica: construí una segunda máquina.", "reward": 2000 },
	{ "id": "energy", "text": "Mejorá tu suministro energético (Generador o Subestación).", "reward": 3000 },
]

var _started: bool = false

func _ready() -> void:
	EventBus.machine_repaired.connect(func(_m): _try_advance("repair"))
	EventBus.machine_placed.connect(_on_machine_placed)
	EventBus.conveyor_placed.connect(func(_c): _try_advance("conveyor"))
	EventBus.item_produced.connect(_on_item_produced)
	EventBus.contract_completed.connect(func(_c): _try_advance("contract"))
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.game_started.connect(_on_started)
	EventBus.game_loaded.connect(_on_started)

func _on_started() -> void:
	_started = true
	_show_current()

func is_active() -> bool:
	return GameState.tutorial_active and GameState.tutorial_index < STEPS.size()

func _show_current() -> void:
	if is_active():
		var s: Dictionary = STEPS[GameState.tutorial_index]
		EventBus.tutorial_step_changed.emit(String(s["text"]), GameState.tutorial_index + 1, STEPS.size())
	else:
		EventBus.tutorial_finished.emit()

func skip() -> void:
	GameState.tutorial_active = false
	EventBus.tutorial_finished.emit()
	EventBus.notify.emit("Tutorial omitido. Podés consultar objetivos con 🎯.", "info")

func _current_id() -> String:
	if not is_active():
		return ""
	return String(STEPS[GameState.tutorial_index]["id"])

func _try_advance(step_id: String) -> void:
	if not _started or not is_active() or _current_id() != step_id:
		return
	var reward := int(STEPS[GameState.tutorial_index].get("reward", 0))
	if reward > 0:
		GameManager.economy.earn(reward, "misc")
		EventBus.objective_reward.emit("Tutorial: +%s" % Fmt.money(reward))
	GameState.tutorial_index += 1
	if GameState.tutorial_index >= STEPS.size():
		GameState.tutorial_active = false
		EventBus.tutorial_finished.emit()
		EventBus.notify.emit("¡Tutorial completado! Ahora manejás lo básico.", "success")
	else:
		_show_current()

# --- Detección de pasos -----------------------------------------------------
func _on_machine_placed(_m: Node) -> void:
	if _current_id() == "smelter":
		_try_advance("smelter")
	elif _current_id() == "second_machine" and GameManager.machines.count() >= 2:
		_try_advance("second_machine")

func _on_item_produced(item_id: String, _qty: int) -> void:
	if _current_id() == "produce" and (item_id == "iron_ingot" or item_id == "copper_ingot"):
		_try_advance("produce")

func _on_building_placed(b: Node) -> void:
	if _current_id() == "energy" and ("category" in b) and b.category == "energy":
		_try_advance("energy")
