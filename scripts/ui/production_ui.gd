extends PanelContainer
## ProductionUI — panel de inspección de máquina con jerarquía visual (spec §19).
##
## Muestra primero lo importante (estado, receta, progreso de ciclo, E/S) y
## debajo los datos secundarios (energía, condición) y las acciones (reparar,
## activar/desactivar). Se abre al seleccionar una máquina.

var machine: Machine = null
var _box: VBoxContainer
var _title: Label
var _status: Label
var _recipe_opt: OptionButton
var _priority_opt: OptionButton
var _cycle_bar: ProgressBar
var _order_lbl: Label
var _op_btn: Button
var _flow_lbl: Label
var _in_lbl: Label
var _out_lbl: Label
var _power_lbl: Label
var _cond_bar: ProgressBar
var _cond_lbl: Label
var _repair_btn: Button
var _toggle_btn: Button
var _upgrade_btn: Button
var _accum: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	add_theme_stylebox_override("panel", UITheme.panel_style())
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 7)
	add_child(_box)
	EventBus.machine_selected.connect(_on_selected)
	EventBus.machine_state_changed.connect(_on_state_changed)
	visible = false

func _on_selected(obj: Node) -> void:
	if obj is Machine:
		machine = obj
		_rebuild()
		visible = true
	else:
		# Clic en vacío u otro objeto: el panel de máquina desaparece (spec §16).
		close()

func _on_state_changed(m: Node) -> void:
	if m == machine:
		_refresh()

func close() -> void:
	visible = false
	machine = null

func _section(text: String) -> void:
	_box.add_child(UITheme.make_label(text.to_upper(), 11, UITheme.ACCENT))

func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	if machine == null:
		return

	# Cabecera.
	var header := HBoxContainer.new()
	_title = UITheme.make_label(machine.display_name(), 20, UITheme.TEXT)
	header.add_child(_title)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	var x := UITheme.make_button("✕"); x.custom_minimum_size = Vector2(30, 30)
	x.pressed.connect(close)
	header.add_child(x)
	_box.add_child(header)

	# Estado destacado.
	_status = UITheme.make_label("", 16)
	_box.add_child(_status)
	# Flujo de producción: ENTRADA → máquina → SALIDA (spec §8).
	_flow_lbl = UITheme.make_label("", 13, UITheme.ACCENT2)
	_flow_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flow_lbl.custom_minimum_size = Vector2(300, 0)
	_box.add_child(_flow_lbl)
	_box.add_child(UITheme.hsep())

	# Receta.
	_section("Receta")
	_recipe_opt = OptionButton.new()
	var recs: Array = machine.def.get("recipes", [])
	for i in recs.size():
		_recipe_opt.add_item(GameManager.recipes.recipe_name(String(recs[i])), i)
		if String(recs[i]) == machine.recipe_id:
			_recipe_opt.select(i)
	_recipe_opt.item_selected.connect(_on_recipe_selected)
	_box.add_child(_recipe_opt)

	# Producción (barra de ciclo).
	_section("Producción · progreso de ciclo")
	_cycle_bar = ProgressBar.new()
	_cycle_bar.max_value = 100
	_cycle_bar.show_percentage = false
	_cycle_bar.custom_minimum_size = Vector2(0, 16)
	_box.add_child(_cycle_bar)

	# ORDEN DE PRODUCCIÓN: lote manual (vos trabajás) u operario (continuo).
	_section("Orden de producción")
	_order_lbl = UITheme.make_label("", 12)
	_order_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_lbl.custom_minimum_size = Vector2(300, 0)
	_box.add_child(_order_lbl)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	var b10 := UITheme.make_button("▶ Producir ×10")
	b10.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b10.pressed.connect(_on_batch.bind(10))
	var b50 := UITheme.make_button("×50")
	b50.pressed.connect(_on_batch.bind(50))
	var bstop := UITheme.make_button("⏹")
	bstop.tooltip_text = "Detener el lote actual"
	bstop.pressed.connect(_on_stop_batch)
	brow.add_child(b10); brow.add_child(b50); brow.add_child(bstop)
	_box.add_child(brow)
	_op_btn = UITheme.make_button("")
	_op_btn.pressed.connect(_on_toggle_operator)
	_box.add_child(_op_btn)

	# Entrada / Salida.
	var io := HBoxContainer.new()
	io.add_theme_constant_override("separation", 12)
	var incol := VBoxContainer.new()
	incol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	incol.add_child(UITheme.make_label("ENTRADA", 11, UITheme.ACCENT))
	_in_lbl = UITheme.make_label("", 12)
	incol.add_child(_in_lbl)
	var outcol := VBoxContainer.new()
	outcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outcol.add_child(UITheme.make_label("SALIDA", 11, UITheme.ACCENT2))
	_out_lbl = UITheme.make_label("", 12)
	outcol.add_child(_out_lbl)
	io.add_child(incol)
	io.add_child(outcol)
	_box.add_child(io)
	_box.add_child(UITheme.hsep())

	# Datos secundarios.
	_power_lbl = UITheme.make_label("", 12)
	_box.add_child(_power_lbl)
	_section("Condición")
	_cond_bar = ProgressBar.new()
	_cond_bar.max_value = 100
	_cond_bar.show_percentage = false
	_cond_bar.custom_minimum_size = Vector2(0, 14)
	_box.add_child(_cond_bar)
	_cond_lbl = UITheme.make_label("", 12)
	_box.add_child(_cond_lbl)

	# Prioridad (secundario).
	var prow := HBoxContainer.new()
	prow.add_child(UITheme.make_label("Prioridad:", 12))
	_priority_opt = OptionButton.new()
	for i in Machine.PRIORITY_NAMES.size():
		_priority_opt.add_item(Machine.PRIORITY_NAMES[i], i)
	_priority_opt.select(machine.priority)
	_priority_opt.item_selected.connect(_on_priority_selected)
	prow.add_child(_priority_opt)
	_box.add_child(prow)

	# Acciones.
	_box.add_child(UITheme.hsep())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_repair_btn = UITheme.make_button("🔧 Reparar")
	_repair_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_btn.pressed.connect(_on_repair)
	_toggle_btn = UITheme.make_button("⏻ Activar/Desactivar")
	_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle_btn.pressed.connect(_on_toggle)
	actions.add_child(_repair_btn)
	actions.add_child(_toggle_btn)
	_box.add_child(actions)
	_upgrade_btn = UITheme.make_button("⬆ Mejorar")
	_upgrade_btn.pressed.connect(_on_upgrade)
	_box.add_child(_upgrade_btn)

	_refresh()

