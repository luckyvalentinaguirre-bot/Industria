extends Node3D
## WorldManager — construye y gestiona el mundo 3D de la fábrica (ETAPA 1).
##
## Responsabilidades:
##   * Configurar el entorno (cielo, niebla, ambiente PBR) y la iluminación.
##   * Generar el terreno base (losa de hormigón de la nave industrial).
##   * Coordinar la cuadrícula de construcción y la cámara.
##   * Avisar al resto del juego cuando el mundo está listo (EventBus.world_ready).
##
## La geometría del terreno y los materiales se generan por código para no
## depender aún de assets 3D definitivos (que llegarán por el pipeline gráfico),
## pero todo queda preparado para reemplazar los placeholders por modelos reales.

const BuildControllerScript := preload("res://scripts/world/build_controller.gd")

@onready var _environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _fill_light: DirectionalLight3D = $FillLight
@onready var _ground: MeshInstance3D = $Ground
@onready var _build_grid: Node3D = $BuildGrid

var _containers: Dictionary = {}
var build_controller: Node3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _lamp_lights: Array = []

func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	_setup_containers()
	_setup_props()
	_setup_build_controller()
	# Ciclo día/noche sincronizado con el reloj del juego.
	EventBus.minute_passed.connect(_update_day_night)
	_update_day_night(GameState.day, GameState.hour, GameState.minute)
	# La cuadrícula se autoconstruye en su propio _ready().
	# Registrar el mundo en GameManager antes de arrancar la partida.
	GameManager.register_world(self, _build_grid, _containers)
	call_deferred("_emit_world_ready")

func _setup_containers() -> void:
	for key in ["machines", "buildings", "conveyors", "workers", "items", "vehicles"]:
		var node := Node3D.new()
		node.name = key.capitalize() + "Root"
		add_child(node)
		_containers[key] = node

func _setup_build_controller() -> void:
	build_controller = BuildControllerScript.new()
	build_controller.name = "BuildController"
	add_child(build_controller)
	# El terreno ampliado incrementa los costos fijos (impuesto de terreno).
	EventBus.day_passed.connect(_on_day_upkeep)

func _on_day_upkeep(_day: int) -> void:
	var level: int = build_controller.expansion_level() if build_controller else 0
	if level > 0:
		GameManager.economy.force_spend(level * 250.0, "misc")

func _emit_world_ready() -> void:
	# Cargar guardado (Continuar/Cargar) o arrancar DESDE CERO (nueva partida).
	if GameManager.pending_load:
		GameManager.save.load_game()
	else:
		_setup_initial_scenario()
	# Vida ambiental: NO al empezar (terreno vacío = arranque desde cero y menos
	# nodos = mejor rendimiento). Aparece cuando la fábrica crece (nivel ≥ 2).
	EventBus.company_level_changed.connect(_on_level_ambient)
	EventBus.world_ready.emit()

var _ambient_level: int = 0
var _ambient_workers: int = 0
func _on_level_ambient(level: int, _name: String) -> void:
	# La fábrica se ve MÁS VIVA a medida que crece (spec §12), pero con tope para
	# no penalizar el rendimiento (spec §24/§25): pocos trabajadores/vehículos.
	if level <= _ambient_level or level < 2:
		return
	if _ambient_level < 2:
		GameManager.vehicles.spawn_ambient()   # carretilla patrullando desde N2
	if level >= 4:
		GameManager.vehicles.spawn_ambient()   # más tránsito en fábricas grandes
	var target: int = clampi(level, 2, 6)       # 2 operarios en N2 … hasta 6 en N6
	if target > _ambient_workers:
		GameManager.workers.spawn_ambient(target - _ambient_workers)
		_ambient_workers = target
	# El PROPIO ESPACIO crece: estructuras diseñadas por nivel (spec §6/§12).
	for lv in range(_ambient_level + 1, level + 1):
		_grow_structures(lv)
	_ambient_level = level

# --- Crecimiento visual del espacio por nivel (composición con intención) ----
var _growth_root: Node3D
var _grown: Dictionary = {}

func _growth_node() -> Node3D:
	if _growth_root == null or not is_instance_valid(_growth_root):
		_growth_root = Node3D.new()
		_growth_root.name = "GrowthProps"
		add_child(_growth_root)
	return _growth_root

