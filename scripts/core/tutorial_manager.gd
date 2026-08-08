extends Node
## TutorialManager — tutorial progresivo que enseña jugando (spec Fase 3 §1).
##
## Muestra un paso a la vez; cada paso se completa con una acción REAL del juego
## (colocar máquina, conectar cinta, producir, cumplir contrato...) detectada por
## señales del EventBus. Se puede saltar. No bloquea la jugabilidad: sólo guía.
##
## Nota de estructura: progresión/onboarding → vive en scripts/core/.

const STEPS := [
	{ "id": "workbench", "text": "Abrí ☰ MENÚ → 🏭 Fábrica y construí tu Banco de trabajo (tu primer puesto).", "reward": 500 },
	{ "id": "craft", "text": "Comprá chatarra en 💰 Economía, seleccioná el banco y pulsá ▶ Producir un lote: VOS ponés a trabajar la máquina.", "reward": 800 },
	{ "id": "sell", "text": "Vendé tus herramientas en 💰 Economía → Vender para conseguir tus primeros ingresos.", "reward": 800 },
]

var _started: bool = false

func _ready() -> void:
	EventBus.machine_placed.connect(_on_machine_placed)
	EventBus.item_produced.connect(_on_item_produced)
	EventBus.transaction.connect(_on_transaction)
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
func _on_machine_placed(m: Node) -> void:
	if _current_id() == "workbench" and ("machine_id" in m) and m.machine_id == "workbench":
		_try_advance("workbench")

func _on_item_produced(item_id: String, _qty: int) -> void:
	if _current_id() == "craft" and item_id == "hand_tool":
		_try_advance("craft")

func _on_transaction(category: String, _amount: float, is_income: bool) -> void:
	if _current_id() == "sell" and is_income and category == "sales":
		_try_advance("sell")
