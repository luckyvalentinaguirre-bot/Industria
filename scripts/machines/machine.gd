extends Node3D
class_name Machine
## Machine — máquina industrial funcional (objeto 3D + lógica) (spec §7).
##
## Cada máquina: entrada y salida de materiales (buffers), consumo eléctrico,
## receta, producción por ciclo, estado, durabilidad/mantenimiento, calidad y
## prioridad. El modelo 3D es un placeholder generado por código, preparado
## para sustituirse por el asset definitivo sin tocar la lógica.

enum State { RUNNING, NO_MATERIALS, NO_POWER, BLOCKED, MAINTENANCE, BROKEN, DISABLED, IDLE }

const STATE_NAMES := {
	State.RUNNING: "Funcionando",
	State.NO_MATERIALS: "Sin materiales",
	State.NO_POWER: "Sin energía",
	State.BLOCKED: "Bloqueada",
	State.MAINTENANCE: "En mantenimiento",
	State.BROKEN: "Averiada",
	State.DISABLED: "Desactivada",
	State.IDLE: "Sin receta",
}
const PRIORITY_NAMES := ["Baja", "Normal", "Alta", "Crítica"]

const BUFFER_CAPACITY := 24
const WEAR_PER_CYCLE := 0.6      # % de condición perdida por ciclo producido
const MAX_LEVEL := 3

# --- Identidad / colocación -------------------------------------------------
var machine_id: String = ""
var def: Dictionary = {}
var grid_origin: Vector2i = Vector2i.ZERO
var grid_size: Vector2i = Vector2i(2, 2)
var uid: int = 0

# --- Configuración ----------------------------------------------------------
var recipe_id: String = ""
var enabled: bool = true
var priority: int = 1            # 0 Baja .. 3 Crítica
var power_draw: float = 0.0
var base_speed: float = 1.0
var level: int = 1               # nivel de mejora (I..III)

# --- Estado dinámico --------------------------------------------------------
var state: int = State.IDLE
var progress: float = 0.0
var condition: float = 100.0     # 100 -> 0
var quality: float = 1.0
var powered: bool = true         # lo fija PowerManager
var operator_bonus: float = 0.0  # lo fija WorkerManager

var input_buffer: Inventory
var output_buffer: Inventory

## Máquinas manuales (banco de trabajo): tiran sus insumos del almacén central y
## depositan su producción allí, sin necesidad de cintas. Permite la ETAPA MANUAL
## del inicio (spec §4) reutilizando el sistema de producción existente.
var auto_supply: bool = false

# --- Visual (capa de modelo separada de la lógica, spec §2/§31) -------------
const MachineModelScript := preload("res://scripts/machines/machine_model.gd")
var _model: MachineModel

func setup(id: String, origin: Vector2i) -> void:
	machine_id = id
	def = GameManager.recipes.get_machine_def(id)
	grid_origin = origin
	var s: Array = def.get("size", [2, 2])
	grid_size = Vector2i(int(s[0]), int(s[1]))
	power_draw = float(def.get("power", 0.0))
	base_speed = float(def.get("base_speed", 1.0))
	auto_supply = bool(def.get("auto_supply", false))
	input_buffer = Inventory.new(BUFFER_CAPACITY)
	output_buffer = Inventory.new(BUFFER_CAPACITY)
	# Receta por defecto: la primera disponible.
	var rs: Array = def.get("recipes", [])
	if not rs.is_empty():
		set_recipe(String(rs[0]))
	_build_visual()

func _ready() -> void:
	EventBus.tick.connect(_on_tick)

# --- Receta -----------------------------------------------------------------
func set_recipe(id: String) -> void:
	recipe_id = id
	progress = 0.0
	# Reajusta el filtro de entrada; devuelve al stock lo que ya no sirve.
	if input_buffer:
		var relevant := current_inputs()
		for item_id in input_buffer.items.keys().duplicate():
			if not relevant.has(item_id):
				var n: int = input_buffer.count(item_id)
				GameManager.storage.deposit(item_id, n)
				input_buffer.remove(item_id, n)
	EventBus.recipe_changed.emit(self)

func current_inputs() -> Dictionary:
	return GameManager.recipes.recipe_inputs(recipe_id)

func current_outputs() -> Dictionary:
	return GameManager.recipes.recipe_outputs(recipe_id)

