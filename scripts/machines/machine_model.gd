extends Node3D
class_name MachineModel
## MachineModel — CAPA DE MODELO 3D de las máquinas, separada de la lógica.
##
## Construye y anima la geometría de cada máquina usando el kit industrial
## compartido (IndKit). La lógica de producción (machine.gd) NO conoce la
## geometría: sólo instancia este modelo y le informa el estado con set_state().
## Así el modelo provisional se puede sustituir por el asset final sin tocar el
## gameplay (spec §2, §31, §32):  MODELO 3D ↓ COLISIÓN ↓ INTERACCIÓN ↓ LÓGICA.

var machine_id: String = ""
var def: Dictionary = {}
var grid_size: Vector2i = Vector2i(2, 2)

# Referencias animadas / de estado (las mueve/actualiza este mismo modelo).
var _anim_kind: String = ""
var _anim_primary: Node3D
var _anim_secondary: Node3D
var _ram_base_y: float = 3.0
var _glow_mat: StandardMaterial3D
var _glow_light: OmniLight3D
var _status_light: MeshInstance3D
var _beacon_light: OmniLight3D
var _running_particles: GPUParticles3D
var _sparks: GPUParticles3D
var _damage_smoke: GPUParticles3D
var _state: int = 0   # Machine.State

# --- Construcción -----------------------------------------------------------
func build(p_id: String, p_def: Dictionary, p_grid: Vector2i) -> void:
	machine_id = p_id
	def = p_def
	grid_size = p_grid
	var cell := GameState.CELL_SIZE
	var w := grid_size.x * cell
	var d := grid_size.y * cell
	var color := _category_color()
	var mats := {
		"housing": IndKit.housing(color),
		"steel": IndKit.steel(),
		"dark": IndKit.dark_metal(),
		"concrete": IndKit.concrete(),
		"rubber": IndKit.rubber(),
	}

	# Losa de cimentación con canto metálico (base común, coherencia).
	IndKit.box(self, Vector3(w * 0.99, 0.3, d * 0.99), Vector3(0, 0.15, 0), mats["concrete"])
	IndKit.box(self, Vector3(w * 0.99, 0.08, d * 0.99), Vector3(0, 0.32, 0), mats["dark"])

	match machine_id:
		"smelter": _build_smelter(w, d, mats)
		"press": _build_press(w, d, mats)
		"assembler": _build_assembler(w, d, mats)
		_: _build_generic(w, d, mats)

	_add_industrial_detail(w, d, mats)
	_add_beacon(w, d, mats)
	_add_effects(w, d, color)
	set_state(_state)

