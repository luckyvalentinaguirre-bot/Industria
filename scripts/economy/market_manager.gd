extends Node
## MarketManager — compra de materias primas a proveedores (spec §14).
##
## Distintos proveedores difieren en precio, calidad y tiempo de entrega. La
## compra descuenta dinero de inmediato y programa la entrega para dentro de
## `delivery_days`; al llegar, los ítems ingresan al stock general de la empresa.

const PRICE_MIN_FACTOR := 0.55
const PRICE_MAX_FACTOR := 1.9

var suppliers: Dictionary = {}
var _pending: Array = []   # [{item_id, qty, arrive_day, supplier}]

# Precios dinámicos: id -> precio actual; se mueven cada día (spec §4 mercado).
var prices: Dictionary = {}
var prev_prices: Dictionary = {}
var demand_bias: Dictionary = {}   # sesgo temporal por eventos (id -> factor)

func _ready() -> void:
	var cfg := _load_prices()
	suppliers = cfg.get("suppliers", {})
	_init_prices()
	EventBus.day_passed.connect(_on_day_passed)

func _init_prices() -> void:
	for id in ItemDB.all_ids():
		var base := ItemDB.base_price(id)
		prices[id] = base
		prev_prices[id] = base

func current_price(item_id: String) -> float:
	return float(prices.get(item_id, ItemDB.base_price(item_id)))

## Variación % respecto al día anterior (para las flechas de tendencia).
func trend_pct(item_id: String) -> float:
	var prev := float(prev_prices.get(item_id, current_price(item_id)))
	if prev <= 0.0:
		return 0.0
	return (current_price(item_id) - prev) / prev * 100.0

## Aplica un sesgo temporal de demanda (lo usan los eventos).
func apply_demand(item_id: String, factor: float, days: int) -> void:
	demand_bias[item_id] = { "factor": factor, "until": GameState.day + days }

func _fluctuate_prices() -> void:
	for id in prices.keys():
		var base := ItemDB.base_price(id)
		if base <= 0.0:
			continue
		prev_prices[id] = prices[id]
		var p := float(prices[id])
		# Paseo aleatorio con reversión a la media (precio base).
		p *= 1.0 + randf_range(-0.09, 0.09)
		p = lerpf(p, base, 0.14)
		# Sesgo de demanda por eventos.
		if demand_bias.has(id):
			var b: Dictionary = demand_bias[id]
			if GameState.day <= int(b["until"]):
				p = lerpf(p, base * float(b["factor"]), 0.25)
			else:
				demand_bias.erase(id)
		prices[id] = clampf(p, base * PRICE_MIN_FACTOR, base * PRICE_MAX_FACTOR)

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
	return current_price(item_id) * mult

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
	var revenue: float = current_price(item_id) * margin * sold
	GameManager.economy.earn(revenue, "sales")
	EventBus.notify.emit("Vendidas %d× %s por %s" % [sold, ItemDB.display_name(item_id), Fmt.money(revenue)], "success")
	return revenue

func _on_day_passed(_day: int) -> void:
	_fluctuate_prices()
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
	return {
		"pending": _pending.duplicate(true),
		"prices": prices.duplicate(),
		"prev_prices": prev_prices.duplicate(),
		"demand_bias": demand_bias.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	_pending = (data.get("pending", []) as Array).duplicate(true)
	if data.has("prices"):
		prices = (data["prices"] as Dictionary).duplicate()
	if data.has("prev_prices"):
		prev_prices = (data["prev_prices"] as Dictionary).duplicate()
	if data.has("demand_bias"):
		demand_bias = (data["demand_bias"] as Dictionary).duplicate(true)
