extends Node
## WorkerManager — contratación, salarios y efectos del personal (spec §12, §13).
##
## Instancia trabajadores en el mundo, paga los salarios diarios y traduce la
## plantilla en bonificaciones globales: operadores → productividad,
## ingenieros → calidad, mecánicos (+ talleres) → mantenimiento más barato.

const WorkerScript := preload("res://scripts/workers/worker.gd")

var types: Dictionary = {}
var workers: Array = []            # Array[Worker]
var _container: Node3D

func _ready() -> void:
	var cfg := _load()
	types = cfg.get("types", {})
	EventBus.day_passed.connect(_on_day)
	call_deferred("_hire_starting_staff", cfg.get("starting_staff", {}))

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
	var def: Dictionary = types[type_id]
	# Coste de contratación = medio mes de salario.
	if charge:
		var fee := float(def.get("salary", 90.0)) * 15.0
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
	workers.erase(w)
	EventBus.worker_fired.emit(w)
	w.queue_free()

func count_specialty(spec: String) -> int:
	var n := 0
	for w in workers:
		if w.specialty == spec:
			n += 1
	return n

# --- Salarios ---------------------------------------------------------------
func daily_salary_total() -> float:
	var t := 0.0
	for w in workers:
		t += w.salary
	return t

func _on_day(_day: int) -> void:
	var total := daily_salary_total()
	if total > 0.0:
		GameManager.economy.force_spend(total, "salaries")

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
		var w := hire(String(wd.get("type_id", "operator")), false)
		if w:
			w.experience = float(wd.get("experience", 0.0))
