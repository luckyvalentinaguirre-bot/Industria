extends PanelContainer
## AutomationUI — panel de reglas y automatización (spec §16, §19 Automatización).
##
## Permite crear reglas SI→ENTONCES: presets rápidos frecuentes y un constructor
## simple (condición de stock → acción de comprar/vender). Lista y elimina reglas.

const RM := preload("res://scripts/automation/rule_manager.gd")
const ITEMS := ["iron_ore", "copper_ore", "scrap", "oil", "chemicals",
	"iron_ingot", "metal_plate", "industrial_part", "metal_piece",
	"industrial_comp", "simple_motor", "fuel"]

var _list: VBoxContainer
var _cond_item: OptionButton
var _cond_amount: SpinBox
var _cond_dir: OptionButton
var _act_kind: OptionButton
var _act_item: OptionButton
var _act_amount: SpinBox

func _ready() -> void:
	custom_minimum_size = Vector2(360, 0)
	add_theme_stylebox_override("panel", UITheme.panel_style())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 520)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_build(box)
	EventBus.rule_added.connect(func(_r): _refresh_list())
	EventBus.rule_removed.connect(func(_id): _refresh_list())
	visible = false

func _build(box: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_child(UITheme.make_title("Automatización"))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	var x := UITheme.make_button("✕"); x.custom_minimum_size = Vector2(30, 30)
	x.pressed.connect(func(): visible = false)
	header.add_child(x)
	box.add_child(header)

	box.add_child(UITheme.make_label("Reglas rápidas:", 13, UITheme.ACCENT))
	_preset(box, "Comprar hierro si stock < 200", func():
		GameManager.rules.add_rule(RM.Cond.STOCK_BELOW, {"item": "iron_ore", "amount": 200}, RM.Act.BUY, {"item": "iron_ore", "amount": 100}))
	_preset(box, "Comprar combustible si stock < 50", func():
		GameManager.rules.add_rule(RM.Cond.STOCK_BELOW, {"item": "fuel", "amount": 50}, RM.Act.BUY, {"item": "oil", "amount": 30}))
	_preset(box, "Reparar todo si hay avería", func():
		GameManager.rules.add_rule(RM.Cond.ANY_MACHINE_BROKEN, {}, RM.Act.REPAIR_ALL, {}))
	_preset(box, "Apagar baja prioridad en sobrecarga", func():
		GameManager.rules.add_rule(RM.Cond.POWER_OVERLOAD, {}, RM.Act.DISABLE_LOW_PRIORITY, {}))

	# Constructor simple: stock → comprar/vender
	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Regla personalizada:", 13, UITheme.ACCENT))
	var c1 := HBoxContainer.new()
	c1.add_child(UITheme.make_label("SI stock de", 12))
	_cond_item = _item_option()
	c1.add_child(_cond_item)
	box.add_child(c1)
	var c2 := HBoxContainer.new()
	_cond_dir = OptionButton.new()
	_cond_dir.add_item("está por debajo de", 0)
	_cond_dir.add_item("está por encima de", 1)
	c2.add_child(_cond_dir)
	_cond_amount = SpinBox.new()
	_cond_amount.min_value = 0; _cond_amount.max_value = 100000; _cond_amount.value = 200
	c2.add_child(_cond_amount)
	box.add_child(c2)
	var c3 := HBoxContainer.new()
	c3.add_child(UITheme.make_label("ENTONCES", 12, UITheme.ACCENT2))
	_act_kind = OptionButton.new()
	_act_kind.add_item("Comprar", 0)
	_act_kind.add_item("Vender", 1)
	c3.add_child(_act_kind)
	box.add_child(c3)
	var c4 := HBoxContainer.new()
	_act_item = _item_option()
	c4.add_child(_act_item)
	_act_amount = SpinBox.new()
	_act_amount.min_value = 1; _act_amount.max_value = 100000; _act_amount.value = 100
	c4.add_child(_act_amount)
	box.add_child(c4)
	var add_btn := UITheme.make_button("+ Añadir regla")
	add_btn.pressed.connect(_on_add_custom)
	box.add_child(add_btn)

	box.add_child(UITheme.hsep())
	box.add_child(UITheme.make_label("Reglas activas:", 13, UITheme.ACCENT))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	_refresh_list()

func _preset(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := UITheme.make_button(text)
	b.pressed.connect(cb)
	box.add_child(b)

func _item_option() -> OptionButton:
	var o := OptionButton.new()
	for i in ITEMS.size():
		o.add_item(ItemDB.display_name(ITEMS[i]), i)
	return o

func _on_add_custom() -> void:
	var cond := RM.Cond.STOCK_BELOW if _cond_dir.selected == 0 else RM.Cond.STOCK_ABOVE
	var act := RM.Act.BUY if _act_kind.selected == 0 else RM.Act.SELL
	GameManager.rules.add_rule(
		cond, {"item": ITEMS[_cond_item.selected], "amount": int(_cond_amount.value)},
		act, {"item": ITEMS[_act_item.selected], "amount": int(_act_amount.value)})

func _refresh_list() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	for rule in GameManager.rules.rules:
		var row := HBoxContainer.new()
		var lbl := UITheme.make_label(GameManager.rules.describe(rule), 11)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(280, 0)
		row.add_child(lbl)
		var del := UITheme.make_button("✕")
		del.custom_minimum_size = Vector2(28, 26)
		var rid: int = rule["id"]
		del.pressed.connect(func(): GameManager.rules.remove_rule(rid))
		row.add_child(del)
		_list.add_child(row)
