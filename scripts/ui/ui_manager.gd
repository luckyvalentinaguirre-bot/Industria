extends Node
## UIManager — HUD, notificaciones y coordinación de paneles (spec §19).
##
## Construye por código toda la interfaz: barra superior (dinero, deuda, reloj,
## energía, velocidad), menú de construcción (FactoryUI), barra inferior de
## accesos, paneles laterales (máquina, finanzas, automatización, contratos,
## personal) y sistema de avisos (toasts).

const FactoryUIScript := preload("res://scripts/ui/factory_ui.gd")
const ProductionUIScript := preload("res://scripts/ui/production_ui.gd")
const FinanceUIScript := preload("res://scripts/ui/finance_ui.gd")
const AutomationUIScript := preload("res://scripts/ui/automation_ui.gd")

var layer: CanvasLayer
var root: Control

# HUD
var _money_lbl: Label
var _value_lbl: Label
var _debt_lbl: Label
var _rep_lbl: Label
var _level_lbl: Label
var _clock_lbl: Label
var _power_lbl: Label
var _mode_lbl: Label
var _tutorial_banner: PanelContainer
var _tutorial_label: Label

# Ayuda contextual del modo construcción.
var _build_help: PanelContainer
var _build_help_title: Label

# Rastreador compacto de objetivo actual (discreto, un solo objetivo).
var _obj_tracker: PanelContainer
var _obj_title: Label
var _obj_progress: Label
var _obj_bar: ProgressBar

# Panels
var production_ui: PanelContainer
var finance_ui: PanelContainer
var automation_ui: PanelContainer
var contracts_panel: PanelContainer
var workers_panel: PanelContainer
var objectives_panel: PanelContainer
var upgrades_panel: PanelContainer
var storage_panel: PanelContainer
var build_panel: Control          # catálogo de construcción (FactoryUI), cerrado por defecto
var menu_panel: PanelContainer    # menú principal desplegable
var _right_panels: Array = []

var _toasts: VBoxContainer

func _ready() -> void:
	call_deferred("_build_ui")

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_topbar()
	_build_left_menu()
	_build_right_panels()
	_build_bottom_bar()
	_build_tutorial()
	_build_objective_tracker()
	_build_build_help()
	_build_toasts()
	_connect_signals()
	_refresh_hud()
	_refresh_objective_tracker()
	# El HUD/UI del juego SOLO se ve dentro de la partida, no en el menú principal.
	layer.visible = false
	EventBus.world_ready.connect(_on_enter_game)

func _on_enter_game() -> void:
	if layer:
		layer.visible = true
	_refresh_objective_tracker()
	# Bienvenida temporal sólo en partida nueva (desaparece sola).
	if not GameManager.pending_load:
		_show_intro()

# --- Banner del tutorial (centro superior) ----------------------------------
func _build_tutorial() -> void:
	_tutorial_banner = UITheme.make_panel(UITheme.BG)
	_tutorial_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tutorial_banner.offset_top = 58
	_tutorial_banner.offset_left = -300
	_tutorial_banner.offset_right = 300
	_tutorial_banner.visible = false
	root.add_child(_tutorial_banner)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_tutorial_banner.add_child(h)
	var icon := UITheme.make_label("🎓", 18)
	h.add_child(icon)
	_tutorial_label = UITheme.make_label("", 14, UITheme.TEXT)
	_tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_label.custom_minimum_size = Vector2(460, 0)
	h.add_child(_tutorial_label)
	var skip := UITheme.make_button("Saltar")
	skip.pressed.connect(func(): GameManager.tutorial.skip())
	h.add_child(skip)

func _on_tutorial_step(text: String, index: int, total: int) -> void:
	if _tutorial_banner == null:
		return
	_tutorial_banner.visible = true
	_tutorial_label.text = "Paso %d/%d — %s" % [index, total, text]
	_refresh_objective_tracker()

func _on_tutorial_finished() -> void:
	if _tutorial_banner:
		_tutorial_banner.visible = false
	_refresh_objective_tracker()

# --- Rastreador compacto de objetivo actual (centro superior, discreto) -----
func _build_objective_tracker() -> void:
	_obj_tracker = UITheme.make_panel(UITheme.BG)
	_obj_tracker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_obj_tracker.offset_top = 58
	_obj_tracker.offset_left = -260
	_obj_tracker.offset_right = 260
	_obj_tracker.visible = false
	root.add_child(_obj_tracker)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_obj_tracker.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UITheme.make_label("🎯", 16))
	_obj_title = UITheme.make_label("", 14, UITheme.TEXT)
	_obj_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_title.custom_minimum_size = Vector2(360, 0)
	top.add_child(_obj_title)
	_obj_progress = UITheme.make_label("", 13, UITheme.ACCENT2)
	top.add_child(_obj_progress)
	var see := UITheme.make_button("VER")
	see.custom_minimum_size = Vector2(52, 26)
	see.pressed.connect(func(): _toggle_right(objectives_panel); _refresh_objectives())
	top.add_child(see)
	v.add_child(top)
	_obj_bar = ProgressBar.new()
	_obj_bar.max_value = 100
	_obj_bar.show_percentage = false
	_obj_bar.custom_minimum_size = Vector2(0, 6)
	_obj_bar.visible = false
	v.add_child(_obj_bar)

func _refresh_objective_tracker() -> void:
	if _obj_tracker == null:
		return
	# No competir con el banner del tutorial: éste guía los primeros pasos.
	if _tutorial_banner and _tutorial_banner.visible:
		_obj_tracker.visible = false
		return
	var o: Dictionary = GameManager.objectives.current()
	if o.is_empty():
		_obj_tracker.visible = false
		return
	_obj_tracker.visible = true
	var reward := int(o.get("reward", 0))
	var suffix := "  ·  +%s" % Fmt.money(reward) if reward > 0 else ""
	_obj_title.text = String(o["title"]) + suffix
	var ptext: String = GameManager.objectives.progress_text(o)
	_obj_progress.text = ptext
	if o.has("target"):
		_obj_bar.visible = true
		_obj_bar.value = GameManager.objectives.progress_ratio(o) * 100.0
	else:
		_obj_bar.visible = false

