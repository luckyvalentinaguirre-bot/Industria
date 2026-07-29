extends PanelContainer
## FactoryUI — menú de construcción tipo videojuego (spec §19 Construcción).
##
## Tarjetas por categoría con icono, nombre, precio y tooltip descriptivo.
## Compacto para no tapar el mapa. Activa el modo de colocación del
## BuildController; incluye herramientas de cinta, selección y eliminación.

const ICONS := {
	"smelter": "🔥", "press": "🛠", "assembler": "🦾",
	"small_storage": "📦", "large_storage": "🏬",
	"splitter": "🔀", "merger": "🔗", "filter": "🧲",
	"generator": "🔌", "substation": "⚡", "workshop": "🔧",
}

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(232, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_build(box)

func _controller() -> Node:
	if GameManager.world and ("build_controller" in GameManager.world):
		return GameManager.world.build_controller
	return null

func _build(box: VBoxContainer) -> void:
	box.add_child(UITheme.make_title("🏗  Construcción"))

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	var sel := _tool_btn("🖱", "Seleccionar", _on_select)
	var del := _tool_btn("🗑", "Eliminar", _on_delete)
	tools.add_child(sel)
	tools.add_child(del)
	box.add_child(tools)

	_header(box, "PRODUCCIÓN")
	for mid in GameManager.recipes.machine_ids():
		box.add_child(_machine_card(String(mid)))

	_header(box, "LOGÍSTICA")
	box.add_child(_card("➡", "Cinta transportadora", 350,
		"Transporta materiales entre máquinas y almacenes.\nConecta: clic en origen y luego en destino.", _on_conveyor))
	for bid in _buildings_of("storage") + _buildings_of("logistics"):
		box.add_child(_building_card(bid))

	_header(box, "ENERGÍA")
	for bid in _buildings_of("energy"):
		box.add_child(_building_card(bid))

	_header(box, "MANTENIMIENTO")
	for bid in _buildings_of("maintenance"):
		box.add_child(_building_card(bid))

	_header(box, "EXPANSIÓN")
	box.add_child(_card("🗺", "Ampliar terreno", 0,
		"Aumenta el área construible. Más espacio pero mayores costos fijos.", _on_expand))

# --- Widgets ----------------------------------------------------------------
func _header(box: VBoxContainer, text: String) -> void:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.30, 0.78, 0.86, 0.14)
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", st)
	var l := UITheme.make_label(text, 11, UITheme.ACCENT)
	l.add_theme_constant_override("outline_size", 0)
	p.add_child(l)
	box.add_child(p)

func _card(icon: String, name: String, price: int, tooltip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = "%s\n\n%s%s" % [name, tooltip, ("" if price <= 0 else "\n\nPrecio: " + Fmt.money(price))]
	b.text = "%s  %s%s" % [icon, name, ("" if price <= 0 else "   " + Fmt.money(price))]
	b.add_theme_font_size_override("font_size", 12)
	b.clip_text = true
	b.pressed.connect(cb)
	return b

func _tool_btn(icon: String, label: String, cb: Callable) -> Button:
	var b := UITheme.make_button("%s %s" % [icon, label])
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = label
	b.pressed.connect(cb)
	return b

func _machine_card(mid: String) -> Button:
	var d: Dictionary = GameManager.recipes.get_machine_def(mid)
	var size: Array = d.get("size", [2, 2])
	var recs: Array = d.get("recipes", [])
	var rec_names: Array = []
	for r in recs:
		rec_names.append(GameManager.recipes.recipe_name(String(r)))
	var tip := "Tamaño %d×%d · %d kW\nFabrica: %s" % [int(size[0]), int(size[1]), int(d.get("power", 0)), ", ".join(rec_names)]
	return _card(ICONS.get(mid, "⚙"), String(d.get("name", mid)), int(d.get("cost", 0)), tip, _on_place_machine.bind(mid))

func _building_card(bid: String) -> Button:
	var d: Dictionary = _all_buildings().get(bid, {})
	var size: Array = d.get("size", [2, 2])
	var tip := "Tamaño %d×%d" % [int(size[0]), int(size[1])]
	if d.has("capacity"): tip += " · Capacidad +%d" % int(d["capacity"])
	if d.has("power_output"): tip += " · Genera %d kW" % int(d["power_output"])
	if d.has("power_capacity"): tip += " · Capacidad +%d kW" % int(d["power_capacity"])
	if d.has("is_filter"): tip += " · Filtra un tipo de ítem"
	return _card(ICONS.get(bid, "🏢"), String(d.get("name", bid)), int(d.get("cost", 0)), tip, _on_place_building.bind(bid))

func _buildings_of(category: String) -> Array:
	var out: Array = []
	var defs := _all_buildings()
	for bid in defs.keys():
		if String(defs[bid].get("category", "")) == category:
			out.append(bid)
	return out

# --- Handlers ---------------------------------------------------------------
func _on_select() -> void:
	var c := _controller()
	if c: c.set_mode_select()

func _on_place_machine(mid: String) -> void:
	var c := _controller()
	if c: c.start_place_machine(mid)

func _on_place_building(bid: String) -> void:
	var c := _controller()
	if c: c.start_place_building(bid)

func _on_conveyor() -> void:
	var c := _controller()
	if c: c.start_conveyor()

func _on_delete() -> void:
	var c := _controller()
	if c: c.start_delete()

func _on_expand() -> void:
	var c := _controller()
	if c: c.buy_expansion()

func _all_buildings() -> Dictionary:
	var path := "res://data/buildings/buildings.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return data.get("buildings", {})
	return {}