# --- Refresco ---------------------------------------------------------------
func _refresh() -> void:
	if machine == null or _status == null:
		return
	var dot := "🟢"
	var col := UITheme.ACCENT2
	match machine.state:
		Machine.State.RUNNING: dot = "🟢"; col = UITheme.ACCENT2
		Machine.State.NO_MATERIALS, Machine.State.BLOCKED: dot = "🟡"; col = UITheme.WARN
		Machine.State.NO_POWER, Machine.State.BROKEN: dot = "🔴"; col = UITheme.DANGER
		Machine.State.MAINTENANCE: dot = "🔵"; col = UITheme.ACCENT
		_: dot = "⚪"; col = UITheme.TEXT
	_status.text = "%s  %s" % [dot, machine.state_name()]
	_status.add_theme_color_override("font_color", col)
	if _title:
		_title.text = machine.display_name()

	if _flow_lbl:
		_flow_lbl.text = _flow_text()
	_refresh_order()
	if _cycle_bar:
		_cycle_bar.value = 0.0 if machine.cycle_time() <= 0.0 else clampf(machine.progress / machine.cycle_time() * 100.0, 0, 100)
	_in_lbl.text = _buffer_text(machine.input_buffer)
	_out_lbl.text = _buffer_text(machine.output_buffer)
	_power_lbl.text = "⚡ %d kW   ⏱ %.1fs   📈 %.1f/min" % [int(machine.effective_power_draw()), machine.cycle_time(), machine.production_per_min()]
	_cond_bar.value = machine.condition
	var eff := int(lerpf(45.0, 100.0, clampf(machine.condition / 100.0, 0.0, 1.0)))
	_cond_lbl.text = "Condición %d%%  ·  Eficiencia %d%%" % [int(machine.condition), eff]
	_cond_lbl.add_theme_color_override("font_color", UITheme.DANGER if machine.condition < 30 else (UITheme.WARN if machine.condition < 60 else UITheme.TEXT))
	_repair_btn.disabled = machine.condition >= 100.0
	_repair_btn.text = "🔧 Reparar" if machine.condition >= 100.0 else "🔧 Reparar (%s)" % Fmt.money(GameManager.maintenance.repair_cost(machine))
	_toggle_btn.text = "⏸ Desactivar" if machine.enabled else "▶ Activar"
	if _upgrade_btn:
		if machine.can_upgrade():
			_upgrade_btn.disabled = false
			_upgrade_btn.text = "⬆ Mejorar a nivel %d (%s)" % [machine.level + 1, Fmt.money(machine.upgrade_cost())]
		else:
			_upgrade_btn.disabled = true
			_upgrade_btn.text = "⬆ Nivel máximo"

