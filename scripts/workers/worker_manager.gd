extends Node
## WorkerManager — contratación, salarios y efectos del personal (spec §12, §13).
##
## Instancia trabajadores en el mundo, paga los salarios diarios y traduce la
## plantilla en bonificaciones globales: operadores → productividad,
## ingenieros → calidad, mecánicos (+ talleres) → mantenimiento más barato.

const WorkerScript := preload("res://scripts/workers/worker.gd")

## Máximo de empleados por nivel de empresa (spec §9/§13). Índice = nivel-1.
## El nivel de la fábrica representa su capacidad de gestión de personal.
const MAX_BY_LEVEL := [1, 3, 6, 10, 16]

## Mercado laboral: candidatos disponibles para contratar (spec §4/§12). Se
## renuevan cada semana, así que no podés esperar eternamente al "perfecto".
const CANDIDATE_COUNT := 5
const FIRST_NAMES := ["Carlos", "Laura", "Diego", "Marta", "Julián", "Sofía",
	"Andrés", "Elena", "Pablo", "Nadia", "Ramiro", "Cecilia", "Iván", "Rocío",
	"Marco", "Valeria", "Tomás", "Bruno", "Camila", "Lucía"]
## Rasgos/características (spec §6): deltas de skill + prima de salario.
const TRAITS := [
	{ "name": "Veterano", "d": { "production": 0.15, "speed": 0.15, "maintenance": 0.1 }, "sal": 250 },
	{ "name": "Aprendiz", "d": { "production": -0.2, "speed": -0.15, "quality": -0.15 }, "sal": -140 },
	{ "name": "Rápido", "d": { "speed": 0.3, "quality": -0.1 }, "sal": 80 },
	{ "name": "Perfeccionista", "d": { "quality": 0.35, "speed": -0.15 }, "sal": 120 },
	{ "name": "Manitas", "d": { "maintenance": 0.35 }, "sal": 90 },
	{ "name": "Logístico", "d": { "logistics": 0.35 }, "sal": 70 },
	{ "name": "Experto en máquinas pesadas", "d": { "production": 0.25 }, "sal": 150 },
	{ "name": "Polivalente", "d": {}, "sal": 40 },
]
const ROLE_PRIMARY := {
	"operator": "production", "mechanic": "maintenance",
	"manager": "logistics", "engineer": "quality",
}

var types: Dictionary = {}
var workers: Array = []            # Array[Worker]
var candidates: Array = []         # Array[Dictionary] — mercado laboral
var _container: Node3D

func _ready() -> void:
	var cfg := _load()
	types = cfg.get("types", {})
	EventBus.week_passed.connect(_on_week)
	call_deferred("_hire_starting_staff", cfg.get("starting_staff", {}))
	call_deferred("refresh_candidates")

## Máximo de empleados según el nivel actual de la empresa.
func max_employees() -> int:
	var idx: int = clampi(GameState.company_level - 1, 0, MAX_BY_LEVEL.size() - 1)
	return MAX_BY_LEVEL[idx]

func at_capacity() -> bool:
	return workers.size() >= max_employees()

func set_container(node: Node3D) -> void:
	_container = node

func _load() -> Dictionary:
	var path := "res://data/workers/workers.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _hire_starting_staff(staff: Dictionary) -> void:
	for type_id in staff.keys():
		for i in range(int(staff[type_id])):
			hire(String(type_id), false)

# --- Contratación -----------------------------------------------------------
func hire(type_id: String, charge: bool = true) -> Worker:
	if not types.has(type_id):
		return null
	# Límite de empleados por nivel: subir de nivel amplía la plantilla (spec §13).
	if charge and at_capacity():
		EventBus.notify.emit("Límite de empleados (%d/%d). Subí el nivel de tu fábrica para contratar más." % [workers.size(), max_employees()], "warning")
		return null
	var def: Dictionary = types[type_id]
	# Coste de contratación = media semana de salario (el gasto real es el sueldo).
	if charge:
		var fee := float(def.get("salary", 400.0)) * 0.5
		if not GameManager.economy.spend(fee, "salaries"):
			return null
	var w: Worker = WorkerScript.new()
	if _container:
		_container.add_child(w)
	w.setup(type_id, def)
	w.global_position = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	workers.append(w)
	EventBus.worker_hired.emit(w)
	if charge:
		EventBus.notify.emit("Contratado: %s" % w.worker_name, "info")
	return w

