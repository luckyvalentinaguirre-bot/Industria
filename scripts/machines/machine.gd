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
	# La condición degrada la velocidad; el operador y las mejoras la aumentan.
	var condition_factor: float = lerpf(0.45, 1.0, clampf(condition / 100.0, 0.0, 1.0))
	var op := 0.0
	if GameManager.workers:
		op = GameManager.workers.operator_bonus()
	var upg := 1.0
	if GameManager.upgrades:
		upg = GameManager.upgrades.machine_speed_mult()
	return base_speed * condition_factor * (1.0 + op) * upg

## Consumo eléctrico efectivo (con mejoras de eficiencia).
func effective_power_draw() -> float:
	var mult := 1.0
	if GameManager.upgrades:
		mult = GameManager.upgrades.power_draw_mult()
	return power_draw * mult

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

# --- Modelo 3D --------------------------------------------------------------
# Modelos bespoke por tipo (horno, prensa, celda robótica) con partes animadas.
# Preparado para sustituirse por el asset final del pipeline gráfico.
var _sparks: GPUParticles3D
var _damage_smoke: GPUParticles3D
var _beacon_light: OmniLight3D
var _glow_light: OmniLight3D
var _glow_mat: StandardMaterial3D
var _anim_primary: Node3D
var _anim_secondary: Node3D
var _anim_kind: String = ""
var _ram_base_y: float = 2.6

func _build_visual() -> void:
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var color := _category_color()

	# Materiales del kit industrial compartido (coherencia visual, spec §2/§15).
	var mats := {
		"housing": IndKit.housing(color),
		"steel": IndKit.steel(),
		"dark": IndKit.dark_metal(),
		"concrete": IndKit.concrete(),
		"rubber": IndKit.rubber(),
	}

	# Losa de cimentación común con bordes.
	_add_box(Vector3(w * 0.99, 0.3, d * 0.99), Vector3(0, 0.15, 0), mats["concrete"])
	_add_box(Vector3(w * 0.99, 0.08, d * 0.99), Vector3(0, 0.32, 0), mats["dark"])

	match machine_id:
		"smelter": _build_smelter(w, d, mats)
		"press": _build_press(w, d, mats)
		"assembler": _build_assembler(w, d, mats)
		_: _build_generic(w, d, mats)

	_add_industrial_detail(w, d, mats)

	# Baliza de estado sobre mástil (común).
	var hx := w * 0.42
	var hz := d * 0.42
	_add_cylinder(0.05, 0.06, 0.6, Vector3(hx, 2.7, hz), mats["dark"])
	_status_light = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.2
	lm.height = 0.4
	_status_light.mesh = lm
	_status_light.position = Vector3(hx, 3.1, hz)
	add_child(_status_light)
	# Foco de la baliza para que ilumine su entorno.
	_beacon_light = OmniLight3D.new()
	_beacon_light.position = Vector3(hx, 3.1, hz)
	_beacon_light.omni_range = 6.0
	_beacon_light.light_energy = 1.5
	_beacon_light.shadow_enabled = false
	add_child(_beacon_light)

	_sparks = _make_sparks(color)
	_sparks.position = Vector3(0, 1.1, d * 0.42)
	add_child(_sparks)

	# Humo negro de avería (sólo cuando la máquina está averiada).
	_damage_smoke = _make_damage_smoke()
	_damage_smoke.position = Vector3(-w * 0.2, 2.3, 0)
	add_child(_damage_smoke)

	# Colisión para selección (capa 2).
	var pick := StaticBody3D.new()
	pick.collision_layer = 2
	pick.collision_mask = 0
	pick.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 3.2, d)
	cs.shape = box
	cs.position = Vector3(0, 1.6, 0)
	pick.add_child(cs)
	pick.set_meta("machine", self)
	add_child(pick)

	_update_visual_state()