# --- FUNDICIÓN (asset de referencia, spec §3, §32) --------------------------
func _build_smelter(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var housing: Material = mats["housing"]

	# Bastidor estructural pesado: 4 columnas + vigas.
	var hx := w * 0.4
	var hz := d * 0.4
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			IndKit.box(self, Vector3(0.28, 5.2, 0.28), Vector3(sx * hx, 2.9, sz * hz), dark)
	for sz in [-1, 1]:
		IndKit.box(self, Vector3(w * 0.82, 0.22, 0.22), Vector3(0, 5.3, sz * hz), dark)

	# Horno principal: vasija abombada con anillos de refuerzo.
	IndKit.cyl(self, w * 0.34, w * 0.42, 3.4, Vector3(0, 2.2, -d * 0.04), steel)
	for i in range(4):
		IndKit.cyl(self, w * 0.44, w * 0.44, 0.14, Vector3(0, 0.9 + i * 0.8, -d * 0.04), dark)
	var dome := IndKit.cyl(self, w * 0.16, w * 0.36, 0.9, Vector3(0, 4.1, -d * 0.04), steel)

	# Boca de colada incandescente + canaleta + foco.
	_glow_mat = IndKit.emissive(Color(1.0, 0.45, 0.1), 2.0)
	IndKit.box(self, Vector3(0.9, 0.6, 0.4), Vector3(0, 1.15, d * 0.34), _glow_mat)
	IndKit.box(self, Vector3(1.2, 0.12, 0.7), Vector3(0, 0.5, d * 0.5), IndKit.dark_metal())  # canaleta de salida
	var spout := IndKit.cyl(self, 0.14, 0.2, 0.7, Vector3(0, 0.85, d * 0.46), dark)
	spout.rotation_degrees = Vector3(58, 0, 0)
	_glow_light = _omni(Vector3(0, 1.0, d * 0.5), Color(1.0, 0.5, 0.15), 5.5, 2.2)
	add_child(_glow_light)

	# Tolva de entrada de material (parte trasera-alta).
	var hopper := IndKit.cyl(self, w * 0.22, w * 0.08, 0.9, Vector3(0, 4.6, -d * 0.3), dark)
	IndKit.box(self, Vector3(0.5, 0.4, 0.5), Vector3(0, 5.1, -d * 0.3), housing)

	# Dos chimeneas altas con sombrerete.
	for sx in [-1, 1]:
		IndKit.cyl(self, 0.3, 0.36, 3.2, Vector3(sx * w * 0.28, 5.3, -d * 0.26), dark)
		IndKit.cyl(self, 0.46, 0.46, 0.14, Vector3(sx * w * 0.28, 7.0, -d * 0.26), dark)

	# Tanques laterales conectados por tuberías con válvulas.
	for sx in [-1, 1]:
		var tx: float = sx * (w * 0.46 + 0.2)
		IndKit.cyl(self, 0.45, 0.5, 2.2, Vector3(tx, 1.7, d * 0.1), steel)
		IndKit.cyl(self, 0.1, 0.5, 0.4, Vector3(tx, 2.9, d * 0.1), dark)
		IndKit.pipe(self, Vector3(tx, 1.8, d * 0.1), Vector3(sx * w * 0.34, 1.8, -d * 0.04), 0.12, dark)
		_valve(Vector3(sx * w * 0.4, 1.8, d * 0.02), IndKit.copper())

	# Plataforma de mantenimiento con baranda + escalera de acceso.
	IndKit.platform(self, Vector2(w * 0.95, 0.9), Vector3(0, 3.0, d * 0.42), mats["steel"])
	IndKit.railing(self, Vector3(0, 3.0, d * 0.46), w * 0.9, dark)
	IndKit.ladder(self, Vector3(-w * 0.42, 0.35, d * 0.42), 2.6, dark)

	# Panel de control + cableado a la vasija.
	_control_panel(Vector3(w * 0.3, 1.2, d * 0.42), mats)
	IndKit.cable(self, Vector3(w * 0.3, 1.9, d * 0.42), Vector3(w * 0.3, 3.4, 0), dark)

	# Ventilador de tiro que gira sobre una chimenea.
	_anim_primary = Node3D.new()
	_anim_primary.position = Vector3(w * 0.28, 7.05, -d * 0.26)
	add_child(_anim_primary)
	_fan(_anim_primary, 0.3, dark)
	_anim_kind = "smelter"
	_running_particles = _make_steam()
	_running_particles.position = Vector3(-w * 0.28, 7.2, -d * 0.26)
	add_child(_running_particles)

# --- PRENSA HIDRÁULICA ------------------------------------------------------
func _build_press(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var housing: Material = mats["housing"]
	# Bancada pesada.
	IndKit.box(self, Vector3(w * 0.85, 1.0, d * 0.75), Vector3(0, 0.85, 0), housing)
	IndKit.bolt_row(self, 4, -w * 0.35, w * 0.35, 1.1, d * 0.34, dark)
	# Dos columnas robustas + corona.
	for sx in [-1, 1]:
		IndKit.box(self, Vector3(0.5, 3.8, 0.5), Vector3(sx * w * 0.3, 3.0, 0), steel)
	IndKit.box(self, Vector3(w * 0.85, 0.8, d * 0.6), Vector3(0, 5.0, 0), housing)
	# Grupo hidráulico + motor sobre la corona.
	IndKit.cyl(self, 0.4, 0.4, 1.1, Vector3(0, 5.8, 0), dark)
	IndKit.box(self, Vector3(0.9, 0.7, 0.9), Vector3(-w * 0.2, 5.7, 0), dark)
	_valve(Vector3(w * 0.28, 5.4, d * 0.2), IndKit.copper())
	# Ariete móvil (baja al producir).
	_anim_primary = Node3D.new()
	add_child(_anim_primary)
	_ram_base_y = 3.3
	_anim_primary.position = Vector3(0, _ram_base_y, 0)
	# Cabezal del ariete: hijo del nodo animado para que baje con él.
	_child_box(_anim_primary, Vector3(w * 0.5, 1.0, d * 0.45), Vector3.ZERO, steel)
	# Matriz inferior fija.
	IndKit.box(self, Vector3(w * 0.5, 0.4, d * 0.45), Vector3(0, 1.5, 0), dark)
	IndKit.box(self, Vector3(0.24, 1.4, 0.24), Vector3(0, 2.0, 0), IndKit.dark_metal())  # vástago
	# Barandas y panel.
	IndKit.railing(self, Vector3(0, 0, d * 0.36), w * 0.7, dark)
	_control_panel(Vector3(w * 0.44, 1.2, d * 0.2), mats)
	IndKit.cable(self, Vector3(w * 0.44, 1.9, d * 0.2), Vector3(-w * 0.2, 5.4, 0), dark)
	_anim_kind = "press"
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 1.8, 0)
	add_child(_running_particles)

# --- CELDA DE ENSAMBLAJE CON BRAZO ROBÓTICO ---------------------------------
func _build_assembler(w: float, d: float, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var housing: Material = mats["housing"]
	IndKit.box(self, Vector3(w * 0.9, 1.0, d * 0.85), Vector3(0, 0.8, 0), housing)
	# Vallado de la celda con vidrio y postes.
	var glass := IndKit.glass()
	for cx in [-w * 0.43, w * 0.43]:
		IndKit.cyl(self, 0.07, 0.07, 2.6, Vector3(cx, 2.6, -d * 0.4), dark)
	IndKit.box(self, Vector3(w * 0.86, 1.6, 0.06), Vector3(0, 2.2, -d * 0.4), glass)
	for sx in [-1, 1]:
		IndKit.box(self, Vector3(0.06, 1.6, d * 0.75), Vector3(sx * w * 0.43, 2.2, 0), glass)
	# Base del robot.
	IndKit.cyl(self, 0.5, 0.6, 0.6, Vector3(0, 1.6, 0), dark)
	# Brazo robótico multiarticulado (anim).
	_anim_primary = Node3D.new()
	_anim_primary.position = Vector3(0, 1.9, 0)
	add_child(_anim_primary)
	_child_box(_anim_primary, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.15, 0), housing)
	_child_box(_anim_primary, Vector3(0.32, 1.6, 0.32), Vector3(0, 0.95, 0.12), steel)
	_anim_secondary = Node3D.new()
	_anim_secondary.position = Vector3(0, 1.7, 0.12)
	_anim_primary.add_child(_anim_secondary)
	_child_box(_anim_secondary, Vector3(0.28, 1.2, 0.28), Vector3(0, 0.55, 0.3), steel)
	_child_box(_anim_secondary, Vector3(0.34, 0.24, 0.34), Vector3(0, 1.1, 0.48), dark)
	for gx in [-1, 1]:
		_child_box(_anim_secondary, Vector3(0.07, 0.34, 0.12), Vector3(gx * 0.13, 1.28, 0.54), dark)
	# Luz de trabajo cenital + panel.
	IndKit.box(self, Vector3(1.4, 0.12, 0.5), Vector3(0, 3.1, 0), IndKit.emissive(Color(1, 1, 0.85), 1.5))
	_control_panel(Vector3(-w * 0.3, 1.25, d * 0.4), mats)
	_anim_kind = "arm"
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 2.3, 0.3)
	add_child(_running_particles)