# --- Barra superior ---------------------------------------------------------
func _build_topbar() -> void:
	var bar := UITheme.make_panel(UITheme.BG)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	bar.add_child(h)

	# Botón de MENÚ (hamburguesa) — prominente y siempre visible, primer elemento
	# de la barra superior. Antes vivía en una barra inferior con rect de altura
	# negativa (preset BOTTOM_LEFT + offsets) que lo dejaba fuera de pantalla.
	var menu_btn := UITheme.make_primary_button("☰  MENÚ")
	menu_btn.custom_minimum_size = Vector2(120, 40)
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.tooltip_text = "Menú principal (Fábrica, Producción, Economía, Contratos…)"
	menu_btn.pressed.connect(_toggle_menu)
	h.add_child(menu_btn)
	h.add_child(_vsep())

	# HUD mínimo: sólo lo esencial permanente (el resto vive en los menús).
	_money_lbl = _stat(h, UITheme.ACCENT2, 110)
	_level_lbl = _stat(h, UITheme.ACCENT, 170)
	_clock_lbl = _stat(h, UITheme.TEXT, 150)
	_power_lbl = _stat(h, UITheme.ACCENT, 130)
	# valor/deuda/reputación se consultan en el panel de Economía (no en el HUD).
	_value_lbl = null
	_debt_lbl = null
	_rep_lbl = null

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_mode_lbl = UITheme.make_label("", 13, UITheme.WARN)
	h.add_child(_mode_lbl)
	h.add_child(_vsep())

	# Controles de velocidad.
	for item in [["⏸", 0.0], ["▶", 1.0], ["▶▶", 2.0], ["▶▶▶", 3.0]]:
		var b := UITheme.make_button(String(item[0]))
		b.custom_minimum_size = Vector2(44, 30)
		b.pressed.connect(TimeManager.set_time_scale.bind(float(item[1])))
		h.add_child(b)

func _stat(h: HBoxContainer, color: Color, min_w: int) -> Label:
	var l := UITheme.make_label("", 15, color)
	l.custom_minimum_size = Vector2(min_w, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(UITheme.chip_panel(l))
	return l

func _vsep() -> VSeparator:
	var v := VSeparator.new()
	v.add_theme_constant_override("separation", 8)
	return v

## Valor de fábrica = caja + capital invertido en máquinas y edificios.
func _factory_value() -> float:
	var invested := 0.0
	if GameManager.machines:
		for m in GameManager.machines.machines:
			invested += float(m.def.get("cost", 0))
	if GameManager.buildings:
		for b in GameManager.buildings.buildings:
			invested += float(b.def.get("cost", 0))
	return GameState.money + invested

# --- Catálogo de construcción (cerrado por defecto) -------------------------
func _build_left_menu() -> void:
	build_panel = FactoryUIScript.new()
	build_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	build_panel.offset_left = 8
	build_panel.offset_top = 64
	build_panel.visible = false
	root.add_child(build_panel)

# --- Paneles laterales (derecha) --------------------------------------------
func _build_right_panels() -> void:
	production_ui = ProductionUIScript.new()
	finance_ui = FinanceUIScript.new()
	automation_ui = AutomationUIScript.new()
	contracts_panel = _make_contracts_panel()
	workers_panel = _make_workers_panel()
	objectives_panel = _make_scroll_panel()
	upgrades_panel = _make_scroll_panel()
	storage_panel = _make_scroll_panel()
	for p in [production_ui, finance_ui, automation_ui, contracts_panel, workers_panel, objectives_panel, upgrades_panel, storage_panel]:
		p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		p.offset_right = -8
		p.offset_top = 64
		p.offset_left = -360
		root.add_child(p)
		_right_panels.append(p)

func _toggle_right(panel: Control) -> void:
	var show := not panel.visible
	for p in _right_panels:
		if p != production_ui:
			p.visible = false
	panel.visible = show

# --- Sistema de menú desplegable (abre desde el botón ☰ de la barra superior) -
func _build_bottom_bar() -> void:
	_build_menu_panel()
	# El catálogo de construcción se cierra al salir del modo construcción.
	EventBus.build_mode_changed.connect(func(active, _k):
		if not active and build_panel:
			build_panel.visible = false)

var _menu_box: VBoxContainer

func _build_menu_panel() -> void:
	menu_panel = UITheme.make_panel(UITheme.BG)
	menu_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu_panel.offset_left = 8
	menu_panel.offset_top = 58           # justo debajo de la barra superior
	menu_panel.custom_minimum_size = Vector2(250, 0)
	menu_panel.visible = false
	root.add_child(menu_panel)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 3)
	menu_panel.add_child(_menu_box)
	_render_menu_root()

## Menú principal: centro de navegación con submenús por categoría (spec §27/§28).
func _render_menu_root() -> void:
	_clear_menu()
	_menu_box.add_child(UITheme.make_title("INDUSTRIA"))
	_menu_cat("🏭  Fábrica", "Fábrica", [
		["🏗  Construcción", _on_construction],
		["🗺  Expansión de terreno", _on_upgrades],
		["ℹ  Información de la empresa", _on_factory_info],
	])
	_menu_cat("⚙  Producción", "Producción", [
		["🏭  Máquinas (seleccioná una)", _on_machines_help],
		["📦  Almacén", _on_storage],
		["🚚  Logística / Reglas", _on_automation],
	])
	_menu_act("👷  Personal", _on_workers)
	_menu_cat("💰  Economía", "Economía", [
		["💵  Finanzas", _on_finance],
		["📈  Mercado", _on_finance],
		["📊  Informe semanal", _on_week_report],
	])
	_menu_act("🔬  Tecnología", _on_upgrades)
	_menu_cat("📋  Contratos", "Contratos", [
		["📥  Disponibles y activos", _on_contracts],
	])
	_menu_act("🎯  Objetivos / Progreso", _on_objectives)
	_menu_act("💾  Guardar", _on_save)
	_menu_act("⚙  Ajustes", _on_config)

func _render_submenu(title: String, items: Array) -> void:
	_clear_menu()
	var back := UITheme.make_button("‹  Volver")
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.custom_minimum_size = Vector2(0, 30)
	back.pressed.connect(_render_menu_root)
	_menu_box.add_child(back)
	_menu_box.add_child(UITheme.make_label(title.to_upper(), 12, UITheme.ACCENT))
	for it in items:
		var label: String = it[0]
		var cb: Callable = it[1]
		_menu_leaf(label, cb)

func _clear_menu() -> void:
	for c in _menu_box.get_children():
		c.queue_free()

## Categoría que abre un submenú (no cierra el menú).
func _menu_cat(text: String, title: String, items: Array) -> void:
	var b := UITheme.make_button(text + "   ›")
	b.custom_minimum_size = Vector2(0, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): _render_submenu(title, items))
	_menu_box.add_child(b)

## Acción directa de nivel raíz (cierra el menú y ejecuta).
func _menu_act(text: String, cb: Callable) -> void:
	var b := UITheme.make_button(text)
	b.custom_minimum_size = Vector2(0, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		menu_panel.visible = false
		cb.call())
	_menu_box.add_child(b)