func _grow_structures(level: int) -> void:
	if _grown.has(level):
		return
	_grown[level] = true
	var root := _growth_node()
	var branch: String = GameManager.specialization.current() if GameManager.specialization else ""
	match level:
		2:
			# Oficina/administración + primera zona de materiales de tu rama.
			_office(root, Vector3(18, 0, 18))
			_branch_cluster(root, Vector3(14, 0, 16), branch)
		3:
			# Zona de almacenamiento (contenedores / pila propia de la rama).
			if branch == "wood":
				_log_pile(root, Vector3(-18, 0, 18))
			else:
				_container_stack(root, Vector3(-19, 0, 17))
			_branch_cluster(root, Vector3(-14, 0, 14), branch)
		4:
			# Estructuras grandes: torre-grúa y más materiales.
			_gantry_tower(root, Vector3(18, 0, -17))
			_branch_cluster(root, Vector3(14, 0, -14), branch)
		5:
			# Complejo consolidado: más volumen y una zona pesada.
			_container_stack(root, Vector3(-19, 0, -18))
			_branch_cluster(root, Vector3(-14, 0, -14), branch)

## Pequeña oficina con ventanas iluminadas (zona administrativa, spec §7).
func _office(parent: Node3D, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var wall := _simple(Color(0.5, 0.52, 0.55), 0.8, 0.1)
	var roof := _simple(Color(0.3, 0.32, 0.35), 0.7, 0.2)
	_pbox(node, Vector3(5, 3, 4), Vector3(0, 1.5, 0), wall)
	_pbox(node, Vector3(5.4, 0.3, 4.4), Vector3(0, 3.15, 0), roof)
	_pbox(node, Vector3(1.2, 2.0, 0.1), Vector3(0, 1.0, 2.05), roof)           # puerta
	var win := IndKit.emissive(Color(0.6, 0.8, 1.0), 0.7)
	_pbox(node, Vector3(1.0, 1.0, 0.08), Vector3(-1.5, 1.9, 2.06), win)
	_pbox(node, Vector3(1.0, 1.0, 0.08), Vector3(1.5, 1.9, 2.06), win)
	# Cartel de la empresa.
	_pbox(node, Vector3(3.0, 0.6, 0.1), Vector3(0, 3.6, 1.5), IndKit.emissive(Color(0.92, 0.63, 0.20), 0.9))

## Pila de troncos (identidad maderera).
func _log_pile(parent: Node3D, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var wood := IndKit.housing(Color(0.55, 0.38, 0.2))
	for row in range(3):
		var n := 4 - row
		for i in range(n):
			var log := _pcyl(node, 0.35, 0.35, 5.0, Vector3(-0.75 * n * 0.5 + i * 0.75, 0.4 + row * 0.65, 0), wood)
			log.rotation_degrees = Vector3(0, 0, 90)

## Cluster de materiales con identidad de cada rama (spec §7/§8).
func _branch_cluster(parent: Node3D, base: Vector3, branch: String) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	match branch:
		"wood":
			var pallet := IndKit.housing(Color(0.55, 0.38, 0.2))
			for i in range(3):
				_pbox(node, Vector3(1.4, 0.2, 1.2), Vector3(i * 0.2, 0.15 + i * 0.25, i * 0.15), pallet)
		"metal":
			var steel := IndKit.steel()
			for sx in [-1, 1]:
				_pcyl(node, 0.7, 0.7, 1.2, Vector3(sx * 0.9, 0.6, 0), steel).rotation_degrees = Vector3(90, 0, 0)
			_pbox(node, Vector3(2.4, 1.6, 1.0), Vector3(0, 0.8, -1.6), IndKit.housing(Color(0.4, 0.42, 0.46)))
		"construction":
			var block := IndKit.housing(Color(0.6, 0.58, 0.54))
			for r in range(2):
				for i in range(3):
					_pbox(node, Vector3(0.9, 0.45, 0.9), Vector3(i * 1.0, 0.25 + r * 0.5, 0), block)
		"energy":
			var dark := IndKit.dark_metal()
			for i in range(2):
				_pcyl(node, 0.6, 0.6, 0.7, Vector3(i * 1.4, 0.35, 0), dark)   # bobinas de cable
			_pbox(node, Vector3(1.2, 1.4, 1.0), Vector3(0.7, 0.7, -1.4), IndKit.housing(Color(0.7, 0.6, 0.2)))
		_:
			var crate := IndKit.housing(Color(0.45, 0.33, 0.19))
			for i in range(4):
				var s := 0.9
				_pbox(node, Vector3(s, s, s), Vector3((i % 2) * 1.0, 0.45 + (i / 2) * 0.9, (i / 2) * 0.2), crate)

## Arranque DESDE CERO (spec §2, §3): terreno vacío, sin máquinas ni edificios.
## Sólo un pequeño lote de chatarra para que el jugador fabrique su primer
## producto en el banco de trabajo y consiga sus primeros ingresos (etapa manual).
func _setup_initial_scenario() -> void:
	GameManager.storage.deposit("scrap", 24)

## Coloca una máquina del escenario y ocupa su área en el grid.
func _place_machine(id: String, origin: Vector2i) -> Machine:
	var m: Machine = GameManager.machines.create_machine(id, origin)
	GameManager.grid.occupy_area(m.grid_origin, m.grid_size, m.uid)
	return m

## Coloca un edificio del escenario y ocupa su área en el grid.
func _place_building(id: String, origin: Vector2i) -> Building:
	var b: Building = GameManager.buildings.create_building(id, origin)
	GameManager.grid.occupy_area(b.grid_origin, b.grid_size, b.uid)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_grid"):
		if _build_grid and _build_grid.has_method("toggle_visibility"):
			_build_grid.toggle_visibility()

# --- Entorno ----------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.42, 0.62)
	sky_mat.sky_horizon_color = Color(0.62, 0.68, 0.74)
	sky_mat.ground_bottom_color = Color(0.16, 0.17, 0.19)
	sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.55)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	_sky_mat = sky_mat

	# Iluminación ambiental basada en el cielo (PBR).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0

	# Niebla sutil para dar profundidad industrial.
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.58, 0.62)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.2

	# Realce visual optimizado para gama media.
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.2
	env.ssao_detail = 1.0
	env.ssil_enabled = true
	env.ssil_intensity = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08

	_environment.environment = env
	_env = env