func _on_upgrade() -> void:
	if machine and machine.upgrade():
		_refresh()

func _on_batch(n: int) -> void:
	if machine:
		machine.queue_batch(n)
		_refresh()

func _on_stop_batch() -> void:
	if machine:
		machine.clear_batch()
		_refresh()

func _on_toggle_operator() -> void:
	if machine == null:
		return
	var wm: Node = GameManager.workers
	var assigned = wm.worker_for_machine(machine.uid)
	if assigned:
		wm.assign(assigned, 0)   # liberar al trabajador
	else:
		# Asigna el trabajador SIN ASIGNAR con mejor bono de velocidad.
		var best = null
		var best_v := -1.0
		for w in wm.unassigned_workers():
			if w.speed_bonus() > best_v:
				best_v = w.speed_bonus()
				best = w
		if best:
			wm.assign(best, machine.uid)
		else:
			EventBus.notify.emit("No hay trabajadores libres. Contratá o liberá a alguien en 👷 Personal.", "warning")
	_refresh()

## Actualiza la sección de orden de producción (lote / operario / automático).
func _refresh_order() -> void:
	if _order_lbl == null or machine == null:
		return
	var auto: bool = GameManager.upgrades and GameManager.upgrades.full_auto()
	if auto:
		_order_lbl.text = "🤖 Automatización total: produce sola."
		_op_btn.visible = false
		return
	_op_btn.visible = true
	var wm: Node = GameManager.workers
	var assigned = wm.worker_for_machine(machine.uid)
	if assigned:
		_order_lbl.text = "👷 %s trabajando aquí (+%d%% velocidad, calidad %d★). Producción continua." % [
			assigned.worker_name, int(assigned.speed_bonus() * 100.0), assigned.star("quality")]
		_op_btn.text = "Quitar trabajador"
	elif machine.batch_remaining > 0:
		_order_lbl.text = "▶ Lote en curso: %d ciclos restantes (sin trabajador)." % machine.batch_remaining
		_op_btn.text = "Asignar trabajador (libres: %d)" % wm.operators_free()
	else:
		_order_lbl.text = "⏸ Sin producir. Dale un lote (trabajás vos) o asigná un trabajador."
		_op_btn.text = "Asignar trabajador (libres: %d)" % wm.operators_free()

## Cadena visual "insumos → máquina → productos" según la receta activa.
func _flow_text() -> String:
	if machine == null or machine.recipe_id == "":
		return "Sin receta seleccionada"
	var ins: Array = []
	for id in machine.current_inputs().keys():
		ins.append("%s ×%d" % [ItemDB.display_name(id), int(machine.current_inputs()[id])])
	var outs: Array = []
	for id in machine.current_outputs().keys():
		outs.append("%s ×%d" % [ItemDB.display_name(id), int(machine.current_outputs()[id])])
	var in_txt := "  ·  ".join(ins) if not ins.is_empty() else "—"
	var out_txt := "  ·  ".join(outs) if not outs.is_empty() else "—"
	return "%s  →  ⚙ %s  →  %s" % [in_txt, String(machine.def.get("name", "")), out_txt]

func _buffer_text(inv: Inventory) -> String:
	var items := inv.provide_peek()
	if items.is_empty():
		return "—"
	var s := ""
	for id in items.keys():
		s += "%s ×%d\n" % [ItemDB.display_name(id), int(items[id])]
	return s

# --- Handlers ---------------------------------------------------------------
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

func _on_toggle() -> void:
	if machine:
		machine.set_enabled(not machine.enabled)
		_refresh()

func _on_repair() -> void:
	if machine and GameManager.maintenance.repair(machine):
		_refresh()

func _process(delta: float) -> void:
	if not visible or machine == null:
		return
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		_refresh()
