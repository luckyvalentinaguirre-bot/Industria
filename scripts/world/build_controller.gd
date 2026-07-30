extends Node3D
## BuildController — herramienta interactiva de construcción y selección (spec §6).
##
## Modos:
##   * SELECT  — clic sobre una máquina/edificio abre su panel.
##   * MACHINE / BUILDING — coloca con vista previa (ghost) sobre el grid, con
##     validación de espacio, límites y costo; rotación con R.
##   * CONVEYOR — clic en origen y luego en destino conecta una cinta.
##   * DELETE  — clic elimina la construcción (con reembolso parcial).
##
## Usa raycasting: capa 1 (suelo) para posición, capa 2 (objetos) para selección.
##
## Nota de estructura: interacción con el mundo 3D → vive en scripts/world/.

enum Mode { SELECT, MACHINE, BUILDING, CONVEYOR, DELETE }

var mode: int = Mode.SELECT
var current_id: String = ""
var _rotated: bool = false
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _conveyor_source: Node = null
var _selected: Node = null
var _sel_highlight: Node3D

func _ready() -> void:
	_build_ghost()
	EventBus.machine_removed.connect(_on_obj_removed)
	EventBus.building_removed.connect(_on_obj_removed)

func _on_obj_removed(obj: Node) -> void:
	if obj == _selected:
		_clear_highlight()
		_selected = null

# --- Resaltado de selección (amarillo) --------------------------------------
func _highlight_selected(obj: Node) -> void:
	_clear_highlight()
	if not (obj is Node3D):
		return
	var gs: Vector2i = obj.grid_size if ("grid_size" in obj) else Vector2i(2, 2)
	var w: float = gs.x * GameState.CELL_SIZE * 0.5 + 0.3
	var d: float = gs.y * GameState.CELL_SIZE * 0.5 + 0.3
	_sel_highlight = Node3D.new()
	add_child(_sel_highlight)
	_sel_highlight.global_position = Vector3((obj as Node3D).global_position.x, 0.09, (obj as Node3D).global_position.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.15)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Cuatro esquineras tipo corchete.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var cx := _corner_bar(Vector3(0.9, 0.06, 0.14), Vector3(sx * (w - 0.45), 0, sz * d), mat)
			var cz := _corner_bar(Vector3(0.14, 0.06, 0.9), Vector3(sx * w, 0, sz * (d - 0.45)), mat)

func _corner_bar(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_highlight.add_child(mi)
	return mi

func _clear_highlight() -> void:
	if _sel_highlight and is_instance_valid(_sel_highlight):
		_sel_highlight.queue_free()
	_sel_highlight = null

# --- API (la llama la UI) ---------------------------------------------------
func set_mode_select() -> void:
	_reset_to_select()

func start_place_machine(id: String) -> void:
	mode = Mode.MACHINE
	current_id = id
	_rotated = false
	_conveyor_source = null
	_update_ghost_mesh()
	EventBus.build_mode_changed.emit(true, "machine:" + id)

func start_place_building(id: String) -> void:
	mode = Mode.BUILDING
	current_id = id
	_rotated = false
	_conveyor_source = null
	_update_ghost_mesh()
	EventBus.build_mode_changed.emit(true, "building:" + id)

func start_conveyor() -> void:
	mode = Mode.CONVEYOR
	_conveyor_source = null
	_ghost.visible = false
	EventBus.build_mode_changed.emit(true, "conveyor")

func start_delete() -> void:
	mode = Mode.DELETE
	_ghost.visible = false
	EventBus.build_mode_changed.emit(true, "delete")

# --- Estado del sistema de construcción -------------------------------------
## ¿Hay una herramienta de construcción activa? (cualquier modo != SELECT).
func is_building() -> bool:
	return mode != Mode.SELECT

# --- Input ------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# ESC: sólo cancela la construcción si HAY una activa; si no, deja que la UI
	# lo gestione (cerrar menú/panel). Así ESC nunca hace dos cosas a la vez.
	if event.is_action_pressed("ui_cancel"):
		if is_building():
			_reset_to_select()
			get_viewport().set_input_as_handled()
		return
	# Clic derecho: cancela la construcción en curso.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_building():
			_reset_to_select()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if mode == Mode.MACHINE or mode == Mode.BUILDING:
			_rotated = not _rotated
			_update_ghost_mesh()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click()

func _process(_delta: float) -> void:
	if mode == Mode.MACHINE or mode == Mode.BUILDING:
		_update_ghost_position()

func _current_size() -> Vector2i:
	var s := Vector2i(2, 2)
	if mode == Mode.MACHINE:
		var d: Dictionary = GameManager.recipes.get_machine_def(current_id)
		var a: Array = d.get("size", [2, 2])
		s = Vector2i(int(a[0]), int(a[1]))
	elif mode == Mode.BUILDING:
		var d := _building_def(current_id)
		var a: Array = d.get("size", [2, 2])
		s = Vector2i(int(a[0]), int(a[1]))
	return Vector2i(s.y, s.x) if _rotated else s

func _cost() -> int:
	if mode == Mode.MACHINE:
		return int(GameManager.recipes.get_machine_def(current_id).get("cost", 0))
	elif mode == Mode.BUILDING:
		return int(_building_def(current_id).get("cost", 0))
	return 0

func _building_def(id: String) -> Dictionary:
	var path := "res://data/buildings/buildings.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return (data.get("buildings", {}) as Dictionary).get(id, {})
	return {}

# --- Raycasting -------------------------------------------------------------
func _ray_to_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	# Intersección con el plano y=0.
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t := -from.y / dir.y
	return from + dir * t

func _ray_pick_object() -> Node:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 500.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)  # capa 2
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var collider: Object = hit["collider"]
	if collider.has_meta("machine"):
		return collider.get_meta("machine")
	if collider.has_meta("building"):
		return collider.get_meta("building")
	return null

