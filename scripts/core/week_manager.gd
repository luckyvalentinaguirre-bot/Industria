extends Node
## WeekManager — ciclo de gestión semanal y resumen (spec §16-§19).
##
## La semana es la unidad de gestión del juego: al cerrarse (cada 7 días) se
## pagan los salarios (WorkerManager) y se presenta un RESUMEN que cuenta lo que
## pasó — dinero, producción, ventas, contratos, gastos por categoría, personal,
## reputación y la próxima meta. Es autónomo: acumula sus cifras vía señales del
## EventBus, sin depender del orden de reseteo de otros managers.
##
## Nota de estructura: ciclo de la partida → vive en scripts/core/.

## Último resumen generado, para reabrirlo desde el menú (Economía → Informe).
var last_summary: Dictionary = {}

var _money_start: float = 0.0
var _rep_start: int = 0
var _produced: int = 0
var _produced_by_item: Dictionary = {} # item -> unidades
var _sales_income: float = 0.0
var _contracts_done: int = 0
var _contracts_failed: int = 0
var _breakdowns: int = 0
var _expense: Dictionary = {}       # categoría -> $
var _last_achievement: String = ""
var _supplied_by_item: Dictionary = {}  # item -> unidades recibidas (proxy de consumo)
var _machine_hours: Dictionary = {}     # nombre de máquina -> horas en marcha

func _ready() -> void:
	EventBus.transaction.connect(_on_transaction)
	EventBus.item_produced.connect(_on_produced)
	EventBus.delivery_arrived.connect(_on_delivery)
	EventBus.hour_passed.connect(_on_hour)
	EventBus.contract_completed.connect(func(_c): _contracts_done += 1)
	EventBus.contract_failed.connect(func(_c): _contracts_failed += 1)
	EventBus.machine_breakdown.connect(func(_m): _breakdowns += 1)
	EventBus.objective_completed.connect(func(_id, title): _last_achievement = title)
	EventBus.week_passed.connect(_on_week)
	EventBus.game_started.connect(_snapshot)
	EventBus.game_loaded.connect(_snapshot)

## Proxy de "recurso más consumido": lo que la fábrica recibe cada semana.
func _on_delivery(item_id: String, q: int) -> void:
	_supplied_by_item[item_id] = int(_supplied_by_item.get(item_id, 0)) + q

## Muestreo por hora (barato, 24/día) de qué máquinas están en marcha.
func _on_hour(_day: int, _hour: int) -> void:
	if GameManager.machines == null:
		return
	for m in GameManager.machines.machines:
		if m.state == Machine.State.RUNNING:
			var n: String = m.display_name()
			_machine_hours[n] = int(_machine_hours.get(n, 0)) + 1

func _on_produced(item_id: String, q: int) -> void:
	_produced += q
	_produced_by_item[item_id] = int(_produced_by_item.get(item_id, 0)) + q

func _snapshot() -> void:
	_money_start = GameState.money
	_rep_start = GameState.reputation
	_reset()

func _reset() -> void:
	_produced = 0
	_produced_by_item = {}
	_sales_income = 0.0
	_contracts_done = 0
	_contracts_failed = 0
	_breakdowns = 0
	_expense = {}
	_last_achievement = ""
	_supplied_by_item = {}
	_machine_hours = {}

func _on_transaction(category: String, amount: float, is_income: bool) -> void:
	if is_income:
		if category == "sales":
			_sales_income += amount
	else:
		_expense[category] = float(_expense.get(category, 0.0)) + amount