# --- Mercado laboral (candidatos) -------------------------------------------
## Renueva el mercado: conserva un par de candidatos y trae caras nuevas.
func refresh_candidates() -> void:
	var keep: Array = []
	if candidates.size() >= 2:
		keep = [candidates[0], candidates[1]]
	candidates = keep
	while candidates.size() < CANDIDATE_COUNT:
		candidates.append(_generate_candidate())
	EventBus.candidates_changed.emit()

func _generate_candidate() -> Dictionary:
	var role_keys: Array = types.keys() if not types.is_empty() else ["operator"]
	var type_id: String = String(role_keys[randi() % role_keys.size()])
	var spec: String = String(types.get(type_id, {}).get("specialty", "production"))
	var primary: String = String(ROLE_PRIMARY.get(type_id, "production"))
	var skills: Dictionary = {}
	for k in Worker.SKILL_KEYS:
		skills[k] = randf_range(0.25, 0.72)
	skills[primary] = clampf(skills[primary] + randf_range(0.2, 0.35), 0.2, 1.0)
	var trait_name := ""
	var sal_bonus := 0.0
	if randf() < 0.55:
		var t: Dictionary = TRAITS[randi() % TRAITS.size()]
		trait_name = String(t["name"])
		sal_bonus = float(t["sal"])
		if trait_name == "Polivalente":
			for k in Worker.SKILL_KEYS:
				skills[k] = clampf(lerpf(float(skills[k]), 0.62, 0.7), 0.2, 1.0)
		else:
			for k in (t["d"] as Dictionary).keys():
				skills[k] = clampf(float(skills[k]) + float(t["d"][k]), 0.1, 1.0)
	var skill_sum := 0.0
	for k in Worker.SKILL_KEYS:
		skill_sum += float(skills[k])
	var salary: float = round((240.0 + skill_sum * 105.0 + sal_bonus) / 10.0) * 10.0
	salary = maxf(300.0, salary)
	return {
		"name": FIRST_NAMES[randi() % FIRST_NAMES.size()],
		"type_id": type_id, "specialty": spec, "skills": skills,
		"trait": trait_name, "salary": salary,
	}

## Contrata a un candidato del mercado (respeta cupo y cobra la contratación).
func hire_candidate(index: int, charge: bool = true) -> Worker:
	if index < 0 or index >= candidates.size():
		return null
	if charge and at_capacity():
		EventBus.notify.emit("Límite de empleados (%d/%d). Subí el nivel de tu fábrica." % [workers.size(), max_employees()], "warning")
		return null
	var cand: Dictionary = candidates[index]
	if charge:
		var fee := float(cand.get("salary", 400.0)) * 0.5
		if not GameManager.economy.spend(fee, "salaries"):
			return null
	var w: Worker = WorkerScript.new()
	if _container:
		_container.add_child(w)
	w.setup(String(cand.get("type_id", "operator")), cand)
	w.global_position = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	workers.append(w)
	candidates.remove_at(index)
	EventBus.worker_hired.emit(w)
	EventBus.candidates_changed.emit()
	if charge:
		EventBus.notify.emit("Contratado: %s (%s)" % [w.worker_name, w.trait_name if w.trait_name != "" else String(types.get(w.type_id, {}).get("name", w.type_id))], "success")
	return w

# --- Asignación de trabajadores a máquinas (spec §7/§8) ---------------------
func _machine(uid: int) -> Machine:
	if GameManager.machines == null:
		return null
	for m in GameManager.machines.machines:
		if m.uid == uid:
			return m
	return null

func worker_for_machine(uid: int) -> Worker:
	for w in workers:
		if w.assigned_uid == uid:
			return w
	return null

func unassigned_workers() -> Array:
	var out: Array = []
	for w in workers:
		if w.assigned_uid == 0:
			out.append(w)
	return out

