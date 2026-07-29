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
	EventBus.money_changed.connect(func(_m): _check_long_term())
	EventBus.reputation_changed.connect(func(_r): _check_long_term())
	EventBus.company_level_changed.connect(func(_l, _n): _check_long_term())

func _on_game_started() -> void:
	_initial_debt = maxf(1.0, GameState.debt)

func _define_objectives() -> void:
	objectives = [
		{"id": "repair", "title": "Repara la máquina averiada", "done": false, "reward": 1000, "long": false},
		{"id": "produce", "title": "Fabrica tu primer producto", "done": false, "reward": 1000, "long": false},
		{"id": "sell", "title": "Realiza tu primera venta", "done": false, "reward": 1000, "long": false},
		{"id": "contract", "title": "Cumple tu primer contrato", "done": false, "reward": 1500, "long": false},
		{"id": "automate", "title": "Configura una regla de automatización", "done": false, "reward": 1500, "long": false},
		{"id": "profit", "title": "Cierra un día con ganancias", "done": false, "reward": 2000, "long": false},
		{"id": "halve_debt", "title": "Reduce la deuda a la mitad", "done": false, "reward": 5000, "long": false},
		{"id": "solvent", "title": "Salda por completo la deuda", "done": false, "reward": 10000, "long": false},
		# Metas de largo plazo (spec §12).
		{"id": "machines50", "title": "🏭 Construí 50 máquinas", "done": false, "reward": 20000, "long": true},
		{"id": "million", "title": "💰 Alcanzá $1.000.000 de capital", "done": false, "reward": 25000, "long": true},
		{"id": "units10k", "title": "⚙️ Producí 10.000 unidades", "done": false, "reward": 20000, "long": true},
		{"id": "contracts100", "title": "📦 Completá 100 contratos", "done": false, "reward": 30000, "long": true},
		{"id": "rep100", "title": "⭐ Alcanzá reputación 100", "done": false, "reward": 20000, "long": true},
		{"id": "corporation", "title": "🏢 Convertite en Corporación (nivel 5)", "done": false, "reward": 50000, "long": true},
	]

func _complete(id: String) -> void:
	for o in objectives:
		if o["id"] == id and not o["done"]:
			o["done"] = true
			var reward := int(o.get("reward", 0))
			if reward > 0 and GameManager.economy:
				GameManager.economy.earn(reward, "misc")
				EventBus.objective_reward.emit("%s: +%s" % [o["title"], Fmt.money(reward)])
			EventBus.objective_completed.emit(id, o["title"])
			EventBus.objectives_updated.emit()
			EventBus.notify.emit("Objetivo cumplido: %s (+%s)" % [o["title"], Fmt.money(reward)], "success")
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
	_check_long_term()

## Metas de largo plazo: se comprueban por métricas reales de la simulación.
func _check_long_term() -> void:
	if GameManager.machines and GameManager.machines.count() >= 50:
		_complete("machines50")
	if GameState.money >= 1000000.0:
		_complete("million")
	if _units_produced() >= 10000:
		_complete("units10k")
	if GameState.contracts_completed >= 100:
		_complete("contracts100")
	if GameState.reputation >= 100:
		_complete("rep100")
	if GameState.company_level >= 5:
		_complete("corporation")

func _units_produced() -> int:
	var total := 0
	if GameManager.production:
		for v in GameManager.production.produced_total.values():
			total += int(v)
	return total

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
