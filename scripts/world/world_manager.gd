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

@onready var _environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _fill_light: DirectionalLight3D = $FillLight
@onready var _ground: MeshInstance3D = $Ground
@onready var _build_grid: Node3D = $BuildGrid

func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	# La cuadrícula se autoconstruye en su propio _ready().
	# Notificamos que el mundo está listo (arranca la partida vía GameManager).
	call_deferred("_emit_world_ready")

func _emit_world_ready() -> void:
	EventBus.world_ready.emit()

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
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	_environment.environment = env

# --- Iluminación ------------------------------------------------------------

func _setup_lighting() -> void:
	# Sol principal con sombras.
	_sun.rotation_degrees = Vector3(-52, -46, 0)
	_sun.light_energy = 1.35
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 160.0

	# Luz de relleno fría, sin sombras, para suavizar contrastes.
	_fill_light.rotation_degrees = Vector3(-35, 140, 0)
	_fill_light.light_energy = 0.35
	_fill_light.light_color = Color(0.7, 0.78, 0.95)
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

func _make_ground_material() -> StandardMaterial3D:
	# Placeholder PBR de hormigón industrial. Se sustituirá por textura real.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.33)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.metallic_specular = 0.15
	# UV escalado para insinuar losas de la nave.
	mat.uv1_scale = Vector3(GameState.grid_size.x * 0.5, GameState.grid_size.y * 0.5, 1.0)
	return mat