## Hoja de un submenú (cierra el menú y ejecuta).
func _menu_leaf(text: String, cb: Callable) -> void:
	var b := UITheme.make_button(text)
	b.custom_minimum_size = Vector2(0, 30)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		menu_panel.visible = false
		cb.call())
	_menu_box.add_child(b)

func _on_factory_info() -> void:
	var machines: int = GameManager.machines.count() if GameManager.machines else 0
	var brand: String = GameManager.specialization.branch_name() if GameManager.specialization.has_chosen() else "sin elegir"
	EventBus.notify.emit("%s · Nivel %d (%s) · Rama: %s · %d máquinas · Valor %s" % [
		GameState.company_name, GameState.company_level, GameManager.progression.level_name(),
		brand, machines, Fmt.money(_factory_value())], "info")

func _on_machines_help() -> void:
	EventBus.notify.emit("Seleccioná una máquina en el mundo para ver y ajustar su panel.", "info")

func _on_week_report() -> void:
	var last: Dictionary = GameManager.week.last_summary if GameManager.week else {}
	if last.is_empty():
		EventBus.notify.emit("Aún no cerró la primera semana. El informe aparecerá al completarla.", "info")
	else:
		_show_week_summary(last)

func _toggle_menu() -> void:
	if menu_panel:
		menu_panel.visible = not menu_panel.visible
		if menu_panel.visible:
			_render_menu_root()   # siempre abre en el nivel raíz

func _on_construction() -> void:
	if build_panel:
		build_panel.visible = not build_panel.visible

func _on_energy() -> void:
	EventBus.notify.emit("Energía: usá el HUD (⚡) y coloca Generador/Subestación desde Construcción.", "info")

func _on_save() -> void:
	GameManager.save.save_game()
	EventBus.notify.emit("Partida guardada.", "success")

func _on_config() -> void:
	EventBus.notify.emit("Ajustes: la partida se guarda con 💾 Guardar y automáticamente cada 2 días.", "info")

func _on_finance() -> void: _toggle_right(finance_ui)
func _on_contracts() -> void: _toggle_right(contracts_panel); _refresh_contracts()
func _on_workers() -> void: _toggle_right(workers_panel); _refresh_workers()
func _on_automation() -> void: _toggle_right(automation_ui)
func _on_objectives() -> void: _toggle_right(objectives_panel); _refresh_objectives()
func _on_upgrades() -> void: _toggle_right(upgrades_panel); _refresh_upgrades()
func _on_storage() -> void: _toggle_right(storage_panel); _refresh_storage()

# --- Toasts -----------------------------------------------------------------
func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toasts.offset_bottom = -56
	_toasts.offset_left = 220
	_toasts.offset_right = -220
	_toasts.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_toasts)

func _on_notify(message: String, level: String) -> void:
	var p := UITheme.make_panel(UITheme.BG_SOFT)
	var color := UITheme.TEXT
	match level:
		"success": color = UITheme.ACCENT2
		"warning": color = UITheme.WARN
		"error": color = UITheme.DANGER
	p.add_child(UITheme.make_label(message, 13, color))
	p.modulate.a = 1.0
	_toasts.add_child(p)
	if _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.0)
	tw.tween_callback(p.queue_free)

# --- Señales / HUD ----------------------------------------------------------
func _connect_signals() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.debt_changed.connect(func(_d): _refresh_hud())
	EventBus.reputation_changed.connect(func(_r): _refresh_hud())
	EventBus.minute_passed.connect(func(_a, _b, _c): _refresh_hud())
	EventBus.power_changed.connect(func(_c, _cap): _refresh_hud())
	EventBus.notify.connect(_on_notify)
	EventBus.build_mode_changed.connect(_on_build_mode)
	EventBus.contract_offered.connect(func(_c): _refresh_contracts())
	EventBus.contract_accepted.connect(func(_c): _refresh_contracts())
	EventBus.contract_completed.connect(func(_c): _refresh_contracts())
	EventBus.contract_failed.connect(func(_c): _refresh_contracts())
	EventBus.worker_hired.connect(func(_w): _refresh_workers())
	EventBus.worker_fired.connect(func(_w): _refresh_workers())
	EventBus.candidates_changed.connect(_refresh_workers)
	EventBus.staff_updated.connect(_refresh_workers)
	EventBus.objectives_updated.connect(_on_objectives_updated)
	EventBus.game_won.connect(_on_game_won)
	EventBus.week_summary.connect(_show_week_summary)
	EventBus.decision_requested.connect(_show_decision)
	EventBus.minute_passed.connect(func(_a, _b, _c): _refresh_storage())
	EventBus.tutorial_step_changed.connect(_on_tutorial_step)
	EventBus.tutorial_finished.connect(_on_tutorial_finished)
	EventBus.company_level_changed.connect(_on_level_changed)
	EventBus.branch_chosen.connect(_on_branch_chosen)
	EventBus.objective_completed.connect(_on_objective_completed)

var _branch_prompted: bool = false
func _on_level_changed(level: int, _name: String) -> void:
	_refresh_hud()
	# Al llegar a Nivel 2 se ofrece elegir la rama industrial (spec §9).
	if level >= 2 and not _branch_prompted and not GameManager.specialization.has_chosen():
		_branch_prompted = true
		_show_branch_choice()

func _on_objectives_updated() -> void:
	_refresh_objective_tracker()
	_refresh_objectives()

# --- Hitos: banner breve "NUEVO DESBLOQUEO" (spec §5, §7) --------------------
const _TECH_BRANCH_LABELS := {
	"produccion": "⚙  PRODUCCIÓN — velocidad (a costa de energía)",
	"eficiencia": "⚡  EFICIENCIA — menos consumo y desgaste",
	"logistica": "🚚  LOGÍSTICA — transporte y líneas largas",
	"capacidad": "📦  CAPACIDAD — almacenamiento",
	"comercial": "💰  COMERCIAL — mejor precio de venta",
}

const _MILESTONES := {
	"first_machine": "Producción industrial habilitada",
	"automate": "Automatización: la fábrica se alimenta sola",
	"line": "Primera línea de producción",
	"expand": "Terreno ampliado",
	"contract": "Primer contrato cumplido",
	"hire": "Primer trabajador contratado",
	"top": "¡Complejo industrial!",
}

func _on_branch_chosen(id: String, name: String) -> void:
	_refresh_hud()
	_refresh_upgrades()
	_milestone_banner("NUEVA RAMA INDUSTRIAL", "%s %s  ·  +25%% a tus máquinas" % [GameManager.specialization.branch_icon(id), name])

func _on_objective_completed(id: String, _title: String) -> void:
	if _MILESTONES.has(id):
		_milestone_banner("NUEVO HITO", String(_MILESTONES[id]))