# --- Detalle industrial compartido (coherencia entre todas las máquinas) ----
func _add_industrial_detail(w: float, d: float, mats: Dictionary) -> void:
	var dark: Material = mats["dark"]
	# Pernos en el zócalo frontal.
	IndKit.bolt_row(self, 5, -w * 0.4, w * 0.4, 0.42, d * 0.49, dark)
	# Franja de peligro en la base (frente).
	IndKit.hazard_stripe(self, Vector3(w * 0.82, 0.16, 0.05), Vector3(0, 0.58, d * 0.47))
	# Rejilla de ventilación lateral.
	IndKit.grille(self, 0.7, 0.8, Vector3(-w * 0.47, 1.2, 0), dark)
	# Cables desde el panel hacia el cuerpo.
	IndKit.cable(self, Vector3(-w * 0.2, 1.7, d * 0.4), Vector3(-w * 0.42, 2.1, d * 0.05), dark)
	# Señal de advertencia en una esquina.
	IndKit.warning_sign(self, Vector3(-w * 0.44, 0.35, d * 0.32))

# --- Detalles comunes -------------------------------------------------------
func _add_control_panel(pos: Vector3, mats: Dictionary) -> void:
	_add_box(Vector3(0.7, 0.95, 0.14), pos, mats["dark"])
	var screen := _pbr(Color(0.15, 0.5, 0.65), 0.2, 0.0)
	screen.emission_enabled = true
	screen.emission = Color(0.25, 0.8, 1.0)
	screen.emission_energy_multiplier = 1.8
	_add_box(Vector3(0.48, 0.4, 0.04), pos + Vector3(0, 0.18, 0.09), screen)
	# Botonera.
	for i in range(3):
		var btn := _pbr(Color(0.9, 0.3, 0.2) if i == 0 else Color(0.3, 0.8, 0.4), 0.4, 0.0)
		btn.emission_enabled = true
		btn.emission = btn.albedo_color
		btn.emission_energy_multiplier = 0.8
		_add_cylinder(0.05, 0.05, 0.05, pos + Vector3(-0.18 + i * 0.18, -0.2, 0.08), btn).rotation_degrees = Vector3(90, 0, 0)

func _add_ladder(base: Vector3, height: float, mat: Material) -> void:
	for side in [-1, 1]:
		_add_cylinder(0.03, 0.03, height, base + Vector3(side * 0.18, height * 0.5, 0), mat)
	var rungs := int(height / 0.35)
	for i in range(rungs):
		var r := _add_cylinder(0.025, 0.025, 0.36, base + Vector3(0, 0.3 + i * 0.35, 0), mat)
		r.rotation_degrees = Vector3(0, 0, 90)

func _add_bolts(size_x: float, pos: Vector3, mat: Material) -> void:
	for i in range(4):
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sy := -1.0 if i < 2 else 1.0
		_add_cylinder(0.05, 0.05, 0.08, pos + Vector3(sx * size_x * 0.5, sy * 0.25, 0.02), mat).rotation_degrees = Vector3(90, 0, 0)