func _on_week(week: int) -> void:
	# Los salarios de WorkerManager ya se pagaron (se registró su transacción),
	# así que quedan incluidos en los gastos de esta semana.
	var money_end: float = GameState.money
	var next_goal := ""
	if GameManager.progression:
		var nr: Dictionary = GameManager.progression.next_requirement()
		if not nr.is_empty():
			next_goal = "Llegar a Nivel %d (%s)" % [int(nr["level"]), nr["name"]]
		else:
			next_goal = "Modo libre: optimizá y expandí tu complejo."
	var data := {
		"week": week,
		"money_start": _money_start,
		"money_end": money_end,
		"profit": money_end - _money_start,
		"produced": _produced,
		"sales_income": _sales_income,
		"contracts_done": _contracts_done,
		"contracts_failed": _contracts_failed,
		"expense": _expense.duplicate(),
		"staff": GameManager.workers.workers.size() if GameManager.workers else 0,
		"staff_max": GameManager.workers.max_employees() if GameManager.workers else 0,
		"salaries": GameManager.workers.weekly_salary_total() if GameManager.workers else 0.0,
		"reputation_delta": GameState.reputation - _rep_start,
		"achievement": _last_achievement,
		"next_goal": next_goal,
		"top_product": _top_product(),
		"best_employee": _best_employee(),
		"problems": _contracts_failed + _breakdowns,
		"top_expense": _top_expense(),
		"top_value_product": _top_value_product(),
		"top_supplied": _top_supplied(),
		"busiest_machine": _busiest_machine(),
	}
	last_summary = data
	EventBus.week_summary.emit(data)
	# Reinicia para la semana siguiente.
	_money_start = money_end
	_rep_start = GameState.reputation
	_reset()

## Producto más fabricado de la semana (nombre) o "" si no hubo.
func _top_product() -> String:
	var best := ""
	var best_n := 0
	for id in _produced_by_item.keys():
		if int(_produced_by_item[id]) > best_n:
			best_n = int(_produced_by_item[id])
			best = String(id)
	return ItemDB.display_name(best) if best != "" else ""

## Categoría de gasto más alta de la semana → {"name","amount"} legible.
func _top_expense() -> Dictionary:
	var labels := {
		"purchases": "Compras", "salaries": "Salarios", "energy": "Energía",
		"maintenance": "Mantenimiento", "construction": "Construcción",
		"contract_penalty": "Penalizaciones", "debt_payment": "Deuda", "misc": "Varios",
	}
	var best := ""
	var best_v := 0.0
	for cat in _expense.keys():
		if float(_expense[cat]) > best_v:
			best_v = float(_expense[cat])
			best = String(cat)
	if best == "":
		return {}
	return { "name": String(labels.get(best, best)), "amount": best_v }

## Producto de mayor valor fabricado (unidades × precio base) → proxy de rentabilidad.
func _top_value_product() -> String:
	var best := ""
	var best_v := 0.0
	for id in _produced_by_item.keys():
		var v: float = float(int(_produced_by_item[id])) * ItemDB.base_price(id)
		if v > best_v:
			best_v = v
			best = String(id)
	return ItemDB.display_name(best) if best != "" else ""

## Recurso más abastecido (proxy del más consumido por la producción).
func _top_supplied() -> String:
	var best := ""
	var best_n := 0
	for id in _supplied_by_item.keys():
		if int(_supplied_by_item[id]) > best_n:
			best_n = int(_supplied_by_item[id])
			best = String(id)
	return ItemDB.display_name(best) if best != "" else ""

## Máquina con más horas en marcha durante la semana.
func _busiest_machine() -> String:
	var best := ""
	var best_h := 0
	for n in _machine_hours.keys():
		if int(_machine_hours[n]) > best_h:
			best_h = int(_machine_hours[n])
			best = String(n)
	return best

## Empleado más capaz de la plantilla (mayor suma de skills) o "" si no hay.
func _best_employee() -> String:
	if GameManager.workers == null:
		return ""
	var best := ""
	var best_v := -1.0
	for w in GameManager.workers.workers:
		var s := 0.0
		for k in w.SKILL_KEYS:
			s += float(w.skills.get(k, 0.5))
		if s > best_v:
			best_v = s
			best = w.worker_name
	return best