func _milestone_banner(title: String, subtitle: String) -> void:
	var panel := UITheme.make_panel(UITheme.BG)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 96
	panel.offset_left = -220
	panel.offset_right = 220
	panel.modulate.a = 0.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var t := UITheme.make_label("━━  %s  ━━" % title, 12, UITheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UITheme.make_label(subtitle, 16, UITheme.ACCENT2)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	root.add_child(panel)
	# Aparece, se mantiene y se desvanece (elegante, no bloquea el juego).
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_free_node.bind(panel))

func _refresh_hud() -> void:
	if _money_lbl == null:
		return
	_money_lbl.text = "💰 " + Fmt.money(GameState.money)
	if _value_lbl: _value_lbl.text = "🏭 " + Fmt.money(_factory_value())
	if _debt_lbl: _debt_lbl.text = "🏦 " + Fmt.money(GameState.debt)
	if _rep_lbl: _rep_lbl.text = "⭐ %d" % GameState.reputation
	var brand := ""
	if GameManager.specialization and GameManager.specialization.has_chosen():
		brand = " " + GameManager.specialization.branch_icon()
	_level_lbl.text = "🏢 N%d · %s%s" % [GameState.company_level, GameManager.progression.level_name(), brand]
	_clock_lbl.text = "📅 " + TimeManager.get_clock_string()
	var ps: Dictionary = GameManager.power.get_status()
	var cons: float = ps["consumption"]
	var cap: float = ps["capacity"]
	_power_lbl.text = "⚡ %d/%d kW" % [int(cons), int(cap)]
	# Feedback de energía: verde ok, amarillo cerca del límite, rojo sobrecarga.
	var pcol := UITheme.ACCENT2
	if ps["overload"]:
		pcol = UITheme.DANGER
	elif cap > 0 and cons / cap > 0.8:
		pcol = UITheme.WARN
	_power_lbl.add_theme_color_override("font_color", pcol)

func _on_money_changed(_m: float) -> void:
	_refresh_hud()
	_refresh_upgrades()
	_refresh_objective_tracker()
	# Destello de la caja al cambiar (feedback discreto).
	if _money_lbl:
		_money_lbl.modulate = Color(1.4, 1.4, 1.0)
		var tw := create_tween()
		tw.tween_property(_money_lbl, "modulate", Color(1, 1, 1), 0.4)

func _on_build_mode(active: bool, kind: String) -> void:
	_mode_lbl.text = "🔨 Construyendo" if active else ""
	_update_build_help(active, kind)

# --- Ayuda contextual del modo construcción (sólo mientras construyo) --------
func _build_build_help() -> void:
	_build_help = UITheme.make_panel(UITheme.BG)
	_build_help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_help.offset_bottom = -18
	_build_help.offset_left = -230
	_build_help.offset_right = 230
	_build_help.visible = false
	root.add_child(_build_help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_build_help.add_child(v)
	_build_help_title = UITheme.make_label("", 14, UITheme.ACCENT)
	_build_help_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_build_help_title)
	var hint := UITheme.make_label("🖱 Izq: Construir    R: Rotar    ESC / Clic der.: Cancelar", 12, UITheme.TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

func _update_build_help(active: bool, kind: String) -> void:
	if _build_help == null:
		return
	_build_help.visible = active
	if active:
		_build_help_title.text = "🔨 %s" % _build_kind_label(kind)

func _build_kind_label(kind: String) -> String:
	if kind.begins_with("machine:"):
		return GameManager.recipes.machine_name(kind.trim_prefix("machine:"))
	if kind.begins_with("building:"):
		var bid := kind.trim_prefix("building:")
		return String(_all_buildings_def().get(bid, {}).get("name", bid))
	match kind:
		"conveyor": return "Cinta transportadora"
		"delete": return "Eliminar (clic sobre una construcción)"
	return kind

func _all_buildings_def() -> Dictionary:
	var path := "res://data/buildings/buildings.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("buildings", {}) if data is Dictionary else {}

## ESC/entrada global de UI: cierra menú o panel SÓLO si no estoy construyendo
## (si construyo, el BuildController ya cancela primero). Evita conflictos §42.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if GameManager.world and ("build_controller" in GameManager.world) \
			and GameManager.world.build_controller and GameManager.world.build_controller.is_building():
		return   # el BuildController cancela la construcción; no tocamos la UI
	if menu_panel and menu_panel.visible:
		menu_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	for p in _right_panels:
		if p.visible:
			p.visible = false
			get_viewport().set_input_as_handled()
			return

# --- Panel de contratos -----------------------------------------------------
func _make_contracts_panel() -> PanelContainer:
	var p := UITheme.make_panel()
	p.custom_minimum_size = Vector2(360, 0)
	p.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 520)
	p.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return p

func _refresh_contracts() -> void:
	if contracts_panel == null:
		return
	var box := _find_box(contracts_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Contratos"))
	box.add_child(UITheme.make_label("Ofertas:", 13, UITheme.ACCENT))
	for c in GameManager.contracts.offers:
		box.add_child(_offer_row(c))
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Activos:", 13, UITheme.ACCENT2))
	for c in GameManager.contracts.active:
		var t := "%s — %d/%d %s · %s · %d días" % [c.client, c.delivered, c.amount, ItemDB.display_name(c.product), Fmt.money(c.payment), c.days_left()]
		box.add_child(UITheme.make_label(t, 12))

func _offer_row(c: Contract) -> VBoxContainer:
	var v := VBoxContainer.new()
	var tag: String = GameManager.contracts.type_label(c)
	var tcol := UITheme.WARN if c.type == "urgente" else (UITheme.ACCENT2 if c.type == "rentable" else UITheme.ACCENT)
	var head := "%s · %s" % [tag, c.client]
	if c.program_phase > 0:
		head += "  (Fase %d/%d)" % [c.program_phase, c.program_total]
	v.add_child(UITheme.make_label(head, 13, tcol))
	var info := "%d× %s · Paga %s · Plazo %d días" % [c.amount, ItemDB.display_name(c.product), Fmt.money(c.payment), c.deadline_days]
	v.add_child(UITheme.make_label(info, 12))
	var terms := "⏱ Bonus antes de plazo +%s   ·   ⚠ Penalización %s" % [Fmt.money(c.bonus), Fmt.money(c.penalty)]
	v.add_child(UITheme.make_label(terms, 11, UITheme.MUTED))
	# Chequeo de capacidad: ¿tu fábrica llega? (spec §7: decisión real).
	var f: Dictionary = GameManager.contracts.feasibility(c)
	var verdict := ""
	var vcol := UITheme.ACCENT2
	if bool(f["feasible"]):
		verdict = "✅ Tu capacidad alcanza (%.0f u/min, en stock %d)" % [float(f["rate"]), int(f["stock"])]
	else:
		verdict = "⚠ Falta capacidad: necesitás ~%.0f u/min, producís %.0f (¿otra máquina o automatizar?)" % [float(f["needed"]), float(f["rate"])]
		vcol = UITheme.WARN
	var vl := UITheme.make_label(verdict, 11, vcol)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.custom_minimum_size = Vector2(320, 0)
	v.add_child(vl)
	var row := HBoxContainer.new()
	var acc := UITheme.make_button("Aceptar")
	acc.pressed.connect(GameManager.contracts.accept.bind(c))
	var dec := UITheme.make_button("Rechazar")
	dec.pressed.connect(GameManager.contracts.decline.bind(c))
	row.add_child(acc)
	row.add_child(dec)
	v.add_child(row)
	v.add_child(UITheme.hsep())
	return v

# --- Panel de personal ------------------------------------------------------
func _make_workers_panel() -> PanelContainer:
	var p := UITheme.make_panel()
	p.custom_minimum_size = Vector2(340, 0)
	p.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 520)
	p.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return p

