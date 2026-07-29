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
	# Escenario inicial: una fábrica deteriorada (spec §26).
	if not GameManager.save.has_save():
		_setup_initial_scenario()
	EventBus.world_ready.emit()

## Fábrica deteriorada de partida: un almacén y una fundición vieja averiada.
func _setup_initial_scenario() -> void:
	# Almacén central para almacenar materia prima y productos.
	var store: Building = GameManager.buildings.create_building("small_storage", Vector2i(16, 22))
	GameManager.grid.occupy_area(store.grid_origin, store.grid_size, store.uid)

	# Una fundición vieja (deteriorada) que el jugador deberá reparar.
	var smelter: Machine = GameManager.machines.create_machine("smelter", Vector2i(20, 20))
	GameManager.grid.occupy_area(smelter.grid_origin, smelter.grid_size, smelter.uid)
	smelter.set_condition(35.0)

	# Algo de materia prima inicial para empezar a producir.
	GameManager.storage.deposit("iron_ore", 60)
	GameManager.storage.deposit("fuel", 40)

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
	_sun.directional_shadow_max_distance = 180.0
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

	var mat_wall := _simple(Color(0.28, 0.29, 0.31), 0.9, 0.0)
	var mat_metal := _simple(Color(0.2, 0.21, 0.23), 0.5, 0.8)
	var mat_crate := _simple(Color(0.45, 0.33, 0.19), 0.8, 0.0)
	var mat_barrel := _simple(Color(0.2, 0.45, 0.55), 0.5, 0.4)
	var mat_barrel2 := _simple(Color(0.6, 0.4, 0.15), 0.5, 0.4)

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

	# Grupos de props (cajas y barriles) repartidos por el perímetro.
	var clusters := [
		Vector3(-ext + 6, 0, -6), Vector3(ext - 6, 0, 8),
		Vector3(-8, 0, ext - 6), Vector3(10, 0, -ext + 6),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for c in clusters:
		for i in range(4):
			var off := Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			if rng.randf() < 0.5:
				var s := rng.randf_range(0.8, 1.3)
				var crate := _pbox(props, Vector3(s, s, s), c + off + Vector3(0, s * 0.5, 0), mat_crate)
				crate.rotation.y = rng.randf_range(0, TAU)
			else:
				var bm := mat_barrel if rng.randf() < 0.5 else mat_barrel2
				_pcyl(props, 0.35, 0.35, 1.1, c + off + Vector3(0, 0.55, 0), bm)

	# Sonda de reflejos para dar brillo realista al metal.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(ext * 2.2, 30, ext * 2.2)
	probe.origin_offset = Vector3(0, -10, 0)
	probe.position = Vector3(0, 12, 0)
	probe.max_distance = 220.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	props.add_child(probe)

	# Polvo ambiental muy sutil sobre la fábrica.
	props.add_child(_make_dust(ext))

	# Señalización y líneas de seguridad en el suelo.
	_setup_floor_markings(props, ext)

func _setup_floor_markings(parent: Node3D, ext: float) -> void:
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.85, 0.72, 0.1)
	yellow.roughness = 0.7
	yellow.emission_enabled = true
	yellow.emission = Color(0.6, 0.5, 0.05)
	yellow.emission_energy_multiplier = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.8, 0.8, 0.82)
	white.roughness = 0.7

	# Carril de circulación de camiones (dos líneas paralelas hasta el centro).
	for lz in [5.0, 7.0]:
		_pbox(parent, Vector3(ext, 0.03, 0.2), Vector3(-ext * 0.5, 0.04, lz), white)
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
	p.amount = 60
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
	vec3 col = base_color * (0.82 + n * 0.4);
	// Juntas oscuras entre losas.
	vec2 g = abs(fract(wp / slab) - 0.5);
	float joint = smoothstep(0.46, 0.5, max(g.x, g.y));
	col = mix(col, base_color * 0.55, joint * 0.7);
	// Óxido/suciedad tenue.
	float rust = smoothstep(0.6, 0.9, noise(wp * 0.4 + 10.0));
	col = mix(col, vec3(0.32, 0.24, 0.19), rust * 0.15);
	ALBEDO = col;
	ROUGHNESS = 0.9 - n * 0.15;
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("slab", 8.0)
	mat.set_shader_parameter("base_color", Color(0.30, 0.31, 0.33))
	return mat