# --- Colocación / selección -------------------------------------------------
func _on_click() -> void:
	match mode:
		Mode.SELECT:
			var obj := _ray_pick_object()
			if obj:
				_selected = obj
				_highlight_selected(obj)
				EventBus.machine_selected.emit(obj)
			else:
				_clear_highlight()
		Mode.MACHINE, Mode.BUILDING:
			_try_place()
		Mode.CONVEYOR:
			_conveyor_click()
		Mode.DELETE:
			_delete_click()

func _origin_cell() -> Vector2i:
	var pos := _ray_to_ground()
	var size := _current_size()
	var center_cell: Vector2i = GameManager.grid.world_to_cell(pos)
	# El ghost se centra en el cursor; calcular esquina.
	return center_cell - Vector2i(int(size.x / 2.0), int(size.y / 2.0))

func _try_place() -> void:
	if mode == Mode.MACHINE and GameManager.specialization and not GameManager.specialization.is_machine_available(current_id):
		var req: String = GameManager.specialization.exclusive_branch(current_id)
		EventBus.notify.emit("Requiere la rama %s (elegila en Tecnología)" % GameManager.specialization.branch_name(req), "warning")
		return
	if GameManager.progression and not GameManager.progression.is_unlocked(current_id):
		EventBus.notify.emit("Se desbloquea en nivel %d de empresa" % GameManager.progression.required_level(current_id), "warning")
		return
	var size := _current_size()
	var origin := _origin_cell()
	if not GameManager.grid.is_area_buildable(origin, size):
		EventBus.notify.emit("Fuera del terreno disponible (amplía tu terreno)", "error")
		return
	if not GameManager.grid.is_area_free(origin, size):
		EventBus.notify.emit("Espacio ocupado o fuera de límites", "error")
		return
	var cost := _cost()
	if not GameManager.economy.can_afford(cost):
		EventBus.notify.emit("No hay fondos para construir (%s)" % Fmt.money(cost), "error")
		return
	GameManager.economy.spend(cost, "construction")
	if mode == Mode.MACHINE:
		var m: Machine = GameManager.machines.create_machine(current_id, origin)
		if _rotated:
			m.grid_size = size
		GameManager.grid.occupy_area(origin, size, m.uid)
		EventBus.machine_selected.emit(m)
	else:
		var b: Building = GameManager.buildings.create_building(current_id, origin)
		GameManager.grid.occupy_area(origin, size, b.uid)
	EventBus.notify.emit("Construido (%s)" % Fmt.money(cost), "success")
	# Mantener el modo para colocar varios; Esc para salir.

func _conveyor_click() -> void:
	var obj := _ray_pick_object()
	if obj == null:
		return
	if _conveyor_source == null:
		_conveyor_source = obj
		EventBus.notify.emit("Origen de cinta seleccionado. Elige el destino.", "info")
	else:
		GameManager.transport.create_conveyor(_conveyor_source, obj)
		_conveyor_source = null

func _delete_click() -> void:
	var obj := _ray_pick_object()
	if obj == null:
		return
	if obj is Machine:
		GameManager.economy.earn(int(obj.def.get("cost", 0)) * 0.4, "misc")
		GameManager.machines.remove_machine(obj)
	elif obj is Building:
		GameManager.economy.earn(int(obj.def.get("cost", 0)) * 0.4, "misc")
		GameManager.buildings.remove_building(obj)
	EventBus.notify.emit("Construcción eliminada (reembolso 40%)", "info")

# --- Expansión de terreno (spec §12) ----------------------------------------
## La parcela arranca en 12×12 y crece de a 8 celdas por compra.
const EXPANSION_COSTS := [25000, 75000, 200000, 400000]

func expansion_level() -> int:
	return int((GameState.buildable_size.x - 12) / 8)

func expansion_cost() -> int:
	var lvl: int = expansion_level()
	if lvl < EXPANSION_COSTS.size():
		return EXPANSION_COSTS[lvl]
	return EXPANSION_COSTS[EXPANSION_COSTS.size() - 1] + (lvl - EXPANSION_COSTS.size() + 1) * 200000

func buy_expansion() -> void:
	if GameManager.grid.is_at_max_expansion():
		EventBus.notify.emit("El terreno ya está al máximo", "warning")
		return
	var cost := expansion_cost()
	if not GameManager.economy.spend(cost, "construction"):
		return
	GameManager.grid.expand(8)
	EventBus.notify.emit("Terreno ampliado (%s). Más espacio, más costos." % Fmt.money(cost), "success")

func _reset_to_select() -> void:
	mode = Mode.SELECT
	current_id = ""
	_conveyor_source = null
	_ghost.visible = false
	EventBus.build_mode_changed.emit(false, "")

# --- Ghost ------------------------------------------------------------------
func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.4)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)

func _update_ghost_mesh() -> void:
	var size := _current_size()
	var cell := GameState.CELL_SIZE
	(_ghost.mesh as BoxMesh).size = Vector3(size.x * cell, 2.0, size.y * cell)
	_ghost.visible = true

func _update_ghost_position() -> void:
	var size := _current_size()
	var origin := _origin_cell()
	var base: Vector3 = GameManager.grid.cell_to_world(origin)
	var center: Vector3 = base + Vector3((size.x - 1) * GameState.CELL_SIZE * 0.5, 1.0, (size.y - 1) * GameState.CELL_SIZE * 0.5)
	_ghost.global_position = center
	var ok: bool = GameManager.grid.is_area_buildable(origin, size) and GameManager.grid.is_area_free(origin, size) and GameManager.economy.can_afford(_cost())
	_ghost_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.4) if ok else Color(0.9, 0.3, 0.3, 0.4)
