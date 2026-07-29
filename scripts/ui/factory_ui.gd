extends PanelContainer
## FactoryUI — menú de construcción (spec §6, §19 Construcción).
##
## Barra lateral con categorías: Producción, Logística, Energía, Mantenimiento.
## Cada botón activa el modo de colocación del BuildController. Incluye las
## herramientas de cinta, selección y eliminación.

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(210, 480)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_build(box)

func _controller() -> Node:
	if GameManager.world and ("build_controller" in GameManager.world):
		return GameManager.world.build_controller
	return null

func _build(box: VBoxContainer) -> void:
	box.add_child(UITheme.make_title("Construcción"))

	var sel := UITheme.make_button("🖱 Seleccionar")
	sel.pressed.connect(_on_select)
	box.add_child(sel)

	# Producción (máquinas)
	box.add_child(UITheme.make_label("Producción", 12, UITheme.ACCENT))
	for mid in GameManager.recipes.machine_ids():
		var d: Dictionary = GameManager.recipes.get_machine_def(mid)
		var b := UITheme.make_button("%s  (%s)" % [String(d.get("name", mid)), Fmt.money(d.get("cost", 0))])
		b.pressed.connect(_on_place_machine.bind(String(mid)))
		box.add_child(b)

	# Logística
	box.add_child(UITheme.make_label("Logística", 12, UITheme.ACCENT))
	var conv := UITheme.make_button("Cinta transportadora (%s)" % Fmt.money(350))
	conv.pressed.connect(_on_conveyor)
	box.add_child(conv)
	_building_buttons(box, "storage")

	# Energía
	box.add_child(UITheme.make_label("Energía", 12, UITheme.ACCENT))
	_building_buttons(box, "energy")

	# Mantenimiento
	box.add_child(UITheme.make_label("Mantenimiento", 12, UITheme.ACCENT))
	_building_buttons(box, "maintenance")

	box.add_child(UITheme.hsep())
	var del := UITheme.make_button("🗑 Eliminar")
	del.pressed.connect(_on_delete)
	box.add_child(del)

func _building_buttons(box: VBoxContainer, category: String) -> void:
	var defs := _all_buildings()
	for bid in defs.keys():
		var d: Dictionary = defs[bid]
		if String(d.get("category", "")) != category:
			continue
		var b := UITheme.make_button("%s  (%s)" % [String(d.get("name", bid)), Fmt.money(d.get("cost", 0))])
		b.pressed.connect(_on_place_building.bind(String(bid)))
		box.add_child(b)

# --- Handlers ---------------------------------------------------------------
func _on_select() -> void:
	var c := _controller()
	if c:
		c.set_mode_select()

func _on_place_machine(mid: String) -> void:
	var c := _controller()
	if c:
		c.start_place_machine(mid)

func _on_place_building(bid: String) -> void:
	var c := _controller()
	if c:
		c.start_place_building(bid)

func _on_conveyor() -> void:
	var c := _controller()
	if c:
		c.start_conveyor()

func _on_delete() -> void:
	var c := _controller()
	if c:
		c.start_delete()

func _all_buildings() -> Dictionary:
	var path := "res://data/buildings/buildings.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return data.get("buildings", {})
	return {}