func _refresh_workers() -> void:
	if workers_panel == null or not workers_panel.visible:
		return
	var box := _find_box(workers_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Personal"))
	var wm: Node = GameManager.workers
	var full: bool = wm.at_capacity()
	box.add_child(UITheme.make_label("Cupo: %d / %d empleados · Salarios: %s/semana" % [wm.workers.size(), wm.max_employees(), Fmt.money(wm.weekly_salary_total())], 13, UITheme.WARN if full else UITheme.ACCENT2))
	# --- Mercado laboral (candidatos) ---
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("🧑‍💼 MERCADO LABORAL (cambia cada semana)", 12, UITheme.ACCENT))
	if full:
		box.add_child(UITheme.make_label("Límite alcanzado: subí el nivel de tu fábrica para contratar más.", 11, UITheme.WARN))
	for i in wm.candidates.size():
		box.add_child(_candidate_card(i, wm.candidates[i], full))
	# --- Plantilla actual ---
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("👥 TU PLANTILLA", 12, UITheme.ACCENT2))
	if wm.workers.is_empty():
		box.add_child(UITheme.make_label("Todavía no tenés empleados. Al principio trabajás vos.", 11, UITheme.MUTED))
	for w in wm.workers:
		box.add_child(_worker_card(w))

func _stars(w, skill: String) -> String:
	var n: int = w.star(skill)
	return "★".repeat(n) + "☆".repeat(5 - n)

func _skill_block(w) -> String:
	return "Prod %s  Vel %s\nCal %s  Log %s  Mant %s" % [
		_stars(w, "production"), _stars(w, "speed"), _stars(w, "quality"),
		_stars(w, "logistics"), _stars(w, "maintenance")]

func _candidate_card(index: int, c: Dictionary, full: bool) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var role := String(GameManager.workers.types.get(c.get("type_id", ""), {}).get("name", c.get("type_id", "")))
	var tr := String(c.get("trait", ""))
	var head := "👤 %s — %s%s" % [c.get("name", "?"), role, ("  «%s»" % tr) if tr != "" else ""]
	v.add_child(UITheme.make_label(head, 13, UITheme.TEXT))
	# Estrellas a partir del dict de skills.
	var sk: Dictionary = c.get("skills", {})
	var line := "Prod %s  Vel %s  Cal %s" % [_star_str(sk.get("production", 0.5)), _star_str(sk.get("speed", 0.5)), _star_str(sk.get("quality", 0.5))]
	v.add_child(UITheme.make_label(line, 11, UITheme.MUTED))
	var row := HBoxContainer.new()
	row.add_child(UITheme.make_label("%s/sem" % Fmt.money(c.get("salary", 0)), 12, UITheme.ACCENT))
	var hire_btn := UITheme.make_button("Contratar")
	hire_btn.disabled = full or not GameManager.economy.can_afford(float(c.get("salary", 400)) * 0.5)
	hire_btn.pressed.connect(func(): GameManager.workers.hire_candidate(index, true))
	row.add_child(hire_btn)
	v.add_child(row)
	v.add_child(UITheme.hsep())
	return v

func _star_str(v: float) -> String:
	var n: int = clampi(int(round(v * 5.0)), 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)

func _worker_card(w) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var tr := ("  «%s»" % w.trait_name) if w.trait_name != "" else ""
	v.add_child(UITheme.make_label("👤 %s%s  ·  %s/sem  ·  exp %d" % [w.worker_name, tr, Fmt.money(w.salary), int(w.experience)], 12, UITheme.TEXT))
	var sl := UITheme.make_label(_skill_block(w), 11, UITheme.MUTED)
	v.add_child(sl)
	# Asignación a máquina (dropdown: sin asignar + máquinas).
	var row := HBoxContainer.new()
	row.add_child(UITheme.make_label("Trabaja en:", 11))
	var opt := OptionButton.new()
	opt.add_item("Sin asignar", 0)
	var idmap: Array = [0]
	if GameManager.machines:
		for m in GameManager.machines.machines:
			opt.add_item(m.display_name(), m.uid)
			idmap.append(m.uid)
			if w.assigned_uid == m.uid:
				opt.select(idmap.size() - 1)
	opt.item_selected.connect(func(idx: int): GameManager.workers.assign(w, int(idmap[idx])); _refresh_workers())
	row.add_child(opt)
	var fire := UITheme.make_button("Despedir")
	fire.pressed.connect(func(): GameManager.workers.fire(w); _refresh_workers())
	row.add_child(fire)
	v.add_child(row)
	v.add_child(UITheme.hsep())
	return v

func _worker_effect(specialty: String) -> String:
	match specialty:
		"production": return "+6% producción"
		"maintenance": return "reparaciones más baratas"
		"quality": return "+3% calidad"
		"logistics": return "+ logística"
		_: return "personal"

func _find_box(panel: PanelContainer) -> VBoxContainer:
	for child in panel.get_children():
		if child is ScrollContainer and child.get_child_count() > 0:
			return child.get_child(0)
	return null

# --- Panel genérico con scroll ----------------------------------------------
func _make_scroll_panel() -> PanelContainer:
	var p := UITheme.make_panel()
	p.custom_minimum_size = Vector2(340, 0)
	p.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 520)
	p.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return p

