extends RefCounted
class_name ProductionLine
## ProductionLine — agrupación lógica de máquinas encadenadas.
##
## Utilidad opcional para tratar un conjunto de máquinas como una línea con
## prioridad común (spec §17). En la V1 es una estructura ligera que la
## automatización/energía pueden usar para apagar líneas enteras por prioridad.

var name: String = "Línea"
var machines: Array = []          # Array[Machine]
var priority: int = 1

func add_machine(m: Machine) -> void:
	if not machines.has(m):
		machines.append(m)

func remove_machine(m: Machine) -> void:
	machines.erase(m)

func set_priority(p: int) -> void:
	priority = clampi(p, 0, 3)
	for m in machines:
		if is_instance_valid(m):
			m.set_priority(p)

func set_enabled(v: bool) -> void:
	for m in machines:
		if is_instance_valid(m):
			m.set_enabled(v)

func is_running() -> bool:
	for m in machines:
		if is_instance_valid(m) and m.state == Machine.State.RUNNING:
			return true
	return false
