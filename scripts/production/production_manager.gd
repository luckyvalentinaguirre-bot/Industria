extends Node
## ProductionManager — coordinación y estadísticas de producción.
##
## Las máquinas se autoprocesan por tick; este manager agrega métricas globales
## (unidades producidas, ritmo por minuto) para la UI y la automatización, y
## expone consultas sobre la producción total.

var produced_total: Dictionary = {}      # item_id -> total histórico
var _minute_counter: Dictionary = {}     # item_id -> producidas en el minuto
var rate_per_min: Dictionary = {}        # item_id -> últimas producidas/min

func _ready() -> void:
	EventBus.item_produced.connect(_on_item_produced)
	EventBus.minute_passed.connect(_on_minute)

func _on_item_produced(item_id: String, qty: int) -> void:
	produced_total[item_id] = int(produced_total.get(item_id, 0)) + qty
	_minute_counter[item_id] = int(_minute_counter.get(item_id, 0)) + qty

func _on_minute(_d: int, _h: int, _m: int) -> void:
	rate_per_min = _minute_counter.duplicate()
	_minute_counter.clear()

func running_machines() -> int:
	var n := 0
	for m in GameManager.machines.machines:
		if m.state == Machine.State.RUNNING:
			n += 1
	return n

func get_rate(item_id: String) -> int:
	return int(rate_per_min.get(item_id, 0))

func to_dict() -> Dictionary:
	return { "produced_total": produced_total.duplicate() }

func from_dict(data: Dictionary) -> void:
	produced_total = (data.get("produced_total", {}) as Dictionary).duplicate()
