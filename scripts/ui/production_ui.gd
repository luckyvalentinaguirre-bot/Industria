extends PanelContainer
## ProductionUI — panel de inspección de máquina (spec §19 "Panel de máquina").
##
## Muestra y edita: nombre, estado, receta, entrada, salida, producción, consumo,
## condición y prioridad. Se abre al seleccionar una máquina.

var machine: Machine = null
var _content: VBoxContainer
var _recipe_opt: OptionButton
var _priority_opt: OptionButton
var _enable_chk: CheckButton
var _cond_bar: ProgressBar
var _state_lbl: Label
var _io_lbl: Label
var _repair_btn: Button
var _refresh_accum: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(310, 0)
	add_theme_stylebox_override("panel", UITheme.panel_style())
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	add_child(_content)
	EventBus.machine_selected.connect(_on_selected)
	EventBus.machine_state_changed.connect(_on_state_changed)
	visible = false

func _on_selected(obj: Node) -> void:
	if obj is Machine:
		machine = obj
		_rebuild()
		visible = true

func _on_state_changed(m: Node) -> void:
	if m == machine:
		_refresh()

func close() -> void:
	visible = false
	machine = null

func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	if machine == null:
		return

	var header := HBoxContainer.new()
	header.add_child(UITheme.make_title(machine.display_name()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var x := UITheme.make_button("✕")
	x.custom_minimum_size = Vector2(30, 30)
	x.pressed.connect(close)
	header.add_child(x)
	_content.add_child(header)

	_state_lbl = UITheme.make_label("")
	_content.add_child(_state_lbl)

	# Receta
	_content.add_child(UITheme.make_label("Receta:", 12, UITheme.ACCENT))
	_recipe_opt = OptionButton.new()
	var recs: Array = machine.def.get("recipes", [])
	for i in recs.size():
		_recipe_opt.add_item(GameManager.recipes.recipe_name(String(recs[i])), i)
		if String(recs[i]) == machine.recipe_id:
			_recipe_opt.select(i)
	_recipe_opt.item_selected.connect(_on_recipe_selected)
	_content.add_child(_recipe_opt)

	# Prioridad
	_content.add_child(UITheme.make_label("Prioridad:", 12, UITheme.ACCENT))
	_priority_opt = OptionButton.new()
	for i in Machine.PRIORITY_NAMES.size():
		_priority_opt.add_item(Machine.PRIORITY_NAMES[i], i)
	_priority_opt.select(machine.priority)
	_priority_opt.item_selected.connect(_on_priority_selected)
	_content.add_child(_priority_opt)

	# Activada
	_enable_chk = CheckButton.new()
	_enable_chk.text = "Activada"
	_enable_chk.button_pressed = machine.enabled
	_enable_chk.toggled.connect(_on_enable_toggled)
	_content.add_child(_enable_chk)

	# Condición
	_content.add_child(UITheme.make_label("Condición:", 12, UITheme.ACCENT))
	_cond_bar = ProgressBar.new()
	_cond_bar.max_value = 100
	_cond_bar.custom_minimum_size = Vector2(0, 18)
	_content.add_child(_cond_bar)
	_repair_btn = UITheme.make_button("Reparar")
	_repair_btn.pressed.connect(_on_repair)
	_content.add_child(_repair_btn)

	_content.add_child(UITheme.hsep())
	_io_lbl = UITheme.make_label("")
	_io_lbl.add_theme_font_size_override("font_size", 12)
	_content.add_child(_io_lbl)

	_refresh()

func _refresh() -> void:
	if machine == null or _state_lbl == null:
		return
	_state_lbl.text = "Estado: " + machine.state_name()
	_state_lbl.add_theme_color_override("font_color", _state_color())
	_cond_bar.value = machine.condition
	_repair_btn.disabled = machine.condition >= 100.0
	_repair_btn.text = "Reparar (%s)" % Fmt.money(GameManager.maintenance.repair_cost(machine))
	_io_lbl.text = _io_text()

func _on_recipe_selected(idx: int) -> void:
	if machine == null:
		return
	var recs: Array = machine.def.get("recipes", [])
	if idx >= 0 and idx < recs.size():
		machine.set_recipe(String(recs[idx]))
		_refresh()

func _on_priority_selected(idx: int) -> void:
	if machine:
		machine.set_priority(idx)

func _on_enable_toggled(v: bool) -> void:
	if machine:
		machine.set_enabled(v)

func _on_repair() -> void:
	if machine and GameManager.maintenance.repair(machine):
		_refresh()

func _state_color() -> Color:
	match machine.state:
		Machine.State.RUNNING: return UITheme.ACCENT2
		Machine.State.BROKEN, Machine.State.NO_POWER: return UITheme.DANGER
		Machine.State.NO_MATERIALS, Machine.State.BLOCKED: return UITheme.WARN
		_: return UITheme.TEXT

func _io_text() -> String:
	var s := "⚡ Consumo: %d kW\n" % int(machine.power_draw)
	s += "⏱ Ciclo: %.1fs\n\n" % machine.cycle_time()
	s += "▼ Entrada:\n"
	var inp := machine.input_buffer.provide_peek()
	if inp.is_empty():
		s += "   (vacía)\n"
	for id in inp.keys():
		s += "   %s: %d\n" % [ItemDB.display_name(id), int(inp[id])]
	s += "▲ Salida:\n"
	var outp := machine.output_buffer.provide_peek()
	if outp.is_empty():
		s += "   (vacía)\n"
	for id in outp.keys():
		s += "   %s: %d\n" % [ItemDB.display_name(id), int(outp[id])]
	return s

func _process(delta: float) -> void:
	if not visible or machine == null:
		return
	_refresh_accum += delta
	if _refresh_accum >= 0.4:
		_refresh_accum = 0.0
		_refresh()
