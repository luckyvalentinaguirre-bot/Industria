extends Node
## BankManager — deuda e intereses de la empresa.
##
## Aplica el interés diario sobre la deuda pendiente y ofrece pagos manuales.
## En la V1 no hay préstamos nuevos: el banco sólo cobra intereses de la deuda
## heredada, presionando al jugador a hacerla rentable (spec §3, §13).

var daily_interest: float = 0.0008

func _ready() -> void:
	var cfg := _load_prices()
	daily_interest = float(cfg.get("debt_daily_interest", daily_interest))
	EventBus.day_passed.connect(_on_day_passed)

func _load_prices() -> Dictionary:
	var path := "res://data/economy/prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _on_day_passed(_day: int) -> void:
	if GameState.debt <= 0.0:
		return
	var interest: float = GameState.debt * daily_interest
	if interest <= 0.0:
		return
	# El interés se suma a la deuda y se contabiliza como gasto financiero.
	GameState.debt += interest
	EventBus.transaction.emit("debt_interest", interest, false)
	EventBus.debt_changed.emit(GameState.debt)

## Pago manual de deuda (usado por la UI de finanzas y por reglas de automatización).
func pay(amount: float) -> float:
	return GameManager.economy.pay_debt(amount)
