extends Node
## EventManager — eventos aleatorios que sacuden la gestión (spec §2 estabilidad).
##
## Con baja probabilidad diaria dispara un evento (positivo o negativo) para que
## la fábrica deba "responder a cambios". V1: conjunto pequeño y equilibrado.

const DAILY_CHANCE := 0.18

var _events: Array = []

func _ready() -> void:
	_build_events()
	EventBus.day_passed.connect(_on_day)

func _build_events() -> void:
	_events = [
		RandomEvent.new("subsidy", "Subsidio industrial",
			"El gobierno otorga un incentivo a la producción.",
			func(): GameManager.economy.earn(3000.0, "misc")),
		RandomEvent.new("inspection", "Inspección sorpresa",
			"Una inspección obliga a un gasto imprevisto de mantenimiento.",
			func(): GameManager.economy.force_spend(1500.0, "maintenance")),
		RandomEvent.new("breakdown", "Falla mecánica",
			"Una máquina sufre desgaste acelerado.",
			func(): _damage_random_machine()),
		RandomEvent.new("rush_order", "Pedido urgente",
			"Un cliente paga extra por un lote inmediato de placas metálicas.",
			func(): _rush_bonus()),
	]

func _on_day(_day: int) -> void:
	if _events.is_empty() or randf() > DAILY_CHANCE:
		return
	var ev: RandomEvent = _events[randi() % _events.size()]
	ev.apply.call()
	EventBus.notify.emit("Evento: %s — %s" % [ev.title, ev.description], "warning")

func _damage_random_machine() -> void:
	var ms: Array = GameManager.machines.machines
	if ms.is_empty():
		return
	var m = ms[randi() % ms.size()]
	m.set_condition(m.condition - 25.0)

func _rush_bonus() -> void:
	var sold: int = GameManager.storage.withdraw("metal_plate", 20)
	if sold > 0:
		GameManager.economy.earn(sold * ItemDB.base_price("metal_plate") * 1.6, "sales")
	else:
		GameManager.economy.earn(800.0, "misc")
