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
	_build_toasts()
	_connect_signals()
	_refresh_hud()
	if not GameManager.save.has_save():
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

func _on_tutorial_finished() -> void:
	if _tutorial_banner:
		_tutorial_banner.visible = false

# --- Barra superior ---------------------------------------------------------
func _build_topbar() -> void:
	var bar := UITheme.make_panel(UITheme.BG)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	_money_lbl = _stat(h, UITheme.ACCENT2, 110)
	h.add_child(_vsep())
	_value_lbl = _stat(h, UITheme.TEXT, 130)
	h.add_child(_vsep())
	_debt_lbl = _stat(h, UITheme.WARN, 120)
	h.add_child(_vsep())
	_rep_lbl = _stat(h, UITheme.ACCENT, 70)
	h.add_child(_vsep())
	_level_lbl = _stat(h, UITheme.ACCENT2, 180)
	h.add_child(_vsep())
	_clock_lbl = _stat(h, UITheme.TEXT, 140)
	h.add_child(_vsep())
	_power_lbl = _stat(h, UITheme.ACCENT, 120)

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
	var l := UITheme.make_label("", 16, color)
	l.custom_minimum_size = Vector2(min_w, 0)
	h.add_child(l)
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

# --- Barra inferior: sólo el botón de Menú ----------------------------------
func _build_bottom_bar() -> void:
	var bar := UITheme.make_panel(UITheme.BG)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 8
	bar.offset_bottom = -8
	root.add_child(bar)
	var menu_btn := UITheme.make_button("☰  MENÚ")
	menu_btn.custom_minimum_size = Vector2(168, 48)
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.add_theme_color_override("font_color", UITheme.ACCENT)
	menu_btn.pressed.connect(_toggle_menu)
	bar.add_child(menu_btn)
	_build_menu_panel()
	# El catálogo de construcción se cierra al salir del modo construcción.
	EventBus.build_mode_changed.connect(func(active, _k):
		if not active and build_panel:
			build_panel.visible = false)

