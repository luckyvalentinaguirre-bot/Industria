extends Node3D
## BuildGrid — cuadrícula 3D de construcción de la fábrica.
##
## Responsable de:
##   * Mantener el modelo lógico de celdas (libres / ocupadas).
##   * Convertir entre coordenadas de mundo y coordenadas de celda.
##   * Dibujar la cuadrícula visual sobre el terreno mediante un shader
##     (un único quad = coste de dibujo mínimo, sin miles de nodos).
##
## En la ETAPA 1 sólo se establecen la base geométrica y la visualización.
## El sistema de colocación (ETAPA 2) consumirá occupy_cell() / is_area_free().
##
## Nota de estructura: este script vive en scripts/world/ por pertenecer al
## mundo/terreno. No altera la estructura de carpetas existente.

const CELL_SIZE := 2.0  # metros por celda (coincide con GameState.CELL_SIZE)

@export var grid_size: Vector2i = Vector2i(40, 40)
@export var line_color: Color = Color(0.35, 0.75, 0.85, 0.35)
@export var major_line_color: Color = Color(0.45, 0.9, 1.0, 0.55)

var _occupied: Dictionary = {}          # Vector2i -> bool
var _mesh_instance: MeshInstance3D
var _visible_grid: bool = true

func _ready() -> void:
	grid_size = GameState.grid_size
	_build_visual()
	EventBus.grid_visibility_changed.connect(_on_grid_visibility_changed)

# --- Coordenadas ------------------------------------------------------------

## Centro del mundo alineado para que la fábrica quede centrada en el origen.
func _grid_origin() -> Vector3:
	return Vector3(-grid_size.x * CELL_SIZE * 0.5, 0.0, -grid_size.y * CELL_SIZE * 0.5)

## Convierte una posición de mundo en coordenada de celda (Vector2i).
func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := world_pos - _grid_origin()
	return Vector2i(int(floor(local.x / CELL_SIZE)), int(floor(local.z / CELL_SIZE)))

## Devuelve el centro en mundo de una celda dada.
func cell_to_world(cell: Vector2i) -> Vector3:
	var origin := _grid_origin()
	return origin + Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)

## ¿La celda está dentro de los límites de la fábrica?
func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y

# --- Ocupación (base para ETAPA 2) -----------------------------------------

func is_cell_free(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not _occupied.has(cell)

## ¿Está libre un área rectangular de tamaño `size` con esquina en `origin`?
func is_area_free(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			if not is_cell_free(origin + Vector2i(x, y)):
				return false
	return true

func occupy_area(origin: Vector2i, size: Vector2i, owner_id: int) -> void:
	for x in range(size.x):
		for y in range(size.y):
			_occupied[origin + Vector2i(x, y)] = owner_id

func free_area(origin: Vector2i, size: Vector2i) -> void:
	for x in range(size.x):
		for y in range(size.y):
			_occupied.erase(origin + Vector2i(x, y))

# --- Visualización ----------------------------------------------------------

func _build_visual() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GridOverlay"
	var plane := PlaneMesh.new()
	plane.size = Vector2(grid_size.x * CELL_SIZE, grid_size.y * CELL_SIZE)
	_mesh_instance.mesh = plane
	# Ligeramente por encima del terreno para evitar z-fighting.
	_mesh_instance.position = Vector3(0, 0.02, 0)
	_mesh_instance.material_override = _make_grid_material()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

func _make_grid_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform float cell_size = 2.0;
uniform float grid_cells_x = 40.0;
uniform float grid_cells_y = 40.0;
uniform vec4 line_color : source_color = vec4(0.35, 0.75, 0.85, 0.35);
uniform vec4 major_color : source_color = vec4(0.45, 0.9, 1.0, 0.55);
uniform float line_width = 0.03;

float grid_line(vec2 coord, float width) {
	vec2 g = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
	float line = min(g.x, g.y);
	return 1.0 - clamp(line - width * 0.0, 0.0, 1.0);
}

void fragment() {
	// UV va de 0..1 sobre todo el plano; escalamos a celdas.
	vec2 cell_uv = UV * vec2(grid_cells_x, grid_cells_y);
	vec2 major_uv = UV * vec2(grid_cells_x / 5.0, grid_cells_y / 5.0);

	float minor = grid_line(cell_uv, line_width);
	float major = grid_line(major_uv, line_width);

	vec4 col = mix(line_color, major_color, major);
	float a = max(minor * line_color.a, major * major_color.a);
	ALBEDO = col.rgb;
	ALPHA = a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cell_size", CELL_SIZE)
	mat.set_shader_parameter("grid_cells_x", float(grid_size.x))
	mat.set_shader_parameter("grid_cells_y", float(grid_size.y))
	mat.set_shader_parameter("line_color", line_color)
	mat.set_shader_parameter("major_color", major_line_color)
	return mat

func _on_grid_visibility_changed(is_visible: bool) -> void:
	_visible_grid = is_visible
	if _mesh_instance:
		_mesh_instance.visible = is_visible

func toggle_visibility() -> void:
	EventBus.grid_visibility_changed.emit(not _visible_grid)
