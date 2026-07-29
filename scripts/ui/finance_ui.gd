extends PanelContainer
## FinanceUI — panel de finanzas y mercado (spec §13, §14, §19 Finanzas).
##
## Muestra ingresos/gastos/ganancias/deuda, permite pagar deuda y operar el
## mercado (comprar materias primas a proveedores y vender productos).

const RAW_ITEMS := ["iron_ore", "copper_ore", "scrap", "oil", "chemicals"]
const SELL_ITEMS := ["metal_plate", "copper_part", "industrial_part",
	"metal_piece", "industrial_comp", "simple_motor", "iron_ingot", "copper_ingot"]

var _summary_lbl: Label
var _debt_spin: SpinBox
var _accum: float = 0.0

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

	# Comprar materias primas
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Comprar materias primas:", 13, UITheme.ACCENT))
	for item_id in RAW_ITEMS:
		box.add_child(_buy_row(item_id))

	# Vender productos
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Vender productos:", 13, UITheme.ACCENT))
	for item_id in SELL_ITEMS:
		box.add_child(_sell_row(item_id))

	_refresh()

func _buy_row(item_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_lbl := UITheme.make_label(ItemDB.display_name(item_id), 12)
	name_lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_lbl)
	var qty := SpinBox.new()
	qty.min_value = 1; qty.max_value = 1000; qty.value = 20
	qty.custom_minimum_size = Vector2(70, 0)
	row.add_child(qty)
	var btn := UITheme.make_button("Comprar")
	btn.pressed.connect(func(): GameManager.market.buy(item_id, int(qty.value)))
	row.add_child(btn)
	return row

func _sell_row(item_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_lbl := UITheme.make_label(ItemDB.display_name(item_id), 12)
	name_lbl.custom_minimum_size = Vector2(120, 0)
	name_lbl.set_meta("item", item_id)
	name_lbl.name = "sell_" + item_id
	row.add_child(name_lbl)
	var qty := SpinBox.new()
	qty.min_value = 1; qty.max_value = 10000; qty.value = 10
	qty.custom_minimum_size = Vector2(70, 0)
	row.add_child(qty)
	var btn := UITheme.make_button("Vender")
	btn.pressed.connect(func(): GameManager.market.sell(item_id, int(qty.value)))
	row.add_child(btn)
	return row

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

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		_refresh()
