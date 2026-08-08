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
		# Sólo gana experiencia si está trabajando (asignado a una máquina).
		if w.assigned_uid == 0:
			continue
		var before: float = w.experience
		w.experience = minf(MAX_XP, w.experience + XP_PER_DAY)
		# Al cruzar cada 25 de experiencia mejora un poco su MEJOR skill (mantiene
		# su identidad: no todos terminan perfectos, spec §10).
		if int(w.experience / 25.0) > int(before / 25.0):
			_level_up_best_skill(w)

func _level_up_best_skill(w: Worker) -> void:
	var best := ""
	var best_v := -1.0
	for k in Worker.SKILL_KEYS:
		var v := float(w.skills.get(k, 0.5))
		if v > best_v:
			best_v = v
			best = k
	if best != "":
		w.skills[best] = clampf(best_v + 0.06, 0.2, 1.0)
		EventBus.notify.emit("%s mejoró su habilidad (%s) con la experiencia." % [w.worker_name, best], "info")

## Multiplicador de productividad por experiencia (1.0 .. 1.2).
func experience_multiplier(worker: Worker) -> float:
	return 1.0 + clampf(worker.experience / MAX_XP, 0.0, 1.0) * 0.2