# --- HORNO DE FUNDICIÓN -----------------------------------------------------
func _build_smelter(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	# Cuerpo del horno: cilindro ancho abombado con anillos de refuerzo.
	_add_cylinder(w * 0.34, w * 0.4, 2.2, Vector3(0, 1.4, -d * 0.05), steel)
	for i in range(3):
		var ring := _add_cylinder(w * 0.42, w * 0.42, 0.12, Vector3(0, 0.7 + i * 0.7, -d * 0.05), dark)
	# Cúpula superior.
	var dome := _add_sphere(w * 0.34, Vector3(0, 2.5, -d * 0.05), steel)
	dome.scale = Vector3(1, 0.6, 1)
	# Boca de colada incandescente al frente + foco.
	_glow_mat = _pbr(Color(1.0, 0.45, 0.1), 0.4, 0.0)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.4, 0.08)
	_glow_mat.emission_energy_multiplier = 2.0
	_add_box(Vector3(0.7, 0.5, 0.3), Vector3(0, 0.85, d * 0.32), _glow_mat)
	_add_cylinder(0.12, 0.18, 0.6, Vector3(0, 0.6, d * 0.42), dark).rotation_degrees = Vector3(60, 0, 0)
	_glow_light = OmniLight3D.new()
	_glow_light.position = Vector3(0, 0.9, d * 0.45)
	_glow_light.light_color = Color(1.0, 0.5, 0.15)
	_glow_light.omni_range = 5.0
	_glow_light.light_energy = 2.0
	_glow_light.shadow_enabled = false
	add_child(_glow_light)
	# Chimenea alta con sombrerete.
	_add_cylinder(0.28, 0.34, 2.6, Vector3(w * 0.26, 3.0, -d * 0.28), dark)
	_add_cylinder(0.42, 0.42, 0.12, Vector3(w * 0.26, 4.35, -d * 0.28), dark)
	# Escalera de acceso.
	_add_ladder(Vector3(-w * 0.36, 0.3, d * 0.1), 2.4, dark)
	# Tuberías de alimentación.
	_add_pipe(w * 0.7, Vector3(0, 1.9, -d * 0.4 - 0.1), Vector3(90, 0, 0), dark)
	_add_valve(Vector3(w * 0.3, 1.9, -d * 0.4), Color(0.7, 0.3, 0.2))
	_add_control_panel(Vector3(-w * 0.28, 1.1, d * 0.36), mats)
	# Ventilador de tiro (gira).
	_anim_primary = Node3D.new()
	_anim_primary.position = Vector3(w * 0.26, 4.4, -d * 0.28)
	add_child(_anim_primary)
	_add_fan(_anim_primary, 0.3, dark)
	_anim_kind = "smelter"
	# Humo por la chimenea.
	_running_particles = _make_steam()
	_running_particles.position = Vector3(w * 0.26, 4.5, -d * 0.28)
	add_child(_running_particles)

# --- PRENSA DE BASTIDOR -----------------------------------------------------
func _build_press(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var housing: Material = mats["housing"]
	# Base / bancada.
	_add_box(Vector3(w * 0.8, 0.8, d * 0.7), Vector3(0, 0.7, 0), housing)
	_add_bolts(w * 0.8, Vector3(0, 0.9, d * 0.36), dark)
	# Dos columnas robustas.
	for sx in [-1, 1]:
		_add_box(Vector3(0.4, 3.0, 0.4), Vector3(sx * w * 0.3, 2.4, 0), steel)
	# Corona superior (crown).
	_add_box(Vector3(w * 0.8, 0.7, d * 0.55), Vector3(0, 4.0, 0), housing)
	# Cilindro hidráulico sobre la corona.
	_add_cylinder(0.35, 0.35, 1.0, Vector3(0, 4.7, 0), dark)
	# Ariete móvil (baja al producir).
	_anim_primary = Node3D.new()
	add_child(_anim_primary)
	_ram_base_y = 2.6
	_anim_primary.position = Vector3(0, _ram_base_y, 0)
	_add_box(Vector3(w * 0.5, 0.9, d * 0.45), Vector3(0, 0, 0), steel)
	_add_cylinder(0.22, 0.22, 1.2, Vector3(0, 0.9, 0), mats["dark"])   # vástago
	# Matriz inferior.
	_add_box(Vector3(w * 0.5, 0.35, d * 0.45), Vector3(0, 1.35, 0), dark)
	# Barandillas de seguridad frontales.
	_add_railing(Vector3(0, 0, d * 0.36), w * 0.7, mats["dark"])
	_add_control_panel(Vector3(w * 0.44, 1.1, d * 0.2), mats)
	_anim_kind = "press"
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 1.6, 0)
	add_child(_running_particles)

