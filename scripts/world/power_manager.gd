extends Node
## PowerManager — red eléctrica de la fábrica (spec §10, §17).
##
## Capacidad = conexión base de la red + generadores activos (queman combustible)
## + subestaciones. Consumo = máquinas alimentadas. Si el consumo potencial
## supera la capacidad, se produce SOBRECARGA y se apagan primero las líneas de
## menor prioridad (deslastre por prioridad).
##
## Nota de estructura: la energía es infraestructura del mundo; este manager
## vive en scripts/world/. La política de prioridades la comparte con
## PriorityManager (automation).

const BASELINE_CAPACITY := 80.0   # kW de la conexión a la red pública

var energy_price: float = 0.18
var capacity: float = BASELINE_CAPACITY
var consumption: float = 0.0
var overload: bool = false

var _generators: Array = []       # buildings energía con power_output
var _substations: Array = []      # buildings energía con power_capacity
var _gen_has_fuel: Dictionary = {} # uid -> bool

func _ready() -> void:
	var cfg := _load_prices()
	energy_price = float(cfg.get("energy_price_per_kwh", energy_price))
	EventBus.tick.connect(_on_tick)
	EventBus.minute_passed.connect(_on_minute)

func _load_prices() -> Dictionary:
	var path := "res://data/economy/prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func register_building(b: Building) -> void:
	if b.def.has("power_output"):
		_generators.append(b)
		_gen_has_fuel[b.uid] = true
	if b.def.has("power_capacity"):
		_substations.append(b)

func unregister_building(b: Building) -> void:
	_generators.erase(b)
	_substations.erase(b)
	_gen_has_fuel.erase(b.uid)

# --- Cálculo de capacidad y deslastre ---------------------------------------
var _accum: float = 0.0

func _on_tick(delta: float) -> void:
	# Optimización: recalcular la red ~2 veces/seg en vez de cada frame.
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	_recompute()

func _recompute() -> void:
	capacity = BASELINE_CAPACITY
	for g in _generators:
		if _gen_has_fuel.get(g.uid, false):
			capacity += float(g.def.get("power_output", 0.0))
	for s in _substations:
		capacity += float(s.def.get("power_capacity", 0.0))

	# Máquinas que demandan energía, ordenadas por prioridad (crítica primero).
	var demand: Array = []
	var total_want := 0.0
	for m in GameManager.machines.machines:
		if m.enabled and m.condition > 0.0 and m.recipe_id != "":
			demand.append(m)
			total_want += m.effective_power_draw()
		else:
			m.powered = false
	demand.sort_custom(func(a, b): return a.priority > b.priority)

	var budget := capacity
	var used := 0.0
	for m in demand:
		var draw: float = m.effective_power_draw()
		if budget >= draw:
			m.powered = true
			budget -= draw
			used += draw
		else:
			m.powered = false

	consumption = used
	var was_overload := overload
	overload = total_want > capacity + 0.001
	EventBus.power_changed.emit(consumption, capacity)
	if overload != was_overload:
		EventBus.power_overload.emit(overload)
		if overload:
			EventBus.notify.emit("¡SOBRECARGA! Faltan %d kW. Se apagan líneas de baja prioridad." % int(ceil(total_want - capacity)), "warning")

# --- Combustible y facturación ----------------------------------------------
func _on_minute(_d: int, _h: int, _m: int) -> void:
	# Generadores: consumen combustible del stock por minuto.
	for g in _generators:
		var need := int(ceil(float(g.def.get("fuel_per_min", 0.0))))
		if need <= 0:
			_gen_has_fuel[g.uid] = true
			continue
		var taken: int = GameManager.storage.withdraw("fuel", need)
		_gen_has_fuel[g.uid] = taken >= need

	# Facturación de la energía tomada de la red pública (no la de generadores).
	var gen_output := 0.0
	for g in _generators:
		if _gen_has_fuel.get(g.uid, false):
			gen_output += float(g.def.get("power_output", 0.0))
	var grid_kw: float = maxf(0.0, consumption - gen_output)
	var kwh: float = grid_kw / 60.0     # un minuto = 1/60 hora
	if kwh > 0.0:
		GameManager.economy.force_spend(kwh * energy_price, "energy")

func get_status() -> Dictionary:
	return { "capacity": capacity, "consumption": consumption, "overload": overload }
