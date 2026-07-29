extends Node
## SkillManager — experiencia y progresión de los trabajadores (spec §12).
##
## En la V1 la experiencia crece con el tiempo trabajado y mejora ligeramente la
## productividad individual. Base ampliable para especializaciones futuras.

const XP_PER_DAY := 1.0
const MAX_XP := 100.0

func _ready() -> void:
	EventBus.day_passed.connect(_on_day)

func _on_day(_day: int) -> void:
	if not GameManager.workers:
		return
	for w in GameManager.workers.workers:
		w.experience = minf(MAX_XP, w.experience + XP_PER_DAY)

## Multiplicador de productividad por experiencia (1.0 .. 1.2).
func experience_multiplier(worker: Worker) -> float:
	return 1.0 + clampf(worker.experience / MAX_XP, 0.0, 1.0) * 0.2