# --- Ciclo día / noche ------------------------------------------------------
func _update_day_night(_day: int, hour: int, minute: int) -> void:
	if not _env:
		return
	var t := float(hour) + float(minute) / 60.0
	var day_amt := 0.0
	if t >= 5.5 and t <= 18.5:
		day_amt = clampf(sin(PI * (t - 5.5) / 13.0), 0.0, 1.0)

	# Sol: elevación y azimut a lo largo del día.
	_sun.rotation_degrees = Vector3(-8.0 - day_amt * 72.0, -46.0 + (t - 6.0) / 12.0 * 80.0, 0)
	_sun.light_energy = lerpf(0.04, 1.6, day_amt)
	_sun.light_color = Color(0.4, 0.45, 0.7).lerp(Color(1.0, 0.95, 0.85), day_amt)

	_env.ambient_light_energy = lerpf(0.12, 1.0, day_amt)
	_env.fog_light_color = Color(0.09, 0.11, 0.2).lerp(Color(0.55, 0.58, 0.62), day_amt)
	if _sky_mat:
		_sky_mat.sky_top_color = Color(0.03, 0.04, 0.10).lerp(Color(0.28, 0.42, 0.62), day_amt)
		_sky_mat.sky_horizon_color = Color(0.09, 0.10, 0.15).lerp(Color(0.62, 0.68, 0.74), day_amt)

	# Farolas encendidas al anochecer / de noche.
	var lamps_on: bool = day_amt < 0.28
	for l in _lamp_lights:
		if is_instance_valid(l):
			l.light_energy = 2.6 if lamps_on else 0.0

# --- Iluminación ------------------------------------------------------------

func _setup_lighting() -> void:
	# Sol principal con sombras suaves y contacto.
	_sun.rotation_degrees = Vector3(-52, -46, 0)
	_sun.light_energy = 1.5
	_sun.light_color = Color(1.0, 0.95, 0.85)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Distancia de sombras acotada a la escala de la fábrica (rendimiento, §20).
	_sun.directional_shadow_max_distance = 120.0
	_sun.shadow_blur = 1.2
	_sun.light_bake_mode = Light3D.BAKE_DISABLED

	# Luz de relleno fría, sin sombras, para suavizar contrastes.
	_fill_light.rotation_degrees = Vector3(-35, 140, 0)
	_fill_light.light_energy = 0.4
	_fill_light.light_color = Color(0.68, 0.76, 0.95)
	_fill_light.shadow_enabled = false