# --- Panel de objetivos -----------------------------------------------------
func _refresh_objectives() -> void:
	# Sólo se reconstruye cuando está a la vista (evita trabajo de UI oculto, §17).
	if objectives_panel == null or not objectives_panel.visible:
		return
	var box := _find_box(objectives_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Objetivos"))
	box.add_child(UITheme.make_label("Nivel de empresa: %s (N%d)" % [GameManager.progression.level_name(), GameState.company_level], 12, UITheme.ACCENT2))
	# Meta de mediano plazo: requisitos para el próximo nivel (spec §8/§9).
	var nr: Dictionary = GameManager.progression.next_requirement()
	if not nr.is_empty():
		box.add_child(UITheme.make_label("🏁 META: llegar a Nivel %d (%s)" % [int(nr["level"]), nr["name"]], 12, UITheme.ACCENT))
		box.add_child(_req_row("Valor de fábrica", nr["value"][0], nr["value"][1], true))
		box.add_child(_req_row("Máquinas", nr["machines"][0], nr["machines"][1], false))
		box.add_child(_req_row("Contratos completados", nr["contracts"][0], nr["contracts"][1], false))
	else:
		box.add_child(UITheme.make_label("🏢 Nivel máximo — modo libre.", 12, UITheme.ACCENT2))
	# Objetivo actual destacado con su pista (qué hacer y por qué).
	var cur: Dictionary = GameManager.objectives.current()
	if not cur.is_empty():
		box.add_child(UITheme.hsep())
		box.add_child(UITheme.make_label("🎯 OBJETIVO ACTUAL", 11, UITheme.ACCENT))
		var ct := String(cur["title"])
		if cur.has("target"):
			ct += "   [%s]" % GameManager.objectives.progress_text(cur)
		box.add_child(UITheme.make_label(ct, 14, UITheme.TEXT))
		var hint := UITheme.make_label(String(cur.get("hint", "")), 12, UITheme.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(300, 0)
		box.add_child(hint)
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("PRINCIPALES", 11, UITheme.ACCENT))
	for o in GameManager.objectives.objectives:
		if o.get("long", false):
			continue
		box.add_child(_objective_row(o))
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("METAS DE LARGO PLAZO", 11, UITheme.ACCENT))
	for o in GameManager.objectives.objectives:
		if o.get("long", false):
			box.add_child(_objective_row(o))
	var done: int = GameManager.objectives.completed_count()
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Progreso: %d / %d" % [done, GameManager.objectives.objectives.size()], 13, UITheme.ACCENT))

## Fila de requisito con marca ✓/⬜ y progreso, para la meta de nivel.
func _req_row(label: String, cur: float, need: float, money: bool) -> Label:
	var done: bool = cur >= need
	var cur_s: String = Fmt.money(cur) if money else str(int(cur))
	var need_s: String = Fmt.money(need) if money else str(int(need))
	var mark := "✅" if done else "⬜"
	return UITheme.make_label("%s %s: %s / %s" % [mark, label, cur_s, need_s], 12,
		UITheme.ACCENT2 if done else UITheme.TEXT)