# --- CELDA DE ENSAMBLAJE CON BRAZO ROBÓTICO ---------------------------------
func _build_assembler(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var housing: Material = mats["housing"]
	# Bancada baja.
	_add_box(Vector3(w * 0.9, 0.9, d * 0.85), Vector3(0, 0.75, 0), housing)
	# Vallado de la celda con ventanas de vidrio.
	var glass := _pbr(Color(0.4, 0.6, 0.7, 0.25), 0.1, 0.0)
	glass.emission_enabled = true
	glass.emission = Color(0.2, 0.4, 0.5)
	glass.emission_energy_multiplier = 0.3
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for corner in [Vector3(-w * 0.42, 0, -d * 0.4), Vector3(w * 0.42, 0, -d * 0.4)]:
		_add_cylinder(0.06, 0.06, 2.2, Vector3(corner.x, 2.3, corner.z), dark)
	_add_box(Vector3(w * 0.85, 1.4, 0.05), Vector3(0, 2.0, -d * 0.4), glass)
	for sx in [-1, 1]:
		_add_box(Vector3(0.05, 1.4, d * 0.75), Vector3(sx * w * 0.42, 2.0, 0), glass)
	# Base del robot.
	_add_cylinder(0.45, 0.55, 0.5, Vector3(0, 1.45, 0), dark)
	# Brazo robótico multiarticulado (anim).
	_anim_primary = Node3D.new()          # rota sobre la base
	_anim_primary.position = Vector3(0, 1.7, 0)
	add_child(_anim_primary)
	var shoulder := _add_child_box(_anim_primary, Vector3(0.4, 0.4, 0.4), Vector3(0, 0.1, 0), housing)
	# Brazo superior.
	_add_child_box(_anim_primary, Vector3(0.28, 1.3, 0.28), Vector3(0, 0.75, 0.1), steel)
	# Codo articulado (anim secundaria).
	_anim_secondary = Node3D.new()
	_anim_secondary.position = Vector3(0, 1.35, 0.1)
	_anim_primary.add_child(_anim_secondary)
	_add_child_box(_anim_secondary, Vector3(0.24, 1.0, 0.24), Vector3(0, 0.45, 0.25), steel)
	# Muñeca + pinza.
	_add_child_box(_anim_secondary, Vector3(0.3, 0.2, 0.3), Vector3(0, 0.9, 0.4), dark)
	for gx in [-1, 1]:
		_add_child_box(_anim_secondary, Vector3(0.06, 0.3, 0.1), Vector3(gx * 0.12, 1.05, 0.45), dark)
	# Luz de trabajo cenital.
	var worklight := _pbr(Color(1, 1, 0.9), 0.3, 0.0)
	worklight.emission_enabled = true
	worklight.emission = Color(1, 1, 0.85)
	worklight.emission_energy_multiplier = 1.5
	_add_box(Vector3(1.2, 0.1, 0.4), Vector3(0, 2.7, 0), worklight)
	_add_control_panel(Vector3(-w * 0.3, 1.15, d * 0.4), mats)
	_anim_kind = "arm"
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 2.0, 0.3)
	add_child(_running_particles)

func _build_generic(w: float, d: float, mats: Dictionary) -> void:
	_add_box(Vector3(w * 0.82, 1.7, d * 0.82), Vector3(0, 1.2, 0), mats["housing"])
	_add_box(Vector3(w * 0.6, 0.35, d * 0.6), Vector3(0, 2.2, 0), mats["steel"])
	_anim_primary = Node3D.new()
	_anim_primary.position = Vector3(0, 2.4, 0)
	add_child(_anim_primary)
	_add_fan(_anim_primary, 0.5, mats["dark"])
	_anim_kind = "fan"
	_add_control_panel(Vector3(0, 1.2, d * 0.42), mats)
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 2.6, 0)
	add_child(_running_particles)