func _build_generic(w: float, d: float, mats: Dictionary) -> void:
	IndKit.box(self, Vector3(w * 0.82, 2.2, d * 0.82), Vector3(0, 1.4, 0), mats["housing"])
	IndKit.box(self, Vector3(w * 0.6, 0.4, d * 0.6), Vector3(0, 2.7, 0), mats["steel"])
	_anim_primary = Node3D.new()
	_anim_primary.position = Vector3(0, 2.9, 0)
	add_child(_anim_primary)
	_fan(_anim_primary, 0.5, mats["dark"])
	_anim_kind = "fan"
	_control_panel(Vector3(0, 1.3, d * 0.42), mats)
	_running_particles = _make_steam()
	_running_particles.position = Vector3(0, 3.0, 0)
	add_child(_running_particles)

# --- Detalle / efectos comunes ----------------------------------------------
func _add_industrial_detail(w: float, d: float, mats: Dictionary) -> void:
	var dark: Material = mats["dark"]
	IndKit.bolt_row(self, 5, -w * 0.4, w * 0.4, 0.42, d * 0.49, dark)
	IndKit.hazard_stripe(self, Vector3(w * 0.82, 0.16, 0.05), Vector3(0, 0.58, d * 0.47))
	IndKit.grille(self, 0.7, 0.8, Vector3(-w * 0.47, 1.2, 0), dark)
	IndKit.warning_sign(self, Vector3(-w * 0.44, 0.35, -d * 0.32))

func _add_beacon(w: float, d: float, mats: Dictionary) -> void:
	var hx := w * 0.42
	var hz := d * 0.42
	IndKit.cyl(self, 0.05, 0.06, 0.6, Vector3(hx, 3.3, hz), mats["dark"])
	_status_light = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.22
	lm.height = 0.44
	_status_light.mesh = lm
	_status_light.position = Vector3(hx, 3.75, hz)
	add_child(_status_light)
	_beacon_light = _omni(Vector3(hx, 3.75, hz), Color(0.3, 0.9, 0.4), 6.0, 1.5)
	add_child(_beacon_light)

func _add_effects(w: float, d: float, color: Color) -> void:
	_sparks = _make_sparks(color)
	_sparks.position = Vector3(0, 1.1, d * 0.42)
	add_child(_sparks)
	_damage_smoke = _make_damage_smoke()
	_damage_smoke.position = Vector3(-w * 0.2, 2.4, 0)
	add_child(_damage_smoke)

