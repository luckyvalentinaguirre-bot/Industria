extends Node
## MarketManager — compra de materias primas a proveedores (spec §14).
##
## Distintos proveedores difieren en precio, calidad y tiempo de entrega. La
## compra descuenta dinero de inmediato y programa la entrega para dentro de
## `delivery_days`; al llegar, los ítems ingresan al stock general de la empresa.

var suppliers: Dictionary = {}
var _pending: Array = []   # [{item_id, qty, arrive_day, supplier}]

func _ready() -> void:
	var cfg := _load_prices()
	suppliers = cfg.get("suppliers", {})
	EventBus.day_passed.connect(_on_day_passed)

func _load_prices() -> Dictionary:
	var path := "res://data/economy/prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

## Proveedores que venden un ítem dado.
func suppliers_for(item_id: String) -> Array:
	var out: Array = []
	for sid in suppliers.keys():
		var s: Dictionary = suppliers[sid]
		if (s.get("sells", []) as Array).has(item_id):
			out.append(sid)
	return out

func unit_price(item_id: String, supplier_id: String) -> float:
	var mult := 1.0
	if suppliers.has(supplier_id):
		mult = float(suppliers[supplier_id].get("price_mult", 1.0))
	return ItemDB.base_price(item_id) * mult

func order_cost(item_id: String, qty: int, supplier_id: String) -> float:
	return unit_price(item_id, supplier_id) * qty

## Realiza un pedido. Devuelve true si se pagó y programó.
func buy(item_id: String, qty: int, supplier_id: String = "") -> bool:
	if qty <= 0:
		return false
	if supplier_id == "" or not suppliers.has(supplier_id):
		var opts := suppliers_for(item_id)
		if opts.is_empty():
			EventBus.notify.emit("Ningún proveedor vende %s" % ItemDB.display_name(item_id), "error")
			return false
		supplier_id = _cheapest(opts, item_id)
	var cost := order_cost(item_id, qty, supplier_id)
	if not GameManager.economy.spend(cost, "purchases"):
		return false
	var days := int(suppliers[supplier_id].get("delivery_days", 1))
	var arrive := GameState.day + days
	_pending.append({ "item_id": item_id, "qty": qty, "arrive_day": arrive, "supplier": supplier_id })
	EventBus.purchase_ordered.emit(item_id, qty, cost, arrive)
	EventBus.notify.emit("Pedido: %d× %s (llega día %d)" % [qty, ItemDB.display_name(item_id), arrive], "info")
	return true

func _cheapest(opts: Array, item_id: String) -> String:
	var best := String(opts[0])
	var best_price := unit_price(item_id, best)
	for sid in opts:
		var p := unit_price(item_id, sid)
		if p < best_price:
			best_price = p
			best = sid
	return best

## Vende `qty` unidades de un producto desde el stock al mercado abierto.
## Devuelve el ingreso obtenido.
func sell(item_id: String, qty: int) -> float:
	if qty <= 0:
		return 0.0
	var sold: int = GameManager.storage.withdraw(item_id, qty)
	if sold <= 0:
		EventBus.notify.emit("No hay %s en stock para vender" % ItemDB.display_name(item_id), "warning")
		return 0.0
	var cfg := _load_prices()
	var margin := float(cfg.get("sell_margin", 1.0))
	if GameManager.upgrades:
		margin *= GameManager.upgrades.sell_mult()
	var revenue: float = ItemDB.base_price(item_id) * margin * sold
	GameManager.economy.earn(revenue, "sales")
	EventBus.notify.emit("Vendidas %d× %s por %s" % [sold, ItemDB.display_name(item_id), Fmt.money(revenue)], "success")
	return revenue

func _on_day_passed(_day: int) -> void:
	var still: Array = []
	for order in _pending:
		if GameState.day >= int(order["arrive_day"]):
			var stored: int = GameManager.storage.deposit(order["item_id"], int(order["qty"]))
			EventBus.delivery_arrived.emit(order["item_id"], stored)
			EventBus.notify.emit("Entrega recibida: %d× %s" % [stored, ItemDB.display_name(order["item_id"])], "success")
		else:
			still.append(order)
	_pending = still

func get_pending() -> Array:
	return _pending

# --- Serialización ----------------------------------------------------------

func to_dict() -> Dictionary:
	return { "pending": _pending.duplicate(true) }

func from_dict(data: Dictionary) -> void:
	_pending = (data.get("pending", []) as Array).duplicate(true)
