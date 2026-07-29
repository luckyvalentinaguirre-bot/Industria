extends Node
## FinanceManager — libro contable de la empresa.
##
## Registra cada movimiento por categoría (ingresos/gastos) para que el jugador
## entienda claramente en qué gana y en qué gasta (spec §13, §19 Finanzas).
## No mueve dinero: sólo contabiliza lo que EconomyManager ejecuta.

const CATEGORIES := ["sales", "purchases", "salaries", "energy", "maintenance",
	"construction", "debt_interest", "debt_payment", "contract_penalty", "misc"]

# Totales acumulados de toda la partida.
var totals_income: Dictionary = {}
var totals_expense: Dictionary = {}
# Acumulados del día en curso (se archivan al pasar el día).
var today_income: Dictionary = {}
var today_expense: Dictionary = {}
# Historial de resúmenes diarios [{day, income, expense, profit}].
var daily_history: Array = []

func _ready() -> void:
	_reset_day()
	for c in CATEGORIES:
		totals_income[c] = 0.0
		totals_expense[c] = 0.0
	EventBus.transaction.connect(_on_transaction)
	EventBus.day_passed.connect(_on_day_passed)

func _reset_day() -> void:
	today_income = {}
	today_expense = {}
	for c in CATEGORIES:
		today_income[c] = 0.0
		today_expense[c] = 0.0

func _on_transaction(category: String, amount: float, is_income: bool) -> void:
	if not CATEGORIES.has(category):
		category = "misc"
	if is_income:
		today_income[category] += amount
		totals_income[category] += amount
	else:
		today_expense[category] += amount
		totals_expense[category] += amount

func _on_day_passed(day: int) -> void:
	var inc := _sum(today_income)
	var exp := _sum(today_expense)
	daily_history.append({
		"day": day - 1,
		"income": inc,
		"expense": exp,
		"profit": inc - exp,
	})
	if daily_history.size() > 60:
		daily_history.pop_front()
	_reset_day()

func _sum(d: Dictionary) -> float:
	var t := 0.0
	for v in d.values():
		t += float(v)
	return t

func today_profit() -> float:
	return _sum(today_income) - _sum(today_expense)

func total_income() -> float:
	return _sum(totals_income)

func total_expense() -> float:
	return _sum(totals_expense)

func get_summary() -> Dictionary:
	return {
		"today_income": today_income.duplicate(),
		"today_expense": today_expense.duplicate(),
		"today_profit": today_profit(),
		"total_income": total_income(),
		"total_expense": total_expense(),
		"history": daily_history,
	}
