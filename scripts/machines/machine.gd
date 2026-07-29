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

# --- Estado dinámico --------------------------------------------------------
var state: int = State.IDLE
var progress: float = 0.0
var condition: float = 100.0     # 100 -> 0
var quality: float = 1.0
var powered: bool = true         # lo fija PowerManager
var operator_bonus: float = 0.0  # lo fija WorkerManager

var input_buffer: Inventory
var output_buffer: Inventory

# --- Visual -----------------------------------------------------------------
var _status_light: MeshInstance3D
var _rotor: Node3D
var _running_particles: GPUParticles3D

func setup(id: String, origin: Vector2i) -> void:
	machine_id = id
	def = GameManager.recipes.get_machine_def(id)
	grid_origin = origin
	var s: Array = def.get("size", [2, 2])
	grid_size = Vector2i(int(s[0]), int(s[1]))
	power_draw = float(def.get("power", 0.0))
	base_speed = float(def.get("base_speed", 1.0))
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

func _effective_speed() -> float:
	# La condición degrada la velocidad; el operador la mejora (spec §11, §12).
	var condition_factor: float = lerpf(0.45, 1.0, clampf(condition / 100.0, 0.0, 1.0))
	var op := 0.0
	if GameManager.workers:
		op = GameManager.workers.operator_bonus()
	return base_speed * condition_factor * (1.0 + op)

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
	# Desgaste por uso.
	set_condition(condition - WEAR_PER_CYCLE)

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
	return String(def.get("name", machine_id))

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
	condition = float(data.get("condition", 100.0))
	progress = float(data.get("progress", 0.0))
	if data.has("input"):
		input_buffer.from_dict(data["input"])
	if data.has("output"):
		output_buffer.from_dict(data["output"])
	_update_visual_state()

# --- Modelo 3D placeholder --------------------------------------------------
func _build_visual() -> void:
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var color := _category_color()

	# Base / carcasa.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(w * 0.9, 2.2, d * 0.9)
	body.mesh = body_mesh
	body.position = Vector3(0, 1.1, 0)
	body.material_override = _pbr(color, 0.6, 0.35)
	add_child(body)

	# Detalle superior (rotor que gira al producir).
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 2.4, 0)
	add_child(_rotor)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = w * 0.18
	top_mesh.bottom_radius = w * 0.22
	top_mesh.height = 0.6
	top.mesh = top_mesh
	top.material_override = _pbr(color.darkened(0.2), 0.8, 0.2)
	_rotor.add_child(top)

	# Luz de estado.
	_status_light = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.22
	lm.height = 0.44
	_status_light.mesh = lm
	_status_light.position = Vector3(w * 0.35, 2.4, d * 0.35)
	add_child(_status_light)

	# Partículas de trabajo (vapor/humo tenue), apagadas por defecto.
	_running_particles = _make_particles()
	_running_particles.position = Vector3(-w * 0.3, 2.6, 0)
	add_child(_running_particles)

	# Cuerpo de colisión para selección por ray (capa 2).
	var pick := StaticBody3D.new()
	pick.collision_layer = 2
	pick.collision_mask = 0
	pick.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 2.6, d)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	pick.add_child(cs)
	pick.set_meta("machine", self)
	add_child(pick)

	_update_visual_state()

func _make_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 1.6
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.2
	mat.gravity = Vector3(0, 0.4, 0)
	mat.scale_min = 0.4
	mat.scale_max = 0.9
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.18
	dot.height = 0.36
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.85, 0.9, 0.35)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _process(delta: float) -> void:
	if _rotor and state == State.RUNNING:
		_rotor.rotate_y(delta * 4.0)

func _category_color() -> Color:
	match String(def.get("category", "")):
		"processing": return Color(0.75, 0.45, 0.25)
		"manufacturing": return Color(0.35, 0.55, 0.75)
		"power": return Color(0.8, 0.7, 0.25)
		_: return Color(0.55, 0.57, 0.6)

func _update_visual_state() -> void:
	if not _status_light:
		return
	var c := Color(0.4, 0.4, 0.4)
	match state:
		State.RUNNING: c = Color(0.2, 0.9, 0.35)
		State.NO_MATERIALS: c = Color(0.95, 0.75, 0.2)
		State.BLOCKED: c = Color(0.95, 0.55, 0.15)
		State.NO_POWER: c = Color(0.9, 0.2, 0.2)
		State.BROKEN: c = Color(0.9, 0.1, 0.1)
		State.MAINTENANCE: c = Color(0.2, 0.6, 0.95)
		State.DISABLED, State.IDLE: c = Color(0.35, 0.35, 0.38)
	var m := _status_light.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_status_light.material_override = m
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	if _running_particles:
		_running_particles.emitting = (state == State.RUNNING)

func _pbr(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
