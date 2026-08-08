extends Node
## MaintenanceManager — desgaste, averías y reparación (spec §11).
##
## Al bajar la condición aumenta la probabilidad de avería. El jugador repara
## pagando (o con mecánicos/taller, que abaratan y aceleran). Las reglas de
## automatización podrán enviar un mecánico automáticamente (spec §16).

const REPAIR_COST_PER_POINT := 22.0    # $ por punto de condición reparado (base)
const BREAKDOWN_CHECK_INTERVAL := 5.0  # segundos de juego entre chequeos

var _accum: float = 0.0

func _ready() -> void:
	EventBus.tick.connect(_on_tick)
	EventBus.machine_breakdown.connect(_on_breakdown)

func _on_tick(delta: float) -> void:
	_accum += delta
	if _accum < BREAKDOWN_CHECK_INTERVAL:
		return
	_accum = 0.0
	for m in GameManager.machines.machines:
		if m.state == Machine.State.BROKEN or not m.enabled:
			continue
		# Probabilidad de avería crece cuando la condición baja de 50%.
		if m.condition < 50.0:
			var risk: float = (50.0 - m.condition) / 50.0 * 0.06
			if randf() < risk:
				m.set_condition(0.0)

func _on_breakdown(m: Machine) -> void:
	EventBus.notify.emit("¡Avería! %s dejó de funcionar." % m.display_name(), "error")

## Costo de reparar totalmente una máquina (mecánicos/taller lo reducen).
func repair_cost(m: Machine) -> float:
	var missing: float = 100.0 - m.condition
	var factor := 1.0
	if GameManager.workers:
		factor -= GameManager.workers.maintenance_discount()
	return missing * REPAIR_COST_PER_POINT * maxf(0.4, factor)

## Repara una máquina si hay fondos. Devuelve true si se reparó.
func repair(m: Machine) -> bool:
	if m.condition >= 100.0:
		return true
	var cost := repair_cost(m)
	if not GameManager.economy.spend(cost, "maintenance"):
		return false
	m.set_condition(100.0)
	m.state = Machine.State.IDLE
	m._update_visual_state()
	EventBus.machine_repaired.emit(m)
	EventBus.notify.emit("%s reparada (%s)" % [m.display_name(), Fmt.money(cost)], "success")
	return true
