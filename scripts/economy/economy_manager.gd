extends Node
## EconomyManager — dinero y deuda de la empresa (fachada central).
##
## Único punto que modifica GameState.money y GameState.debt. Cada movimiento
## emite EventBus.transaction (lo contabiliza FinanceManager) y las señales de
## cambio para la UI. Los demás sistemas (mercado, salarios, energía, contratos)
## llaman aquí en lugar de tocar el dinero directamente.

func _ready() -> void:
	# Valores iniciales desde data/economy/prices.json (si existe).
	var cfg := _load_prices()
	if cfg.has("starting_money"):
		GameState.money = float(cfg["starting_money"])
	if cfg.has("starting_debt"):
		GameState.debt = float(cfg["starting_debt"])
	call_deferred("_emit_initial")

func _emit_initial() -> void:
	EventBus.money_changed.emit(GameState.money)
	EventBus.debt_changed.emit(GameState.debt)

func _load_prices() -> Dictionary:
	var path := "res://data/economy/prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

# --- Consultas --------------------------------------------------------------

func get_money() -> float:
	return GameState.money

func get_debt() -> float:
	return GameState.debt

func can_afford(amount: float) -> bool:
	return GameState.money >= amount

# --- Movimientos ------------------------------------------------------------

## Gasta dinero si hay fondos. Devuelve true si se ejecutó.
func spend(amount: float, category: String = "misc") -> bool:
	if amount <= 0.0:
		return true
	if GameState.money < amount:
		EventBus.insufficient_funds.emit(amount)
		EventBus.notify.emit("Fondos insuficientes (faltan %s)" % Fmt.money(amount - GameState.money), "error")
		return false
	GameState.money -= amount
	EventBus.transaction.emit(category, amount, false)
	EventBus.money_changed.emit(GameState.money)
	return true

## Gasta permitiendo saldo negativo (para costos fijos ineludibles: salarios, energía).
func force_spend(amount: float, category: String = "misc") -> void:
	if amount <= 0.0:
		return
	GameState.money -= amount
	EventBus.transaction.emit(category, amount, false)
	EventBus.money_changed.emit(GameState.money)

## Ingresa dinero.
func earn(amount: float, category: String = "sales") -> void:
	if amount <= 0.0:
		return
	GameState.money += amount
	EventBus.transaction.emit(category, amount, true)
	EventBus.money_changed.emit(GameState.money)

# --- Deuda ------------------------------------------------------------------

func add_debt(amount: float) -> void:
	GameState.debt += amount
	EventBus.debt_changed.emit(GameState.debt)

## Paga deuda desde caja. Devuelve cuánto se pagó realmente.
func pay_debt(amount: float) -> float:
	amount = min(amount, GameState.debt)
	if amount <= 0.0:
		return 0.0
	if not spend(amount, "debt_payment"):
		return 0.0
	GameState.debt -= amount
	EventBus.debt_changed.emit(GameState.debt)
	if GameState.debt <= 0.0:
		EventBus.notify.emit("¡Deuda saldada! La empresa está libre de deudas.", "success")
	return amount
