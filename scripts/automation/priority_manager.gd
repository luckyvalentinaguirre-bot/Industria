extends Node
## PriorityManager — prioridades de máquinas/líneas (spec §17).
##
## Las máquinas tienen prioridad Baja/Normal/Alta/Crítica. Ante falta de energía,
## PowerManager deslastra por prioridad. Este manager ofrece utilidades para
## fijar prioridades en bloque y apagar/encender por nivel (usado por reglas).

func set_machine_priority(m: Machine, priority: int) -> void:
	m.set_priority(priority)

## Desactiva todas las máquinas de una prioridad dada.
func disable_priority(priority: int) -> void:
	var n := 0
	for m in GameManager.machines.machines:
		if m.priority == priority and m.enabled:
			m.set_enabled(false)
			n += 1
	if n > 0:
		EventBus.notify.emit("Apagadas %d máquinas de prioridad %s" % [n, Machine.PRIORITY_NAMES[priority]], "warning")

func enable_all() -> void:
	for m in GameManager.machines.machines:
		m.set_enabled(true)

## Consumo total demandado por prioridad (para diagnósticos de UI).
func demand_by_priority() -> Dictionary:
	var d := {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
	for m in GameManager.machines.machines:
		if m.enabled and m.recipe_id != "":
			d[m.priority] += m.power_draw
	return d