# --- Terreno ----------------------------------------------------------------

func _setup_ground() -> void:
	var size := Vector2(
		GameState.grid_size.x * GameState.CELL_SIZE,
		GameState.grid_size.y * GameState.CELL_SIZE
	)
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	_ground.mesh = plane
	_ground.material_override = _make_ground_material()

	# Plinto: la nave se asienta sobre una losa de hormigón con canto visible.
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var pbm := BoxMesh.new()
	pbm.size = Vector3(size.x + 1.5, 0.6, size.y + 1.5)
	plinth.mesh = pbm
	# Cara superior a y=-0.1 (bajo el plano del suelo y=0) para EVITAR z-fighting
	# coplanar que producía líneas blancas al mover la cámara.
	plinth.position = Vector3(0, -0.4, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.2, 0.22)
	pmat.roughness = 0.95
	_ground.add_child(plinth)

	# Colisión del suelo para el raycasting de construcción (ETAPA 2).
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 0.2, size.y)
	col.shape = shape
	col.position = Vector3(0, -0.1, 0)
	body.add_child(col)
	_ground.add_child(body)

# --- Decoración de entorno / atmósfera --------------------------------------
func _setup_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	var ext: float = GameState.grid_size.x * GameState.CELL_SIZE * 0.5   # 40

	# Terreno lejano (asfalto oscuro) para que el horizonte no flote.
	var far := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(ext * 8.0, ext * 8.0)
	far.mesh = fp
	far.position = Vector3(0, -0.85, 0)   # bajo el plinto, sin intersecciones/z-fighting
	far.material_override = _simple(Color(0.17, 0.18, 0.2), 0.95, 0.0)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(far)

	var mat_wall := _simple(Color(0.28, 0.29, 0.31), 0.9, 0.0)
	var mat_metal := _simple(Color(0.2, 0.21, 0.23), 0.5, 0.8)

	# Muro perimetral (4 lados) con zócalo y remate metálico.
	for side in range(4):
		var horizontal := side < 2
		var sign := 1.0 if (side % 2 == 0) else -1.0
		var wall := _pbox(props, Vector3(ext * 2.0 if horizontal else 0.4, 2.6, 0.4 if horizontal else ext * 2.0),
			Vector3(0 if horizontal else sign * ext, 1.3, sign * ext if horizontal else 0), mat_wall)
		var cap := _pbox(props, Vector3(ext * 2.0 if horizontal else 0.5, 0.25, 0.5 if horizontal else ext * 2.0),
			Vector3(0 if horizontal else sign * ext, 2.65, sign * ext if horizontal else 0), mat_metal)

	# Farolas industriales con luz real (sin sombra, para rendimiento).
	var lamp_positions := [
		Vector3(-ext + 4, 0, -ext + 4), Vector3(ext - 4, 0, -ext + 4),
		Vector3(-ext + 4, 0, ext - 4), Vector3(ext - 4, 0, ext - 4),
		Vector3(0, 0, -ext + 4), Vector3(0, 0, ext - 4),
	]
	for p in lamp_positions:
		_light_pole(props, p, mat_metal)

	# (Se retiraron los grupos ALEATORIOS de cajas/barriles: relleno sin intención.
	#  La ambientación con propósito la aportan _setup_ambient y el crecimiento
	#  por nivel, spec §25/§47.)

	# Sonda de reflejos para dar brillo realista al metal.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(ext * 2.2, 30, ext * 2.2)
	probe.origin_offset = Vector3(0, -10, 0)
	probe.position = Vector3(0, 12, 0)
	probe.max_distance = 220.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	props.add_child(probe)

	# (Se retiró el polvo ambiental de partículas esféricas — las "bolitas"
	#  flotantes de relleno, spec §25.)

	# Señalización y líneas de seguridad en el suelo.
	_setup_floor_markings(props, ext)

	# Ambientación industrial diseñada (infraestructura con intención).
	_setup_ambient(props, ext)
	# Carretera de acceso + línea eléctrica que alimenta la fábrica.
	_setup_infrastructure(props, ext)

	# Horizonte industrial de fondo (más allá del muro) para dar profundidad.
	_setup_skyline(props, ext)

