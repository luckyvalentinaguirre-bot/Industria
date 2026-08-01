extends PanelContainer
## FinanceUI — panel de finanzas y mercado (spec §13, §14, §19 Finanzas).
##
## Muestra ingresos/gastos/ganancias/deuda, permite pagar deuda y operar el
## mercado (comprar materias primas a proveedores y vender productos).

const RAW_ITEMS := ["scrap", "iron_ore", "copper_ore", "wood_log", "clay", "nutrients", "oil", "chemicals", "coal", "sand", "stone"]
const SELL_ITEMS := ["hand_tool", "plank", "pallet", "brick", "block", "regulated_goods",
	"fuel", "metal_plate", "copper_part", "industrial_part", "metal_piece",
	"industrial_comp", "simple_motor", "iron_ingot", "copper_ingot", "recycled_metal",
	"steel", "glass", "plastic", "copper_wire", "electronic_component", "machine_part"]

var _summary_lbl: Label
var _debt_spin: SpinBox
var _accum: float = 0.0
var _price_lbls: Dictionary = {}   # item_id -> Label (precio + tendencia)

func _ready() -> void:
	custom_minimum_size = Vector2(340, 0)
	add_theme_stylebox_override("panel", UITheme.panel_style())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 520)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_build(box)
	EventBus.money_changed.connect(func(_m): _refresh())
	EventBus.debt_changed.connect(func(_d): _refresh())
	visible = false

func _build(box: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_child(UITheme.make_title("Finanzas"))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	var x := UITheme.make_button("✕"); x.custom_minimum_size = Vector2(30, 30)
	x.pressed.connect(func(): visible = false)
	header.add_child(x)
	box.add_child(header)

	_summary_lbl = UITheme.make_label("", 13)
	box.add_child(_summary_lbl)

	# Pagar deuda
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Pagar deuda:", 13, UITheme.ACCENT))
	var debt_row := HBoxContainer.new()
	_debt_spin = SpinBox.new()
	_debt_spin.min_value = 0
	_debt_spin.max_value = 1000000
	_debt_spin.step = 500
	_debt_spin.value = 2000
	_debt_spin.custom_minimum_size = Vector2(120, 0)
	debt_row.add_child(_debt_spin)
	var pay_btn := UITheme.make_button("Pagar")
	pay_btn.pressed.connect(func(): GameManager.economy.pay_debt(_debt_spin.value))
	debt_row.add_child(pay_btn)
	box.add_child(debt_row)

	# Mercado — comprar materias primas (precios dinámicos)
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("📈 MERCADO · Comprar materias primas", 13, UITheme.ACCENT))
	for item_id in RAW_ITEMS:
		box.add_child(_buy_row(item_id))

	# Vender productos
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("📈 MERCADO · Vender productos", 13, UITheme.ACCENT))
	for item_id in SELL_ITEMS:
		box.add_child(_sell_row(item_id))

	_refresh()

func _buy_row(item_id: String) -> VBoxContainer:
	return _market_row(item_id, true)

func _sell_row(item_id: String) -> VBoxContainer:
	return _market_row(item_id, false)

func _market_row(item_id: String, is_buy: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	# Fila 1: nombre + precio con tendencia.
	var top := HBoxContainer.new()
	var name_lbl := UITheme.make_label(ItemDB.display_name(item_id), 12)
	name_lbl.custom_minimum_size = Vector2(130, 0)
	top.add_child(name_lbl)
	var price_lbl := UITheme.make_label("", 12)
	price_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(price_lbl)
	_price_lbls[item_id] = price_lbl
	col.add_child(top)
	# Fila 2: cantidad + acción.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	var qty := SpinBox.new()
	qty.min_value = 1; qty.max_value = 10000; qty.value = 20 if is_buy else 10
	qty.custom_minimum_size = Vector2(90, 0)
	bottom.add_child(qty)
	var btn := UITheme.make_button("Comprar" if is_buy else "Vender")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_buy:
		btn.pressed.connect(func(): GameManager.market.buy(item_id, int(qty.value)))
	else:
		btn.pressed.connect(func(): GameManager.market.sell(item_id, int(qty.value)))
	bottom.add_child(btn)
	col.add_child(bottom)
	col.add_child(UITheme.hsep())
	return col

func _refresh() -> void:
	if _summary_lbl == null:
		return
	var f: Dictionary = GameManager.finance.get_summary()
	var s := "💰 Caja: %s\n" % Fmt.money(GameState.money)
	s += "🏦 Deuda: %s\n" % Fmt.money(GameState.debt)
	s += "⭐ Reputación: %d\n\n" % GameState.reputation
	s += "Hoy — Ingresos: %s   Gastos: %s\n" % [Fmt.money(f["today_income"].values().reduce(func(a,b): return a+b, 0.0)), Fmt.money(f["today_expense"].values().reduce(func(a,b): return a+b, 0.0))]
	s += "Ganancia de hoy: %s\n\n" % Fmt.money(f["today_profit"])
	s += "Gastos por categoría (hoy):\n"
	for cat in f["today_expense"].keys():
		var v: float = f["today_expense"][cat]
		if v > 0.0:
			s += "  · %s: %s\n" % [cat, Fmt.money(v)]
	_summary_lbl.text = s
	_refresh_prices()

func _refresh_prices() -> void:
	for item_id in _price_lbls.keys():
		var lbl: Label = _price_lbls[item_id]
		if not is_instance_valid(lbl):
			continue
		var price: float = GameManager.market.current_price(item_id)
		var trend: float = GameManager.market.trend_pct(item_id)
		var arrow := "→"
		var col := UITheme.TEXT
		if trend > 0.4:
			arrow = "↑"; col = UITheme.ACCENT2
		elif trend < -0.4:
			arrow = "↓"; col = UITheme.DANGER
		lbl.text = "%s  %s %+.0f%%" % [Fmt.money(price), arrow, trend]
		lbl.add_theme_color_override("font_color", col)

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		_refresh()
