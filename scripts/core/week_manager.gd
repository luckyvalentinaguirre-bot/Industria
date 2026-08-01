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
var _sales_income: float = 0.0
var _contracts_done: int = 0
var _contracts_failed: int = 0
var _expense: Dictionary = {}       # categoría -> $
var _last_achievement: String = ""

func _ready() -> void:
	EventBus.transaction.connect(_on_transaction)
	EventBus.item_produced.connect(func(_i, q): _produced += q)
	EventBus.contract_completed.connect(func(_c): _contracts_done += 1)
	EventBus.contract_failed.connect(func(_c): _contracts_failed += 1)
	EventBus.objective_completed.connect(func(_id, title): _last_achievement = title)
	EventBus.week_passed.connect(_on_week)
	EventBus.game_started.connect(_snapshot)
	EventBus.game_loaded.connect(_snapshot)

func _snapshot() -> void:
	_money_start = GameState.money
	_rep_start = GameState.reputation
	_reset()

func _reset() -> void:
	_produced = 0
	_sales_income = 0.0
	_contracts_done = 0
	_contracts_failed = 0
	_expense = {}
	_last_achievement = ""

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
	}
	last_summary = data
	EventBus.week_summary.emit(data)
	# Reinicia para la semana siguiente.
	_money_start = money_end
	_rep_start = GameState.reputation
	_reset()