func _control_panel(pos: Vector3, mats: Dictionary) -> void:
	IndKit.box(self, Vector3(0.7, 0.95, 0.14), pos, mats["dark"])
	IndKit.box(self, Vector3(0.48, 0.4, 0.04), pos + Vector3(0, 0.18, 0.09), IndKit.emissive(Color(0.25, 0.8, 1.0), 1.8))
	for i in range(3):
		var btn := IndKit.emissive(Color(0.9, 0.3, 0.2) if i == 0 else Color(0.3, 0.8, 0.4), 0.8)
		IndKit.cyl(self, 0.05, 0.05, 0.05, pos + Vector3(-0.18 + i * 0.18, -0.2, 0.08), btn).rotation_degrees = Vector3(90, 0, 0)

func _valve(pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.12
	t.outer_radius = 0.22
	mi.mesh = t
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _child_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _fan(parent: Node3D, radius: float, mat: Material) -> void:
	IndKit.cyl(parent, 0.12, 0.12, 0.2, Vector3.ZERO, mat)
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

func _omni(pos: Vector3, color: Color, range_m: float, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	l.shadow_enabled = false
	return l

func _category_color() -> Color:
	match String(def.get("category", "")):
		"processing": return Color(0.72, 0.42, 0.24)
		"manufacturing": return Color(0.34, 0.52, 0.72)
		"power": return Color(0.78, 0.68, 0.22)
		_: return Color(0.52, 0.55, 0.6)

# --- Partículas -------------------------------------------------------------
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
	p.draw_pass_1 = _billboard_dot(0.2, Color(0.9, 0.9, 0.95, 0.28))
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
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.8, 0.3)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.7, 0.2)
	dm.emission_energy_multiplier = 3.0
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
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
	p.draw_pass_1 = _billboard_dot(0.22, Color(0.12, 0.12, 0.13, 0.5))
	return p

func _billboard_dot(radius: float, color: Color) -> SphereMesh:
	var dot := SphereMesh.new()
	dot.radius = radius
	dot.height = radius * 2.0
	var dm := StandardMaterial3D.new()
	dm.albedo_color = color
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	return dot

# --- Estado visual (lo informa la lógica) -----------------------------------
func set_state(state: int) -> void:
	_state = state
	if _status_light == null:
		return
	var c := Color(0.4, 0.4, 0.4)
	match state:
		Machine.State.RUNNING: c = Color(0.2, 0.9, 0.35)
		Machine.State.NO_MATERIALS: c = Color(0.95, 0.75, 0.2)
		Machine.State.BLOCKED: c = Color(0.95, 0.55, 0.15)
		Machine.State.NO_POWER: c = Color(0.9, 0.2, 0.2)
		Machine.State.BROKEN: c = Color(0.9, 0.1, 0.1)
		Machine.State.MAINTENANCE: c = Color(0.2, 0.6, 0.95)
		Machine.State.DISABLED, Machine.State.IDLE: c = Color(0.35, 0.35, 0.38)
	var m := _status_light.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		_status_light.material_override = m
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	if _beacon_light:
		_beacon_light.light_color = c
		_beacon_light.light_energy = 1.8 if state == Machine.State.RUNNING else 0.8
	var running := state == Machine.State.RUNNING
	if _running_particles:
		_running_particles.emitting = running
	if _sparks:
		var cat := String(def.get("category", ""))
		_sparks.emitting = running and (cat == "manufacturing" or cat == "processing")
	if _damage_smoke:
		_damage_smoke.emitting = (state == Machine.State.BROKEN)
	if _glow_light and not running:
		_glow_light.light_energy = 0.6
	if _glow_mat and not running:
		_glow_mat.emission_energy_multiplier = 0.5

func _process(delta: float) -> void:
	var running := _state == Machine.State.RUNNING
	var t := Time.get_ticks_msec() / 1000.0
	match _anim_kind:
		"smelter":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 3.0)
			if _glow_mat:
				_glow_mat.emission_energy_multiplier = (2.2 + 0.9 * sin(t * 4.0)) if running else 0.5
			if _glow_light:
				_glow_light.light_energy = (2.5 + 0.8 * sin(t * 4.0)) if running else 0.6
		"press":
			if _anim_primary:
				var stroke: float = (0.65 * (0.5 - 0.5 * cos(t * 7.0))) if running else 0.0
				_anim_primary.position.y = _ram_base_y - stroke
		"arm":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 1.4)
			if _anim_secondary:
				_anim_secondary.rotation.x = (0.5 * sin(t * 3.0)) if running else 0.15
		"fan":
			if _anim_primary and running:
				_anim_primary.rotate_y(delta * 6.0)