# --- Ambientación industrial (Etapa 3): infraestructura con propósito --------
func _setup_ambient(parent: Node3D, ext: float) -> void:
	# Parque de tanques de almacenamiento en una esquina.
	_tank_farm(parent, Vector3(ext - 12, 0, -ext + 12))
	# Rack de tuberías elevado a lo largo del borde trasero.
	_pipe_rack(parent, Vector3(0, 0, -ext + 3), ext * 1.4)
	# Apilado de contenedores marítimos en otra esquina.
	_container_stack(parent, Vector3(-ext + 12, 0, ext - 12))
	# Torre/estructura metálica junto al parque de tanques.
	_gantry_tower(parent, Vector3(ext - 6, 0, -ext + 22))
	# Bolardos de seguridad amarillos a lo largo del carril de camiones.
	var bollard := IndKit.emissive(Color(0.85, 0.72, 0.1), 0.4)
	for i in range(10):
		var x := lerpf(-ext + 4, -2, float(i) / 9.0)
		IndKit.cyl(parent, 0.14, 0.18, 1.0, Vector3(x, 0.5, 3.6), bollard)

func _tank_farm(parent: Node3D, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var steel := IndKit.steel()
	var dark := IndKit.dark_metal()
	# Dique de contención de hormigón.
	IndKit.box(node, Vector3(16, 0.6, 12), Vector3(0, 0.3, 0), IndKit.concrete())
	var positions := [Vector3(-4.5, 0, -2), Vector3(0.5, 0, 2), Vector3(5, 0, -2.5)]
	var radii := [2.5, 3.0, 2.2]
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		var r: float = radii[i]
		var h := r * 3.0
		IndKit.cyl(node, r, r, h, p + Vector3(0, h * 0.5 + 0.6, 0), steel)
		# Aros de refuerzo.
		for k in range(3):
			IndKit.cyl(node, r * 1.03, r * 1.03, 0.15, p + Vector3(0, 1.2 + k * (h / 3.0) + 0.6, 0), dark)
		# Tapa abombada.
		var dome := IndKit.cyl(node, r * 0.2, r, r * 0.5, p + Vector3(0, h + 0.6 + r * 0.25, 0), steel)
		# Escalera.
		IndKit.ladder(node, p + Vector3(r, 0.6, 0), h, dark)
	# Tuberías que conectan los tanques.
	IndKit.pipe(node, Vector3(-4.5, 1.5, -2), Vector3(0.5, 1.5, 2), 0.2, dark)
	IndKit.pipe(node, Vector3(0.5, 1.5, 2), Vector3(5, 1.5, -2.5), 0.2, dark)

func _pipe_rack(parent: Node3D, base: Vector3, length: float) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var dark := IndKit.dark_metal()
	var steel := IndKit.steel()
	var supports := int(length / 6.0)
	for i in range(supports + 1):
		var x := lerpf(-length * 0.5, length * 0.5, float(i) / float(supports))
		# Pórtico de soporte.
		for sx in [-1, 1]:
			IndKit.cyl(node, 0.15, 0.18, 4.0, Vector3(x + sx * 1.2, 2.0, 0), dark)
		IndKit.box(node, Vector3(3.2, 0.2, 0.3), Vector3(x, 3.6, 0), dark)
		IndKit.box(node, Vector3(3.2, 0.2, 0.3), Vector3(x, 2.6, 0), dark)
	# Tuberías corriendo por el rack.
	for pz in [-0.7, 0.0, 0.7]:
		IndKit.cyl(node, 0.22, 0.22, length, Vector3(0, 3.7, pz), steel).rotation_degrees = Vector3(0, 0, 90)
	IndKit.cyl(node, 0.3, 0.3, length, Vector3(0, 2.7, 0), dark).rotation_degrees = Vector3(0, 0, 90)

func _container_stack(parent: Node3D, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var colors := [Color(0.6, 0.25, 0.2), Color(0.2, 0.35, 0.55), Color(0.3, 0.5, 0.35), Color(0.6, 0.5, 0.2)]
	var layout := [
		[Vector3(0, 1.3, 0), 0], [Vector3(0, 1.3, 2.7), 1], [Vector3(6.4, 1.3, 0), 2],
		[Vector3(0, 3.9, 0), 3], [Vector3(6.4, 3.9, 0), 0], [Vector3(0, 3.9, 2.7), 2],
	]
	for entry in layout:
		var pos: Vector3 = entry[0]
		var mat := IndKit.housing(colors[int(entry[1])])
		IndKit.box(node, Vector3(6.0, 2.5, 2.4), pos, mat)
		# Nervaduras del contenedor.
		for r in range(5):
			var lx := lerpf(-2.7, 2.7, float(r) / 4.0)
			IndKit.box(node, Vector3(0.1, 2.5, 2.42), pos + Vector3(lx, 0, 0), IndKit.dark_metal())

func _gantry_tower(parent: Node3D, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var dark := IndKit.dark_metal()
	var h := 12.0
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			IndKit.cyl(node, 0.15, 0.2, h, Vector3(sx * 1.5, h * 0.5, sz * 1.5), dark)
	# Arriostramientos horizontales.
	for k in range(4):
		var y := 2.5 + k * 2.8
		IndKit.box(node, Vector3(3.0, 0.12, 0.12), Vector3(0, y, 1.5), dark)
		IndKit.box(node, Vector3(3.0, 0.12, 0.12), Vector3(0, y, -1.5), dark)
		IndKit.box(node, Vector3(0.12, 0.12, 3.0), Vector3(1.5, y, 0), dark)
		IndKit.box(node, Vector3(0.12, 0.12, 3.0), Vector3(-1.5, y, 0), dark)
	# Plataforma superior con baranda.
	IndKit.platform(node, Vector2(3.6, 3.6), Vector3(0, h, 0), IndKit.steel())
	IndKit.railing(node, Vector3(0, h, 1.8), 3.6, dark)
	# Luz de advertencia roja en la cima.
	var warn := IndKit.emissive(Color(0.95, 0.15, 0.1), 2.5)
	IndKit.cyl(node, 0.25, 0.25, 0.4, Vector3(0, h + 0.4, 0), warn)

func _setup_infrastructure(parent: Node3D, ext: float) -> void:
	# Carretera de asfalto desde el portón oeste hasta el centro (zona de carga).
	var asphalt := _simple(Color(0.11, 0.11, 0.12), 0.85, 0.0)
	var road := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(ext, 0.05, 5.5)
	road.mesh = rbm
	road.position = Vector3(-ext * 0.5, 0.03, 6)
	road.material_override = asphalt
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(road)
	# Línea discontinua central de la carretera.
	var line := _simple(Color(0.8, 0.75, 0.2), 0.7, 0.0)
	for i in range(int(ext / 3.0)):
		IndKit.box(parent, Vector3(1.2, 0.03, 0.18), Vector3(-ext + 2 + i * 3.0, 0.06, 6), line)

	# Placa metálica de la zona de carga (superficie distinta) junto al frente.
	var plate := _simple(Color(0.3, 0.31, 0.34), 0.5, 0.7)
	IndKit.box(parent, Vector3(10, 0.06, 8), Vector3(-6, 0.05, 12), plate)

	# Línea eléctrica: torres de celosía con cables que cruzan hacia la fábrica.
	var prev_top := Vector3.ZERO
	var have_prev := false
	for i in range(4):
		var z := lerpf(-ext + 6, ext - 6, float(i) / 3.0)
		var base := Vector3(-ext + 9, 0, z)
		var top := _pylon(parent, base)
		if have_prev:
			# Cables entre torres (dos conductores).
			IndKit.cable(parent, prev_top + Vector3(0, 0, -0.9), top + Vector3(0, 0, -0.9), IndKit.dark_metal())
			IndKit.cable(parent, prev_top + Vector3(0, 0, 0.9), top + Vector3(0, 0, 0.9), IndKit.dark_metal())
		prev_top = top
		have_prev = true
	# Bajante de servicio desde la torre central hacia la subestación de la fábrica.
	IndKit.cable(parent, Vector3(-ext + 9, 8.5, 0), Vector3(-8, 3.0, 0), IndKit.dark_metal())

func _pylon(parent: Node3D, base: Vector3) -> Vector3:
	var node := Node3D.new()
	node.position = base
	parent.add_child(node)
	var dark := IndKit.dark_metal()
	var h := 10.0
	# Cuatro patas convergentes.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := IndKit.cyl(node, 0.08, 0.14, h, Vector3(sx * 1.2, h * 0.5, sz * 1.2), dark)
			leg.rotation_degrees = Vector3(sz * 6.0, 0, -sx * 6.0)
	# Arriostramientos.
	for k in range(4):
		var y := 2.0 + k * 2.2
		var s: float = lerpf(1.1, 0.5, float(k) / 3.0)
		IndKit.box(node, Vector3(s * 2.0, 0.08, 0.08), Vector3(0, y, s * 1.0), dark)
		IndKit.box(node, Vector3(s * 2.0, 0.08, 0.08), Vector3(0, y, -s * 1.0), dark)
		IndKit.box(node, Vector3(0.08, 0.08, s * 2.0), Vector3(s * 1.0, y, 0), dark)
		IndKit.box(node, Vector3(0.08, 0.08, s * 2.0), Vector3(-s * 1.0, y, 0), dark)
	# Cruceta con aisladores.
	IndKit.box(node, Vector3(0.1, 0.1, 3.2), Vector3(0, h, 0), dark)
	for sz in [-1, 1]:
		IndKit.cyl(node, 0.05, 0.05, 0.4, Vector3(0, h - 0.3, sz * 0.9), IndKit.emissive(Color(0.8, 0.78, 0.7), 0.2))
	return base + Vector3(0, h, 0)

func _setup_skyline(parent: Node3D, ext: float) -> void:
	var mat_far := _simple(Color(0.22, 0.24, 0.3), 0.9, 0.1)
	var mat_stack := _simple(Color(0.28, 0.26, 0.27), 0.9, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var count := 18
	for i in range(count):
		var ang := TAU * i / count + rng.randf_range(-0.12, 0.12)
		var r := ext * rng.randf_range(1.5, 2.5)
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var kind := rng.randi() % 3
		if kind == 0:
			# Nave/edificio.
			var h := rng.randf_range(8.0, 16.0)
			_pbox(parent, Vector3(rng.randf_range(6, 12), h, rng.randf_range(6, 12)), pos + Vector3(0, h * 0.5, 0), mat_far)
		elif kind == 1:
			# Chimenea alta con humo.
			var h2 := rng.randf_range(14.0, 24.0)
			_pcyl(parent, 0.8, 1.3, h2, pos + Vector3(0, h2 * 0.5, 0), mat_stack)
			if rng.randf() < 0.6:
				parent.add_child(_skyline_smoke(pos + Vector3(0, h2, 0)))
		else:
			# Torre de refrigeración (dos troncos de cono).
			var h3 := rng.randf_range(10.0, 16.0)
			_pcyl(parent, 2.2, 3.2, h3 * 0.6, pos + Vector3(0, h3 * 0.3, 0), mat_far)
			_pcyl(parent, 3.0, 2.2, h3 * 0.4, pos + Vector3(0, h3 * 0.8, 0), mat_far)

func _skyline_smoke(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 8
	p.lifetime = 6.0
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.4, 1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0.3, 0.2, 0)
	mat.scale_min = 1.5
	mat.scale_max = 4.0
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 1.0
	dot.height = 2.0
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.5, 0.5, 0.55, 0.18)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _setup_floor_markings(parent: Node3D, ext: float) -> void:
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.85, 0.72, 0.1)
	yellow.roughness = 0.7
	yellow.emission_enabled = true
	yellow.emission = Color(0.6, 0.5, 0.05)
	yellow.emission_energy_multiplier = 0.3

	# (Se retiraron las líneas de carril BLANCAS: quads finos a ras del suelo que
	#  parpadeaban como "líneas blancas" al mover la cámara — spec §27.)
	# Flechas/franjas de peligro cerca del portón oeste.
	for i in range(5):
		var stripe := _pbox(parent, Vector3(0.5, 0.03, 1.6), Vector3(-ext + 2 + i * 0.9, 0.04, 6), yellow)
		stripe.rotation.y = deg_to_rad(35)
	# Perímetro de la zona de carga (rectángulo amarillo).
	var pad := Vector3(-6, 0, 11)
	_pbox(parent, Vector3(6.2, 0.03, 0.2), pad + Vector3(0, 0.04, -2.5), yellow)
	_pbox(parent, Vector3(6.2, 0.03, 0.2), pad + Vector3(0, 0.04, 2.5), yellow)
	_pbox(parent, Vector3(0.2, 0.03, 5.2), pad + Vector3(-3, 0.04, 0), yellow)
	_pbox(parent, Vector3(0.2, 0.03, 5.2), pad + Vector3(3, 0.04, 0), yellow)

	# Señales de advertencia (poste + placa triangular emisiva).
	for sign_pos in [Vector3(-2, 0, 4), Vector3(8, 0, 4)]:
		_pcyl(parent, 0.06, 0.06, 2.2, sign_pos + Vector3(0, 1.1, 0), _simple(Color(0.5, 0.5, 0.55), 0.5, 0.7))
		var plate := _simple(Color(0.9, 0.75, 0.1), 0.5, 0.0)
		plate.emission_enabled = true
		plate.emission = Color(0.8, 0.6, 0.05)
		plate.emission_energy_multiplier = 0.6
		var s := _pbox(parent, Vector3(0.7, 0.7, 0.05), sign_pos + Vector3(0, 2.3, 0), plate)
		s.rotation.z = deg_to_rad(45)

func _light_pole(parent: Node3D, base: Vector3, mat: Material) -> void:
	var pole := _pcyl(parent, 0.12, 0.14, 7.0, base + Vector3(0, 3.5, 0), mat)
	var arm := _pbox(parent, Vector3(0.12, 0.12, 1.4), base + Vector3(0, 6.8, 0.6), mat)
	# Lámpara emisiva.
	var lampmat := StandardMaterial3D.new()
	lampmat.albedo_color = Color(1.0, 0.95, 0.8)
	lampmat.emission_enabled = true
	lampmat.emission = Color(1.0, 0.92, 0.7)
	lampmat.emission_energy_multiplier = 3.0
	var head := _pbox(parent, Vector3(0.5, 0.2, 0.5), base + Vector3(0, 6.7, 1.2), lampmat)
	var light := OmniLight3D.new()
	light.position = base + Vector3(0, 6.5, 1.2)
	light.light_energy = 2.5
	light.omni_range = 22.0
	light.light_color = Color(1.0, 0.93, 0.78)
	light.shadow_enabled = false
	parent.add_child(light)
	_lamp_lights.append(light)

func _make_dust(ext: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 8.0
	p.position = Vector3(0, 6, 0)
	p.visibility_aabb = AABB(Vector3(-ext, -2, -ext), Vector3(ext * 2, 20, ext * 2))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(ext, 8, ext)
	mat.direction = Vector3(0.2, -0.1, 0)
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.4
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.9, 0.9, 0.85, 0.12)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material = dm
	p.draw_pass_1 = dot
	return p

func _simple(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func _pbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _pcyl(parent: Node3D, tr: float, br: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tr
	cm.bottom_radius = br
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _make_ground_material() -> ShaderMaterial:
	# Hormigón industrial procedural: manchas, juntas de losa y desgaste.
	# Placeholder de alta calidad, sustituible por textura PBR real.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform float slab = 8.0;      // metros por losa
uniform vec3 base_color : source_color = vec3(0.30, 0.31, 0.33);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;
	// Manchas de hormigón (varias frecuencias).
	float n = noise(wp * 0.15) * 0.6 + noise(wp * 0.6) * 0.3 + noise(wp * 2.5) * 0.1;
	// Variación tonal de zonas (grandes losas de distinto tono).
	float zone = noise(wp * 0.05 + 3.0);
	vec3 col = base_color * (0.78 + n * 0.42 + zone * 0.12);
	float rough = 0.9 - n * 0.15;
	// Juntas oscuras entre losas.
	vec2 g = abs(fract(wp / slab) - 0.5);
	float joint = smoothstep(0.45, 0.5, max(g.x, g.y));
	col = mix(col, base_color * 0.5, joint * 0.75);
	// Manchas de aceite (blotches oscuros y algo brillantes).
	float oil = smoothstep(0.62, 0.82, noise(wp * 0.25 + 7.0)) * smoothstep(0.5, 0.75, noise(wp * 0.8));
	col = mix(col, vec3(0.05, 0.05, 0.06), oil * 0.7);
	rough = mix(rough, 0.35, oil * 0.7);
	// Grietas sutiles (líneas oscuras finas).
	float cr = noise(wp * 0.9 + 20.0);
	float crack = smoothstep(0.48, 0.5, cr) * smoothstep(0.52, 0.5, cr);
	col = mix(col, base_color * 0.4, clamp(crack * 3.0, 0.0, 0.6));
	// Óxido/suciedad tenue.
	float rust = smoothstep(0.6, 0.9, noise(wp * 0.4 + 10.0));
	col = mix(col, vec3(0.32, 0.24, 0.19), rust * 0.15);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("slab", 8.0)
	mat.set_shader_parameter("base_color", Color(0.30, 0.31, 0.33))
	return mat
