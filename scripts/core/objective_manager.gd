extends Node
## ObjectiveManager — meta y progresión de la V1 (spec §3, §26, §27).
##
## Da a la partida una meta clara: salvar la empresa. Sigue una lista ordenada de
## objetivos y detecta la victoria (saldar la deuda siendo rentable). Se apoya en
## señales del EventBus, sin acoplarse a los sistemas.
##
## Nota de estructura: progresión del juego → vive en scripts/core/.

var objectives: Array = []         # [{id, title, done}]
var won: bool = false
var _initial_debt: float = 0.0

func _ready() -> void:
	_define_objectives()
	EventBus.machine_repaired.connect(_on_repair)
	EventBus.item_produced.connect(_on_produced)
	EventBus.transaction.connect(_on_transaction)
	EventBus.contract_completed.connect(_on_contract)
	EventBus.rule_added.connect(_on_rule_added)
	EventBus.debt_changed.connect(_on_debt_changed)
	EventBus.day_passed.connect(_on_day)
	EventBus.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	_initial_debt = maxf(1.0, GameState.debt)

func _define_objectives() -> void:
	objectives = [
		{"id": "repair", "title": "Repara la máquina averiada", "done": false},
		{"id": "produce", "title": "Fabrica tu primer producto", "done": false},
		{"id": "sell", "title": "Realiza tu primera venta", "done": false},
		{"id": "contract", "title": "Cumple tu primer contrato", "done": false},
		{"id": "automate", "title": "Configura una regla de automatización", "done": false},
		{"id": "profit", "title": "Cierra un día con ganancias", "done": false},
		{"id": "halve_debt", "title": "Reduce la deuda a la mitad", "done": false},
		{"id": "solvent", "title": "Salda por completo la deuda (¡victoria!)", "done": false},
	]

func _complete(id: String) -> void:
	for o in objectives:
		if o["id"] == id and not o["done"]:
			o["done"] = true
			EventBus.objective_completed.emit(id, o["title"])
			EventBus.objectives_updated.emit()
			EventBus.notify.emit("Objetivo cumplido: %s" % o["title"], "success")
			if id == "solvent":
				_win()
			return

func completed_count() -> int:
	var n := 0
	for o in objectives:
		if o["done"]:
			n += 1
	return n

# --- Detección --------------------------------------------------------------
func _on_repair(_m: Node) -> void:
	_complete("repair")

func _on_produced(_item: String, _qty: int) -> void:
	_complete("produce")

func _on_transaction(category: String, _amount: float, is_income: bool) -> void:
	if is_income and category == "sales":
		_complete("sell")

func _on_contract(_c: Resource) -> void:
	_complete("contract")

func _on_rule_added(_r: Dictionary) -> void:
	_complete("automate")

func _on_debt_changed(debt: float) -> void:
	if _initial_debt > 1.0 and debt <= _initial_debt * 0.5:
		_complete("halve_debt")
	if debt <= 0.0:
		_complete("solvent")

func _on_day(_day: int) -> void:
	# Rentabilidad: el día anterior cerró con ganancia positiva.
	var hist: Array = GameManager.finance.daily_history
	if hist.size() > 0 and float(hist[hist.size() - 1]["profit"]) > 0.0:
		_complete("profit")

func _win() -> void:
	if won:
		return
	won = true
	EventBus.game_won.emit()
	EventBus.notify.emit("¡La empresa está saneada! Has salvado Industria.", "success")

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "objectives": objectives.duplicate(true), "won": won, "initial_debt": _initial_debt }

func from_dict(data: Dictionary) -> void:
	if data.has("objectives"):
		objectives = (data["objectives"] as Array).duplicate(true)
	won = bool(data.get("won", false))
	_initial_debt = float(data.get("initial_debt", _initial_debt))
	EventBus.objectives_updated.emit()