## Asigna un trabajador a una máquina (uid=0 = liberarlo). Asignar = poner a la
## máquina en producción continua y aplicar las skills del trabajador.
func assign(w: Worker, machine_uid: int) -> void:
	if w == null or not workers.has(w):
		return
	if w.assigned_uid == machine_uid:
		return
	# Liberar la máquina anterior.
	if w.assigned_uid != 0:
		var old := _machine(w.assigned_uid)
		if old:
			old.set_staffed(false)
	if machine_uid != 0:
		# Si otra persona atendía esa máquina, la desplaza al pool.
		var prev := worker_for_machine(machine_uid)
		if prev and prev != w:
			prev.assigned_uid = 0
		w.assigned_uid = machine_uid
		var m := _machine(machine_uid)
		if m:
			m.set_staffed(true)
	else:
		w.assigned_uid = 0
	EventBus.staff_updated.emit()

## Trabajadores decorativos (sin salario) que dan vida al patio, optimizados.
func spawn_ambient(n: int) -> void:
	if _container == null:
		return
	var roles := ["operator", "mechanic", "engineer", "manager"]
	for i in range(n):
		var type_id: String = roles[i % roles.size()]
		if not types.has(type_id):
			continue
		var w: Worker = WorkerScript.new()
		_container.add_child(w)
		w.setup(type_id, types[type_id])
		w.global_position = Vector3(randf_range(-16, 16), 0, randf_range(-10, 24))
		# No se añade a `workers`: es ambiental, no cuenta para salarios ni gestión.

func fire(w: Worker) -> void:
	if not workers.has(w):
		return
	# Libera la máquina que atendía (deja de producir de forma continua).
	if w.assigned_uid != 0:
		var m := _machine(w.assigned_uid)
		if m:
			m.set_staffed(false)
	workers.erase(w)
	EventBus.worker_fired.emit(w)
	w.queue_free()

func count_specialty(spec: String) -> int:
	var n := 0
	for w in workers:
		if w.specialty == spec:
			n += 1
	return n

# --- Trabajadores disponibles para atender máquinas -------------------------
func staffed_count() -> int:
	var n := 0
	for w in workers:
		if w.assigned_uid != 0:
			n += 1
	return n

## Trabajadores SIN ASIGNAR, libres para poner en una máquina (spec §9).
func operators_free() -> int:
	return unassigned_workers().size()

# --- Salarios (semanales, spec §10/§15) -------------------------------------
func weekly_salary_total() -> float:
	var t := 0.0
	for w in workers:
		t += w.salary
	return t

## Compatibilidad: algunos paneles piden el total; ahora es semanal.
func daily_salary_total() -> float:
	return weekly_salary_total()

func _on_week(_week: int) -> void:
	var total := weekly_salary_total()
	if total > 0.0:
		GameManager.economy.force_spend(total, "salaries")
		EventBus.notify.emit("💸 Salarios semanales: %s (%d empleados)" % [Fmt.money(total), workers.size()], "info")
	# El mercado laboral se renueva cada semana (spec §12).
	refresh_candidates()

# --- Bonificaciones globales ------------------------------------------------
func operator_bonus() -> float:
	# Cada operador aporta productividad; rendimiento decreciente.
	var ops := count_specialty("production")
	return clampf(ops * 0.06, 0.0, 0.35)

func quality_bonus() -> float:
	var eng := count_specialty("quality")
	return clampf(eng * 0.03, 0.0, 0.12)

func maintenance_discount() -> float:
	var mech := count_specialty("maintenance")
	var workshops: int = GameManager.buildings.count_category("maintenance") if GameManager.buildings else 0
	return clampf(mech * 0.08 + workshops * 0.1, 0.0, 0.5)

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var arr: Array = []
	for w in workers:
		arr.append(w.to_dict())
	return { "workers": arr }

func from_dict(data: Dictionary) -> void:
	for w in workers.duplicate():
		fire(w)
	for wd in data.get("workers", []):
		var w: Worker = WorkerScript.new()
		if _container:
			_container.add_child(w)
		w.setup(String(wd.get("type_id", "operator")), wd)   # setup restaura skills/trait/salary/exp
		w.assigned_uid = int(wd.get("assigned_uid", 0))
		w.global_position = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		workers.append(w)
		if w.assigned_uid != 0:
			var m := _machine(w.assigned_uid)
			if m:
				m.set_staffed(true)
		EventBus.worker_hired.emit(w)
	refresh_candidates()
