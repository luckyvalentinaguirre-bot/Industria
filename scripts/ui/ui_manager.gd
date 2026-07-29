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
var _debt_lbl: Label
var _rep_lbl: Label
var _clock_lbl: Label
var _power_lbl: Label
var _mode_lbl: Label

# Panels
var production_ui: PanelContainer
var finance_ui: PanelContainer
var automation_ui: PanelContainer
var contracts_panel: PanelContainer
var workers_panel: PanelContainer
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
	_build_toasts()
	_connect_signals()
	_refresh_hud()

# --- Barra superior ---------------------------------------------------------
func _build_topbar() -> void:
	var bar := UITheme.make_panel(UITheme.BG)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	bar.add_child(h)

	_money_lbl = UITheme.make_label("", 16, UITheme.ACCENT2)
	_debt_lbl = UITheme.make_label("", 16, UITheme.WARN)
	_rep_lbl = UITheme.make_label("", 16)
	_clock_lbl = UITheme.make_label("", 16)
	_power_lbl = UITheme.make_label("", 16, UITheme.ACCENT)
	_mode_lbl = UITheme.make_label("", 14, UITheme.WARN)
	h.add_child(_money_lbl)
	h.add_child(_debt_lbl)
	h.add_child(_rep_lbl)
	h.add_child(_clock_lbl)
	h.add_child(_power_lbl)
	h.add_child(_mode_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	# Controles de velocidad.
	for item in [["⏸", 0.0], ["▶", 1.0], ["▶▶", 2.0], ["▶▶▶", 3.0]]:
		var b := UITheme.make_button(String(item[0]))
		b.custom_minimum_size = Vector2(44, 30)
		b.pressed.connect(TimeManager.set_time_scale.bind(float(item[1])))
		h.add_child(b)

# --- Menú de construcción (izquierda) ---------------------------------------
func _build_left_menu() -> void:
	var factory := FactoryUIScript.new()
	factory.set_anchors_preset(Control.PRESET_TOP_LEFT)
	factory.offset_left = 8
	factory.offset_top = 64
	root.add_child(factory)

# --- Paneles laterales (derecha) --------------------------------------------
func _build_right_panels() -> void:
	production_ui = ProductionUIScript.new()
	finance_ui = FinanceUIScript.new()
	automation_ui = AutomationUIScript.new()
	contracts_panel = _make_contracts_panel()
	workers_panel = _make_workers_panel()
	for p in [production_ui, finance_ui, automation_ui, contracts_panel, workers_panel]:
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

# --- Barra inferior ---------------------------------------------------------
func _build_bottom_bar() -> void:
	var bar := UITheme.make_panel(UITheme.BG)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_bottom = -8
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)

	_add_bottom_btn(h, "💰 Finanzas", _on_finance)
	_add_bottom_btn(h, "📄 Contratos", _on_contracts)
	_add_bottom_btn(h, "👷 Personal", _on_workers)
	_add_bottom_btn(h, "⚙ Automatización", _on_automation)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_add_bottom_btn(h, "💾 Guardar", func(): GameManager.save.save_game())
	_add_bottom_btn(h, "📂 Cargar", func(): GameManager.save.load_game())

func _add_bottom_btn(h: HBoxContainer, text: String, cb: Callable) -> void:
	var b := UITheme.make_button(text)
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	h.add_child(b)

func _on_finance() -> void: _toggle_right(finance_ui)
func _on_contracts() -> void: _toggle_right(contracts_panel); _refresh_contracts()
func _on_workers() -> void: _toggle_right(workers_panel); _refresh_workers()
func _on_automation() -> void: _toggle_right(automation_ui)

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
	EventBus.money_changed.connect(func(_m): _refresh_hud())
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

func _refresh_hud() -> void:
	if _money_lbl == null:
		return
	_money_lbl.text = "💰 " + Fmt.money(GameState.money)
	_debt_lbl.text = "🏦 " + Fmt.money(GameState.debt)
	_rep_lbl.text = "⭐ %d" % GameState.reputation
	_clock_lbl.text = "📅 " + TimeManager.get_clock_string()
	var ps: Dictionary = GameManager.power.get_status()
	var picon := "⚡"
	_power_lbl.text = "%s %d/%d kW" % [picon, int(ps["consumption"]), int(ps["capacity"])]
	_power_lbl.add_theme_color_override("font_color", UITheme.DANGER if ps["overload"] else UITheme.ACCENT)

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
	var info := "%s\n%d× %s · Paga %s · Plazo %d días" % [c.client, c.amount, ItemDB.display_name(c.product), Fmt.money(c.payment), c.deadline_days]
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