# --- Helpers de construcción de malla ---------------------------------------
func _add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_cylinder(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_pipe(length: float, pos: Vector3, rot_deg: Vector3, mat: Material) -> void:
	var mi := _add_cylinder(0.09, 0.09, length, pos, mat)
	mi.rotation_degrees = rot_deg

func _add_sphere(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_child_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_railing(center: Vector3, length: float, mat: Material) -> void:
	# Pasamanos con postes.
	var top := _add_cylinder(0.03, 0.03, length, center + Vector3(0, 1.0, 0), mat)
	top.rotation_degrees = Vector3(0, 0, 90)
	var posts := int(length / 0.8)
	for i in range(posts + 1):
		var t := float(i) / float(posts)
		var x := lerpf(-length * 0.5, length * 0.5, t)
		_add_cylinder(0.03, 0.03, 1.0, center + Vector3(x, 0.5, 0), mat)

func _add_valve(pos: Vector3, color: Color) -> void:
	var mat := _pbr(color.lightened(0.1), 0.4, 0.6)
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.12
	t.outer_radius = 0.22
	mi.mesh = t
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _add_gear(parent: Node3D, radius: float, mat: Material) -> void:
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.3
	hub.mesh = cm
	hub.material_override = mat
	parent.add_child(hub)
	for i in range(8):
		var tooth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.3, 0.22)
		tooth.mesh = bm
		tooth.material_override = mat
		var ang := TAU * i / 8.0
		tooth.position = Vector3(cos(ang) * radius, 0, sin(ang) * radius)
		tooth.rotation.y = -ang
		parent.add_child(tooth)

func _add_fan(parent: Node3D, radius: float, mat: Material) -> void:
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 0.2
	hub.mesh = cm
	hub.material_override = mat
	parent.add_child(hub)
	for i in range(4):
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(radius, 0.05, 0.2)
		blade.mesh = bm
		blade.material_override = mat
		var ang := TAU * i / 4.0
		blade.position = Vector3(cos(ang) * radius * 0.5, 0, sin(ang) * radius * 0.5)
		blade.rotation.y = -ang
		parent.add_child(blade)

func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.0
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 14.0
	mat.initial_velocity_min = 0.7
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.2
	dot.height = 0.4
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.9, 0.9, 0.95, 0.28)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _make_damage_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.8
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.2, 1, 0)
	mat.spread = 18.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0.3, 0.6, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.2
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.22
	dot.height = 0.44
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.12, 0.12, 0.13, 0.5)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _make_sparks(color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.6
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0.4)
	mat.spread = 40.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -6.0, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.12
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.8, 0.3)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.7, 0.2)
	dm.emission_energy_multiplier = 3.0
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _process(delta: float) -> void:
	var running := state == State.RUNNING
	var t := Time.get_ticks_msec() / 1000.0
	match _anim_kind:
		"smelter":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 3.0)
			# Pulso de la boca incandescente y su foco.
			if _glow_mat:
				var e: float = (2.2 + 0.9 * sin(t * 4.0)) if running else 0.5
				_glow_mat.emission_energy_multiplier = e
			if _glow_light:
				_glow_light.light_energy = (2.5 + 0.8 * sin(t * 4.0)) if running else 0.6
		"press":
			if _anim_primary:
				# Ariete: golpe descendente rápido + retorno.
				var stroke: float = (0.55 * (0.5 - 0.5 * cos(t * 7.0))) if running else 0.0
				_anim_primary.position.y = _ram_base_y - stroke
		"arm":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 1.4)
			if _anim_secondary:
				_anim_secondary.rotation.x = (0.5 * sin(t * 3.0)) if running else 0.15
		"fan":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 6.0)

func _category_color() -> Color:
	match String(def.get("category", "")):
		"processing": return Color(0.72, 0.42, 0.24)
		"manufacturing": return Color(0.34, 0.52, 0.72)
		"power": return Color(0.78, 0.68, 0.22)
		_: return Color(0.52, 0.55, 0.6)

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
	if _beacon_light:
		_beacon_light.light_color = c
		_beacon_light.light_energy = 1.8 if state == State.RUNNING else 0.8
	if _running_particles:
		_running_particles.emitting = (state == State.RUNNING)
	if _sparks:
		# Chispas sólo en máquinas de manufactura/procesado en marcha.
		var cat := String(def.get("category", ""))
		_sparks.emitting = (state == State.RUNNING) and (cat == "manufacturing" or cat == "processing")
	if _damage_smoke:
		_damage_smoke.emitting = (state == State.BROKEN)

func _pbr(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