func _build_menu_panel() -> void:
	menu_panel = UITheme.make_panel(UITheme.BG)
	menu_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	menu_panel.offset_left = 8
	menu_panel.offset_bottom = -54
	menu_panel.custom_minimum_size = Vector2(240, 0)
	menu_panel.visible = false
	root.add_child(menu_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	menu_panel.add_child(v)
	v.add_child(UITheme.make_title("Menú"))
	_menu_item(v, "🏗  Construcción", _on_construction)
	_menu_item(v, "🏭  Producción", _on_storage)      # inventario/materiales de producción
	_menu_item(v, "🚚  Logística", _on_automation)     # reglas/prioridades de flujo
	_menu_item(v, "⚡  Energía", _on_energy)
	_menu_item(v, "💰  Economía", _on_finance)
	_menu_item(v, "📋  Contratos", _on_contracts)
	_menu_item(v, "🔬  Investigación", _on_upgrades)
	_menu_item(v, "👷  Personal", _on_workers)
	_menu_item(v, "📊  Estadísticas", _on_objectives)
	_menu_item(v, "⚙  Configuración", _on_config)

func _menu_item(v: VBoxContainer, text: String, cb: Callable) -> void:
	var b := UITheme.make_button(text)
	b.custom_minimum_size = Vector2(0, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		menu_panel.visible = false
		cb.call())
	v.add_child(b)

func _toggle_menu() -> void:
	if menu_panel:
		menu_panel.visible = not menu_panel.visible

func _on_construction() -> void:
	if build_panel:
		build_panel.visible = not build_panel.visible

func _on_energy() -> void:
	EventBus.notify.emit("Energía: usá el HUD (⚡) y coloca Generador/Subestación desde Construcción.", "info")

func _on_config() -> void:
	EventBus.notify.emit("Configuración: 💾 Guardar / 📂 Cargar disponibles.", "info")
	GameManager.save.save_game()

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
	EventBus.objectives_updated.connect(_refresh_objectives)
	EventBus.game_won.connect(_on_game_won)
	EventBus.minute_passed.connect(func(_a, _b, _c): _refresh_storage())
	EventBus.tutorial_step_changed.connect(_on_tutorial_step)
	EventBus.tutorial_finished.connect(_on_tutorial_finished)
	EventBus.company_level_changed.connect(func(_l, _n): _refresh_hud())

func _refresh_hud() -> void:
	if _money_lbl == null:
		return
	_money_lbl.text = "💰 " + Fmt.money(GameState.money)
	_value_lbl.text = "🏭 " + Fmt.money(_factory_value())
	_debt_lbl.text = "🏦 " + Fmt.money(GameState.debt)
	_rep_lbl.text = "⭐ %d" % GameState.reputation
	_level_lbl.text = "🏢 N%d · %s" % [GameState.company_level, GameManager.progression.level_name()]
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
	# Destello de la caja al cambiar (feedback discreto).
	if _money_lbl:
		_money_lbl.modulate = Color(1.4, 1.4, 1.0)
		var tw := create_tween()
		tw.tween_property(_money_lbl, "modulate", Color(1, 1, 1), 0.4)

func _on_build_mode(active: bool, kind: String) -> void:
	_mode_lbl.text = ("🔨 Construyendo: " + kind + "  (Esc para salir, R rota)") if active else ""

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
	v.add_child(UITheme.make_label("%s · %s" % [tag, c.client], 13, tcol))
	var info := "%d× %s · Paga %s · Plazo %d días · Penal. %s" % [c.amount, ItemDB.display_name(c.product), Fmt.money(c.payment), c.deadline_days, Fmt.money(c.penalty)]
	v.add_child(UITheme.make_label(info, 12))
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
	if workers_panel == null:
		return
	var box := _find_box(workers_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Personal"))
	box.add_child(UITheme.make_label("Contratar:", 13, UITheme.ACCENT))
	for type_id in GameManager.workers.types.keys():
		var def: Dictionary = GameManager.workers.types[type_id]
		var b := UITheme.make_button("%s — %s/día" % [String(def.get("name", type_id)), Fmt.money(def.get("salary", 0))])
		b.pressed.connect(GameManager.workers.hire.bind(String(type_id), true))
		box.add_child(b)
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Plantilla (%d) — Salarios: %s/día" % [GameManager.workers.workers.size(), Fmt.money(GameManager.workers.daily_salary_total())], 12, UITheme.ACCENT2))
	for w in GameManager.workers.workers:
		var row := HBoxContainer.new()
		row.add_child(UITheme.make_label("%s (exp %d)" % [w.worker_name, int(w.experience)], 12))
		var fire := UITheme.make_button("Despedir")
		fire.pressed.connect(GameManager.workers.fire.bind(w))
		row.add_child(fire)
		box.add_child(row)

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
	if objectives_panel == null:
		return
	var box := _find_box(objectives_panel)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	box.add_child(UITheme.make_title("Objetivos"))
	box.add_child(UITheme.make_label("Nivel de empresa: %s (N%d)" % [GameManager.progression.level_name(), GameState.company_level], 12, UITheme.ACCENT2))
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

func _objective_row(o: Dictionary) -> Label:
	var mark := "✅" if o["done"] else "⬜"
	var color := UITheme.ACCENT2 if o["done"] else UITheme.TEXT
	var reward := int(o.get("reward", 0))
	var suffix := "  (+%s)" % Fmt.money(reward) if reward > 0 else ""
	var l := UITheme.make_label("%s  %s%s" % [mark, o["title"], suffix], 12, color)
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
	box.add_child(UITheme.make_title("Mejoras"))
	box.add_child(UITheme.make_label("Invierte para optimizar toda la fábrica.", 12))
	box.add_child(UITheme.hsep())
	var um: Node = GameManager.upgrades
	for id in um.defs.keys():
		var d: Dictionary = um.defs[id]
		var v := VBoxContainer.new()
		var owned: bool = um.is_owned(id)
		var avail: bool = um.is_available(id)
		var title_color := UITheme.ACCENT2 if owned else (UITheme.TEXT if avail else Color(0.5, 0.5, 0.55))
		v.add_child(UITheme.make_label(String(d.get("name", id)), 14, title_color))
		var desc := UITheme.make_label(String(d.get("description", "")), 11)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(300, 0)
		v.add_child(desc)
		if owned:
			v.add_child(UITheme.make_label("✅ Adquirida", 12, UITheme.ACCENT2))
		elif avail:
			var b := UITheme.make_button("Comprar (%s)" % Fmt.money(um.cost(id)))
			b.disabled = not GameManager.economy.can_afford(um.cost(id))
			b.pressed.connect(_on_buy_upgrade.bind(String(id)))
			v.add_child(b)
		else:
			var req := String(d.get("requires", ""))
			var req_name := String(um.defs.get(req, {}).get("name", req))
			v.add_child(UITheme.make_label("🔒 Requiere: %s" % req_name, 11, UITheme.WARN))
		v.add_child(UITheme.hsep())
		box.add_child(v)

func _on_buy_upgrade(id: String) -> void:
	GameManager.upgrades.buy(id)
	_refresh_upgrades()

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
		for id in items.keys():
			var row := HBoxContainer.new()
			var n := UITheme.make_label(ItemDB.display_name(id), 12)
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
	v.add_child(UITheme.make_label("¡INDUSTRIA SALVADA!", 28, UITheme.ACCENT2))
	v.add_child(UITheme.make_label("Saldaste la deuda y la empresa es rentable.", 15))
	v.add_child(UITheme.make_label("Puedes seguir jugando y expandiendo la fábrica.", 13, UITheme.TEXT))
	var close := UITheme.make_button("Continuar")
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
	v.add_child(UITheme.make_title("Bienvenido a Industria"))
	var text := "Heredas una fábrica endeudada y deteriorada. Tu meta: ponerla a producir, cumplir contratos y saldar la deuda.\n\n" \
		+ "Primeros pasos:\n" \
		+ "1. Selecciona la fundición averiada y repárala.\n" \
		+ "2. Compra mineral de hierro en Finanzas → Comprar.\n" \
		+ "3. Conecta el almacén a la fundición con una Cinta.\n" \
		+ "4. Deja que produzca lingotes y véndelos o cumple un contrato.\n\n" \
		+ "Cámara: WASD/bordes mover · Q/E rotar · rueda zoom · G cuadrícula.\n" \
		+ "Construcción: menú izquierdo · R rota · Esc cancela.\n" \
		+ "Velocidad: ⏸ ▶ ▶▶ ▶▶▶ arriba a la derecha."
	var lbl := UITheme.make_label(text, 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(560, 0)
	v.add_child(lbl)
	var close := UITheme.make_button("¡Empezar!")
	close.pressed.connect(panel.queue_free)
	v.add_child(close)
	root.add_child(panel)