func cycle_time() -> float:
	return maxf(0.5, GameManager.recipes.recipe_time(recipe_id))

# --- Simulación -------------------------------------------------------------
func _on_tick(delta: float) -> void:
	var new_state := _compute_and_progress(delta)
	if new_state != state:
		state = new_state
		_update_visual_state()
		EventBus.machine_state_changed.emit(self)

func _compute_and_progress(delta: float) -> int:
	if not enabled:
		return State.DISABLED
	if condition <= 0.0:
		return State.BROKEN
	if recipe_id == "":
		return State.IDLE
	if not powered:
		progress = 0.0
		return State.NO_POWER

	var inputs := current_inputs()
	var outputs := current_outputs()

	# Banco de trabajo: se auto-abastece del almacén y descarga allí su producción.
	if auto_supply:
		_auto_supply_tick(inputs)

	if not input_buffer.has_all(inputs):
		return State.NO_MATERIALS
	if not _output_has_room(outputs):
		return State.BLOCKED

	# Producción activa.
	var speed := _effective_speed()
	progress += delta * speed
	while progress >= cycle_time():
		progress -= cycle_time()
		_produce_cycle(inputs, outputs)
	return State.RUNNING

## Tira insumos del almacén central (hasta ~4 ciclos en buffer) y vacía la salida
## al almacén. Sólo para máquinas manuales (auto_supply).
func _auto_supply_tick(inputs: Dictionary) -> void:
	for id in inputs.keys():
		var per_cycle := int(inputs[id])
		var want: int = per_cycle * 4
		var have: int = input_buffer.count(id)
		if have < want:
			var pulled: int = GameManager.storage.withdraw(id, want - have)
			if pulled > 0:
				input_buffer.add(id, pulled)
	# Descarga la producción acumulada al almacén de la empresa.
	var out_items := output_buffer.provide_peek()
	for id in out_items.keys():
		var n := int(out_items[id])
		var stored: int = GameManager.storage.deposit(id, n)
		if stored > 0:
			output_buffer.remove(id, stored)

func _effective_speed() -> float:
	# La condición degrada la velocidad; el operador y las mejoras la aumentan.
	var condition_factor: float = lerpf(0.45, 1.0, clampf(condition / 100.0, 0.0, 1.0))
	var op := 0.0
	if GameManager.workers:
		op = GameManager.workers.operator_bonus()
	var upg := 1.0
	if GameManager.upgrades:
		upg = GameManager.upgrades.machine_speed_mult()
	# Bonus de especialización: las máquinas de tu rama industrial rinden más.
	var branch := 1.0
	if GameManager.specialization:
		branch = GameManager.specialization.machine_bonus(machine_id)
	return base_speed * condition_factor * (1.0 + op) * upg * level_speed_mult() * branch

## Consumo eléctrico efectivo (mejoras globales + nivel de la máquina).
func effective_power_draw() -> float:
	var mult := 1.0
	if GameManager.upgrades:
		mult = GameManager.upgrades.power_draw_mult()
	return power_draw * mult * (1.0 + (level - 1) * 0.15)

# --- Mejora por máquina (Fundición I → II → III, spec §8/§20) ----------------
func level_speed_mult() -> float:
	match level:
		2: return 1.5
		3: return 2.2
		_: return 1.0

func can_upgrade() -> bool:
	return level < MAX_LEVEL

func upgrade_cost() -> float:
	return float(def.get("cost", 1000)) * (0.8 + (level - 1) * 0.6)

## Mejora la máquina un nivel si hay fondos. Devuelve true si se aplicó.
func upgrade() -> bool:
	if not can_upgrade():
		return false
	var cost := upgrade_cost()
	if not GameManager.economy.spend(cost, "construction"):
		return false
	level += 1
	set_condition(minf(100.0, condition + 20.0))
	EventBus.machine_state_changed.emit(self)
	EventBus.notify.emit("%s mejorada a nivel %d (%s)" % [display_name(), level, Fmt.money(cost)], "success")
	return true

func roman_level() -> String:
	return ["", "I", "II", "III", "IV"][clampi(level, 0, 4)]

## Producción teórica por minuto (para el panel de máquina, spec §20).
func production_per_min() -> float:
	if recipe_id == "":
		return 0.0
	var outs := current_outputs()
	var total := 0
	for v in outs.values():
		total += int(v)
	if total <= 0 or cycle_time() <= 0.0:
		return 0.0
	return float(total) / cycle_time() * _effective_speed() * 60.0

