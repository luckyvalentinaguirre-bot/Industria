extends Node3D
## CameraRig — cámara estratégica de Industria (elevada y diagonal).
##
## Estructura de nodos esperada:
##   CameraRig (este Node3D = pivote sobre el terreno)
##     └── SpringArm3D  (brazo que fija la distancia/altura)
##           └── Camera3D
##
## Controles:
##   * WASD / bordes de pantalla → desplazar (pan) sobre el plano del terreno.
##   * Botón central del ratón (arrastrar) → pan.
##   * Q / E → rotar alrededor del pivote.
##   * Rueda del ratón → zoom (acerca/aleja el brazo).
##
## El pan es relativo a la rotación actual, de modo que "adelante" siempre es
## hacia donde mira la cámara. Todo el movimiento es suavizado (lerp) para dar
## sensación de juego de gestión pulido.
##
## Nota de estructura: vive en scripts/world/ (pertenece al mundo). No modifica
## la estructura de carpetas existente.

@export_group("Pan")
@export var pan_speed: float = 22.0
@export var edge_pan_margin: int = 8
@export var edge_pan_enabled: bool = true
@export var pan_smooth: float = 12.0

@export_group("Rotación")
@export var rotation_speed: float = 2.0
@export var rotation_smooth: float = 10.0

@export_group("Zoom")
@export var zoom_min: float = 6.0    # más cerca: apreciar detalle de las máquinas
@export var zoom_max: float = 64.0   # más lejos: ver toda la fábrica ampliada
@export var zoom_step: float = 3.5
@export var zoom_smooth: float = 10.0

@export_group("Límites")
@export var bounds_extent: float = 48.0  # cuánto puede alejarse el pivote del centro

var _spring: SpringArm3D
var _camera: Camera3D

var _target_position: Vector3
var _target_yaw: float = 0.0
var _target_zoom: float = 34.0
var _dragging: bool = false

func _ready() -> void:
	_spring = $SpringArm3D
	_camera = $SpringArm3D/Camera3D
	_target_position = global_position
	_target_yaw = rotation.y
	_target_zoom = _spring.spring_length
	# El brazo colisiona con el suelo (capa 1) para no atravesar el terreno (§21).
	_spring.collision_mask = 1
	_spring.margin = 0.4
	# Enfocar rápidamente la máquina/edificio seleccionado.
	EventBus.machine_selected.connect(_on_selected)

func _on_selected(obj: Node) -> void:
	if obj is Node3D:
		focus_on((obj as Node3D).global_position)

## Desplaza suavemente la cámara para centrar un punto del mundo.
func focus_on(world_pos: Vector3) -> void:
	_target_position = Vector3(
		clampf(world_pos.x, -bounds_extent, bounds_extent),
		0.0,
		clampf(world_pos.z, -bounds_extent, bounds_extent))
	# Acercar un poco si estábamos muy alejados.
	_target_zoom = clampf(_target_zoom, zoom_min, 28.0)

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	if edge_pan_enabled:
		_handle_edge_pan(delta)

	# Suavizado de traslación, rotación y zoom.
	global_position = global_position.lerp(_target_position, clampf(pan_smooth * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(rotation_smooth * delta, 0.0, 1.0))
	_spring.spring_length = lerpf(_spring.spring_length, _target_zoom, clampf(zoom_smooth * delta, 0.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_zoom(-zoom_step)
	elif event.is_action_pressed("cam_zoom_out"):
		_zoom(zoom_step)
	elif event.is_action_pressed("cam_rotate_left"):
		_target_yaw += deg_to_rad(45.0)
	elif event.is_action_pressed("cam_rotate_right"):
		_target_yaw -= deg_to_rad(45.0)
	elif event.is_action_pressed("cam_drag"):
		_dragging = true
	elif event.is_action_released("cam_drag"):
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_drag_pan(event.relative)

# --- Pan --------------------------------------------------------------------

func _handle_keyboard_pan(delta: float) -> void:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
	input.y = Input.get_action_strength("cam_back") - Input.get_action_strength("cam_forward")
	if input != Vector2.ZERO:
		_move_planar(input.normalized() * pan_speed * delta)

func _handle_edge_pan(delta: float) -> void:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	# Ignora si el ratón está fuera de la ventana.
	if mouse.x < 0 or mouse.y < 0 or mouse.x > size.x or mouse.y > size.y:
		return
	var input := Vector2.ZERO
	if mouse.x <= edge_pan_margin:
		input.x -= 1.0
	elif mouse.x >= size.x - edge_pan_margin:
		input.x += 1.0
	if mouse.y <= edge_pan_margin:
		input.y -= 1.0
	elif mouse.y >= size.y - edge_pan_margin:
		input.y += 1.0
	if input != Vector2.ZERO:
		_move_planar(input.normalized() * pan_speed * delta)

func _drag_pan(relative: Vector2) -> void:
	# Escala el arrastre por la distancia de zoom para un tacto consistente.
	var factor := _spring.spring_length * 0.0016
	_move_planar(Vector2(-relative.x, -relative.y) * factor)

## Mueve el pivote sobre el plano XZ, relativo a la orientación actual.
func _move_planar(amount: Vector2) -> void:
	var basis_yaw := Basis(Vector3.UP, _target_yaw)
	var offset := basis_yaw * Vector3(amount.x, 0.0, amount.y)
	_target_position += offset
	_target_position.x = clampf(_target_position.x, -bounds_extent, bounds_extent)
	_target_position.z = clampf(_target_position.z, -bounds_extent, bounds_extent)
	_target_position.y = 0.0

# --- Zoom -------------------------------------------------------------------

func _zoom(amount: float) -> void:
	_target_zoom = clampf(_target_zoom + amount, zoom_min, zoom_max)