func _objective_row(o: Dictionary) -> Label:
	var mark := "✅" if o["done"] else "⬜"
	var color := UITheme.ACCENT2 if o["done"] else UITheme.TEXT
	var reward := int(o.get("reward", 0))
	var suffix := "  (+%s)" % Fmt.money(reward) if reward > 0 else ""
	var prog := ""
	if not o["done"] and o.has("target"):
		prog = "   [%s]" % GameManager.objectives.progress_text(o)
	var l := UITheme.make_label("%s  %s%s%s" % [mark, o["title"], prog, suffix], 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l

# --- Panel de mejoras -------------------------------------------------------
func _refresh_upgrades() -> void:
	if upgrades_panel == null or not upgrades_panel.visible:
		return
	var box := _find_box(upgrades_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Tecnología"))
	box.add_child(_branch_block())
	box.add_child(UITheme.hsep())
	box.add_child(_expansion_block())
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("🔬 ÁRBOL TECNOLÓGICO", 12, UITheme.ACCENT))
	box.add_child(UITheme.make_label("✅ adquirida   🔓 disponible   🔒 bloqueada", 10, UITheme.MUTED))
	var um: Node = GameManager.upgrades
	# Construye el árbol a partir del campo "requires" de cada mejora.
	var children: Dictionary = {}
	var roots: Array = []
	for id in um.defs.keys():
		var req := String(um.defs[id].get("requires", ""))
		if req == "":
			roots.append(id)
		else:
			if not children.has(req):
				children[req] = []
			children[req].append(id)
	var last_branch := ""
	for r in roots:
		var br := String(um.defs[r].get("branch", ""))
		if br != last_branch:
			last_branch = br
			box.add_child(UITheme.make_label(_TECH_BRANCH_LABELS.get(br, br.to_upper()), 12, UITheme.ACCENT))
		_tech_node(box, um, String(r), children, 0)

## Renderiza un nodo del árbol tecnológico y sus hijos (recursivo, con sangría).
func _tech_node(box: VBoxContainer, um: Node, id: String, children: Dictionary, depth: int) -> void:
	var d: Dictionary = um.defs[id]
	var owned: bool = um.is_owned(id)
	var avail: bool = um.is_available(id)
	var icon := "✅" if owned else ("🔓" if avail else "🔒")
	var col := UITheme.ACCENT2 if owned else (UITheme.TEXT if avail else Color(0.5, 0.5, 0.55))
	var pad := ""
	for i in range(depth):
		pad += "   "
	var connector := (pad + "└─ ") if depth > 0 else ""
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.add_child(UITheme.make_label("%s%s %s" % [connector, icon, String(d.get("name", id))], 13, col))
	var desc := UITheme.make_label(pad + "   " + String(d.get("description", "")), 10, UITheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 0)
	v.add_child(desc)
	if avail and not owned:
		var b := UITheme.make_button("Investigar (%s)" % Fmt.money(um.cost(id)))
		b.disabled = not GameManager.economy.can_afford(um.cost(id))
		b.pressed.connect(_on_buy_upgrade.bind(id))
		v.add_child(b)
	box.add_child(v)
	for ch in children.get(id, []):
		_tech_node(box, um, String(ch), children, depth + 1)

func _on_buy_upgrade(id: String) -> void:
	GameManager.upgrades.buy(id)
	_refresh_upgrades()

## Bloque de rama industrial (spec §8): elegir/ver la especialización.
func _branch_block() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(UITheme.make_label("🏭 RAMA INDUSTRIAL", 12, UITheme.ACCENT))
	var spec := GameManager.specialization
	if spec.has_chosen():
		v.add_child(UITheme.make_label("%s %s (+25%% a tus máquinas)" % [spec.branch_icon(), spec.branch_name()], 13, UITheme.ACCENT2))
		return v
	if GameState.company_level < 2:
		v.add_child(UITheme.make_label("Se elige al alcanzar el Nivel 2.", 12, UITheme.MUTED))
		return v
	v.add_child(UITheme.make_label("Elegí tu especialización:", 12))
	for id in spec.BRANCHES.keys():
		var b: Dictionary = spec.BRANCHES[id]
		var btn := UITheme.make_button("%s  %s" % [b["icon"], b["name"]])
		btn.tooltip_text = String(b["tagline"])
		btn.pressed.connect(func():
			spec.choose(String(id))
			_refresh_upgrades())
		v.add_child(btn)
	return v

## Bloque de ampliación de terreno (spec §6/§18): meta económica de crecimiento.
func _expansion_block() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(UITheme.make_label("🗺 TERRENO DE LA FÁBRICA", 12, UITheme.ACCENT))
	var bc: Node = GameManager.world.build_controller if GameManager.world and ("build_controller" in GameManager.world) else null
	var bs: Vector2i = GameState.buildable_size
	v.add_child(UITheme.make_label("Superficie construible: %d×%d celdas" % [bs.x, bs.y], 12))
	if GameManager.grid and GameManager.grid.is_at_max_expansion():
		v.add_child(UITheme.make_label("✅ Terreno al máximo.", 12, UITheme.ACCENT2))
	elif bc:
		var cost: int = bc.expansion_cost()
		var b := UITheme.make_button("Ampliar terreno (%s)" % Fmt.money(cost))
		b.disabled = not GameManager.economy.can_afford(cost)
		b.pressed.connect(func():
			bc.buy_expansion()
			_refresh_upgrades())
		v.add_child(b)
	return v

# --- Panel de almacén / inventario ------------------------------------------
func _refresh_storage() -> void:
	if storage_panel == null or not storage_panel.visible:
		return
	var box := _find_box(storage_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("📦 Almacén de la empresa"))
	var sm: Node = GameManager.storage
	var used: int = sm.total()
	var cap: int = sm.capacity()
	box.add_child(UITheme.make_label("Capacidad", 12, UITheme.ACCENT))
	var bar := ProgressBar.new()
	bar.max_value = cap
	bar.value = used
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	box.add_child(bar)
	var ratio := 0.0 if cap <= 0 else float(used) / float(cap)
	var cap_col := UITheme.DANGER if ratio > 0.9 else (UITheme.WARN if ratio > 0.7 else UITheme.ACCENT2)
	box.add_child(UITheme.make_label("%d / %d (%d%%)" % [used, cap, int(ratio * 100)], 14, cap_col))
	if ratio > 0.95:
		box.add_child(UITheme.make_label("⚠ Almacén casi lleno: la producción puede bloquearse.", 11, UITheme.WARN))
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Materiales almacenados", 12, UITheme.ACCENT))
	var items: Dictionary = sm.stock.provide_peek()
	if items.is_empty():
		box.add_child(UITheme.make_label("(vacío)", 12))
	else:
		# Agrupar por categoría (§32): materias primas, procesados, componentes, finales…
		var groups: Dictionary = {}  # categoría -> Array[id]
		for id in items.keys():
			var cat: String = ItemDB.category(id)
			if cat == "":
				cat = "otros"
			if not groups.has(cat):
				groups[cat] = []
			groups[cat].append(id)
		var cat_names: Dictionary = {
			"minerals": "⛏ Minerales", "metals": "🔩 Metales", "wood": "🪵 Madera",
			"agro": "🌱 Agro", "energy": "⚡ Energía", "chemicals": "🧪 Químicos",
			"materials": "🧱 Materiales", "components": "🔧 Componentes",
			"regulated": "📋 Regulados", "finished": "📦 Productos finales", "otros": "Otros",
		}
		var order: Array = ["minerals", "metals", "wood", "agro", "energy", "chemicals",
			"materials", "components", "regulated", "finished", "otros"]
		for cat in order:
			if not groups.has(cat):
				continue
			box.add_child(UITheme.make_label(String(cat_names.get(cat, cat)), 12, UITheme.ACCENT2))
			for id in groups[cat]:
				var row := HBoxContainer.new()
				var n := UITheme.make_label("  " + ItemDB.display_name(id), 12)
				n.custom_minimum_size = Vector2(180, 0)
				row.add_child(n)
				var q := UITheme.make_label(str(int(items[id])), 12, UITheme.ACCENT2)
				row.add_child(q)
				box.add_child(row)

# --- Victoria ---------------------------------------------------------------
func _on_game_won() -> void:
	var banner := UITheme.make_panel(UITheme.BG)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -260
	banner.offset_right = 260
	banner.offset_top = -110
	banner.offset_bottom = 110
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	banner.add_child(v)
	v.add_child(UITheme.make_label("🏢 COMPLEJO INDUSTRIAL", 26, UITheme.ACCENT2))
	v.add_child(UITheme.make_label("Convertiste un terreno vacío en el mayor complejo industrial de la región.", 14))
	v.add_child(UITheme.make_label("Modo libre: seguí expandiendo, optimizando y cumpliendo contratos…\no empezá una nueva partida y probá otra rama industrial.", 13, UITheme.TEXT))
	var close := UITheme.make_button("Seguir jugando")
	close.pressed.connect(banner.queue_free)
	v.add_child(close)
	root.add_child(banner)

# --- Ayuda inicial ----------------------------------------------------------
func _show_intro() -> void:
	var panel := UITheme.make_panel(UITheme.BG)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -180
	panel.offset_bottom = 180
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.make_title("Industria — Construí. Producí. Crecé."))
	var text := "Tenés un terreno vacío y un pequeño capital. Tu objetivo: convertirlo en una gran industria, desde cero.\n\n" \
		+ "Primeros pasos:\n" \
		+ "1. Abrí ☰ MENÚ (arriba a la izquierda) → 🏭 Fábrica y construí tu Banco de trabajo.\n" \
		+ "2. Comprá chatarra en 💰 Economía, seleccioná el banco y pulsá ▶ Producir (VOS trabajás).\n" \
		+ "3. Vendé tus herramientas para conseguir tus primeros ingresos.\n" \
		+ "4. Crecé, contratá un operario para que produzca solo y automatizá con cintas.\n\n" \
		+ "Cámara: WASD/bordes mover · Q/E rotar · rueda zoom.\n" \
		+ "Construcción: R rota · Esc cancela.  ·  Velocidad: ⏸ ▶ ▶▶ ▶▶▶ arriba a la derecha.\n" \
		+ "Seguí el objetivo 🎯 arriba en el centro: siempre te dice qué hacer."
	var lbl := UITheme.make_label(text, 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(560, 0)
	v.add_child(lbl)
	var close := UITheme.make_primary_button("¡Empezar!")
	close.pressed.connect(panel.queue_free)
	v.add_child(close)
	root.add_child(panel)
	# Se cierra sola tras unos segundos (mensaje temporal, no permanente).
	var tw := create_tween()
	tw.tween_interval(9.0)
	tw.tween_callback(_free_node.bind(panel))

func _free_node(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()

# --- Evento con decisión (spec §1/§2) ---------------------------------------
func _show_decision(title: String, description: String, options: Array) -> void:
	var panel := UITheme.make_panel(UITheme.BG)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240; panel.offset_right = 240
	panel.offset_top = -150; panel.offset_bottom = 150
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.make_label(title, 18, UITheme.ACCENT))
	var d := UITheme.make_label(description, 13, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(440, 0)
	v.add_child(d)
	v.add_child(UITheme.hsep())
	for opt in options:
		var b := UITheme.make_button(String(opt.get("label", "OK")))
		b.custom_minimum_size = Vector2(0, 38)
		var action: Callable = opt.get("action", Callable())
		b.pressed.connect(func():
			if action.is_valid():
				action.call()
			_free_node(panel))
		v.add_child(b)
	root.add_child(panel)

# --- Resumen semanal (spec §16-§19) -----------------------------------------
var _week_prev_scale: float = 1.0
func _show_week_summary(d: Dictionary) -> void:
	# Pausa el juego: el cierre de semana es un momento de planificación.
	_week_prev_scale = TimeManager.time_scale
	TimeManager.set_time_scale(0.0)
	var panel := UITheme.make_panel(UITheme.BG)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260; panel.offset_right = 260
	panel.offset_top = -250; panel.offset_bottom = 250
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 480)
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := UITheme.make_label("SEMANA %d — RESUMEN INDUSTRIAL" % int(d["week"]), 22, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(UITheme.hsep())
	var profit: float = d["profit"]
	var pcol := UITheme.ACCENT2 if profit >= 0 else UITheme.DANGER
	v.add_child(UITheme.make_label("💰 Caja: %s  →  %s" % [Fmt.money(d["money_start"]), Fmt.money(d["money_end"])], 15))
	v.add_child(UITheme.make_label("📈 Beneficio neto: %s%s" % ["+" if profit >= 0 else "", Fmt.money(profit)], 17, pcol))
	v.add_child(UITheme.hsep())
	v.add_child(UITheme.make_label("📦 Producción: %d unidades   ·   🛒 Ventas: %s" % [int(d["produced"]), Fmt.money(d["sales_income"])], 13))
	v.add_child(UITheme.make_label("📋 Contratos: %d completados · %d fallidos" % [int(d["contracts_done"]), int(d["contracts_failed"])], 13))
	v.add_child(UITheme.hsep())
	v.add_child(UITheme.make_label("💸 GASTOS DE LA SEMANA", 12, UITheme.ACCENT))
	var exp: Dictionary = d["expense"]
	var labels := {"purchases": "Materiales", "energy": "Energía", "maintenance": "Mantenimiento",
		"salaries": "Salarios", "construction": "Construcción/Expansión", "contract_penalty": "Penalizaciones", "misc": "Otros"}
	var any_exp := false
	for cat in exp.keys():
		if float(exp[cat]) > 0.0:
			any_exp = true
			v.add_child(UITheme.make_label("   %s: -%s" % [labels.get(cat, cat), Fmt.money(exp[cat])], 12))
	if not any_exp:
		v.add_child(UITheme.make_label("   (sin gastos)", 12, UITheme.MUTED))
	v.add_child(UITheme.hsep())
	v.add_child(UITheme.make_label("👥 Personal: %d / %d   ·   💰 Salarios: %s/sem" % [int(d["staff"]), int(d["staff_max"]), Fmt.money(d["salaries"])], 13))
	if String(d.get("top_product", "")) != "":
		v.add_child(UITheme.make_label("🏭 Producto estrella: %s" % d["top_product"], 12, UITheme.ACCENT2))
	if String(d.get("best_employee", "")) != "":
		v.add_child(UITheme.make_label("👷 Mejor empleado: %s" % d["best_employee"], 12))
	if int(d.get("problems", 0)) > 0:
		v.add_child(UITheme.make_label("⚠ Problemas de la semana: %d (averías/contratos fallidos)" % int(d["problems"]), 12, UITheme.WARN))
	var rd: int = int(d["reputation_delta"])
	if rd != 0:
		v.add_child(UITheme.make_label("⭐ Reputación: %s%d" % ["+" if rd > 0 else "", rd], 13, UITheme.ACCENT2 if rd > 0 else UITheme.WARN))
	if String(d["achievement"]) != "":
		v.add_child(UITheme.hsep())
		v.add_child(UITheme.make_label("🏆 Mayor logro: %s" % d["achievement"], 13, UITheme.ACCENT2))
	v.add_child(UITheme.hsep())
	v.add_child(UITheme.make_label("🎯 Próxima meta: %s" % d["next_goal"], 13, UITheme.ACCENT))
	var close := UITheme.make_primary_button("Planificar la próxima semana")
	close.pressed.connect(func():
		TimeManager.set_time_scale(_week_prev_scale if _week_prev_scale > 0.0 else 1.0)
		_free_node(panel))
	v.add_child(close)
	root.add_child(panel)

# --- Elección de rama industrial (spec §8, §9) ------------------------------
func _show_branch_choice() -> void:
	var panel := UITheme.make_panel(UITheme.BG)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -220
	panel.offset_bottom = 220
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.make_title("ELEGÍ TU CAMINO INDUSTRIAL"))
	v.add_child(UITheme.make_label("Tu rama define máquinas, recetas y contratos. Da +25% a tus máquinas.\nPodés especializarte sin bloquear del todo las demás industrias.", 12, UITheme.MUTED))
	v.add_child(UITheme.hsep())
	var spec := GameManager.specialization
	for id in spec.BRANCHES.keys():
		var b: Dictionary = spec.BRANCHES[id]
		var btn := UITheme.make_button("%s  %s" % [b["icon"], b["name"]])
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 16)
		btn.tooltip_text = String(b["tagline"])
		btn.pressed.connect(func():
			spec.choose(String(id))
			_free_node(panel))
		v.add_child(btn)
		v.add_child(UITheme.make_label(String(b["tagline"]), 11, UITheme.MUTED))
	v.add_child(UITheme.hsep())
	var later := UITheme.make_button("Elegir más tarde (en 🔬 Tecnología)")
	later.pressed.connect(_free_node.bind(panel))
	v.add_child(later)
	root.add_child(panel)