func _output_has_room(outputs: Dictionary) -> bool:
	var needed := 0
	for v in outputs.values():
		needed += int(v)
	return output_buffer.free_space() >= needed

func _produce_cycle(inputs: Dictionary, outputs: Dictionary) -> void:
	if not input_buffer.consume_all(inputs):
		return
	quality = GameManager.quality.roll_quality(self)
	for item_id in outputs.keys():
		var n := int(outputs[item_id])
		output_buffer.add(item_id, n)
		EventBus.item_produced.emit(item_id, n)
	# Desgaste por uso (reducido por la mejora de mantenimiento preventivo).
	var wear := WEAR_PER_CYCLE
	if GameManager.upgrades:
		wear *= GameManager.upgrades.wear_mult()
	set_condition(condition - wear)

func set_condition(v: float) -> void:
	condition = clampf(v, 0.0, 100.0)
	if condition <= 0.0 and state != State.BROKEN:
		EventBus.machine_breakdown.emit(self)

# --- Prioridad / activación -------------------------------------------------
func set_enabled(v: bool) -> void:
	enabled = v
	_on_tick(0.0)

func set_priority(p: int) -> void:
	priority = clampi(p, 0, 3)

func priority_name() -> String:
	return PRIORITY_NAMES[priority]

func state_name() -> String:
	return STATE_NAMES.get(state, "?")

func display_name() -> String:
	var n := String(def.get("name", machine_id))
	return n + (" " + roman_level() if level > 1 else "")

# --- Puertos (para cintas) --------------------------------------------------
func port_provide_peek() -> Dictionary:
	return output_buffer.provide_peek()

func port_provide_take(item_id: String, n: int) -> int:
	return output_buffer.remove(item_id, n)

func port_receive_can(item_id: String, n: int) -> int:
	if not current_inputs().has(item_id):
		return 0
	return min(n, input_buffer.free_space())

func port_receive_give(item_id: String, n: int) -> int:
	if not current_inputs().has(item_id):
		return 0
	return input_buffer.add(item_id, n)

# --- Posición en mundo ------------------------------------------------------
func world_center() -> Vector3:
	return global_position

## Punto de salida (lado +Z) donde las cintas recogen productos.
func provider_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, d)

## Punto de entrada (lado -Z) donde las cintas depositan materiales.
func receiver_port_position() -> Vector3:
	var d := grid_size.y * GameState.CELL_SIZE * 0.5
	return global_position + Vector3(0, 1.3, -d)

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"machine_id": machine_id,
		"origin": [grid_origin.x, grid_origin.y],
		"recipe": recipe_id,
		"enabled": enabled,
		"priority": priority,
		"level": level,
		"condition": condition,
		"progress": progress,
		"input": input_buffer.to_dict(),
		"output": output_buffer.to_dict(),
	}

func apply_dict(data: Dictionary) -> void:
	uid = int(data.get("uid", uid))
	recipe_id = String(data.get("recipe", recipe_id))
	enabled = bool(data.get("enabled", true))
	priority = int(data.get("priority", 1))
	level = int(data.get("level", 1))
	condition = float(data.get("condition", 100.0))
	progress = float(data.get("progress", 0.0))
	if data.has("input"):
		input_buffer.from_dict(data["input"])
	if data.has("output"):
		output_buffer.from_dict(data["output"])
	_update_visual_state()

# --- Modelo 3D (capa separada) + colisión + estado --------------------------
# La geometría vive en MachineModel; aquí sólo se instancia y se le informa el
# estado. Esto separa MODELO ↓ COLISIÓN ↓ INTERACCIÓN ↓ LÓGICA (spec §2/§31).
func _build_visual() -> void:
	_model = MachineModelScript.new()
	_model.name = "Model"
	add_child(_model)
	_model.build(machine_id, def, grid_size)
	_build_collision()
	_model.set_state(state)

func _build_collision() -> void:
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var pick := StaticBody3D.new()
	pick.collision_layer = 2
	pick.collision_mask = 0
	pick.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 4.5, d)
	cs.shape = box
	cs.position = Vector3(0, 2.25, 0)
	pick.add_child(cs)
	pick.set_meta("machine", self)
	add_child(pick)

func _update_visual_state() -> void:
	if _model:
		_model.set_state(state)
