extends Node
## RuleManager — motor de reglas SI→ENTONCES (spec §16).
##
## Sistema básico y ampliable. Cada regla evalúa una condición y, si se cumple,
## ejecuta una acción (con enfriamiento para no dispararse en bucle). Ejemplos:
##   SI stock de hierro < 500 → comprar hierro
##   SI almacén > 90% → detener producción
##   SI máquina averiada → enviar mecánico (reparar)
##   SI energía en sobrecarga → apagar líneas de baja prioridad

enum Cond { STOCK_BELOW, STOCK_ABOVE, STORAGE_FILL_ABOVE, ANY_MACHINE_BROKEN, POWER_OVERLOAD }
enum Act { BUY, SELL, REPAIR_ALL, PAY_DEBT, DISABLE_LOW_PRIORITY, ENABLE_ALL }

const COND_NAMES := {
	Cond.STOCK_BELOW: "Stock por debajo de",
	Cond.STOCK_ABOVE: "Stock por encima de",
	Cond.STORAGE_FILL_ABOVE: "Almacén lleno por encima de %",
	Cond.ANY_MACHINE_BROKEN: "Hay máquina averiada",
	Cond.POWER_OVERLOAD: "Sobrecarga eléctrica",
}
const ACT_NAMES := {
	Act.BUY: "Comprar",
	Act.SELL: "Vender",
	Act.REPAIR_ALL: "Reparar todo",
	Act.PAY_DEBT: "Pagar deuda",
	Act.DISABLE_LOW_PRIORITY: "Apagar baja prioridad",
	Act.ENABLE_ALL: "Reactivar todo",
}
const DEFAULT_COOLDOWN_MIN := 60.0    # minutos de juego entre disparos

var rules: Array = []
var _next_id: int = 1

func _ready() -> void:
	EventBus.minute_passed.connect(_on_minute)

func _now_minutes() -> float:
	return float(GameState.day) * 1440.0 + float(GameState.hour) * 60.0 + float(GameState.minute)

# --- Gestión de reglas ------------------------------------------------------
func add_rule(cond_type: int, cond_params: Dictionary, act_type: int, act_params: Dictionary) -> Dictionary:
	var rule := {
		"id": _next_id,
		"cond_type": cond_type,
		"cond_params": cond_params,
		"act_type": act_type,
		"act_params": act_params,
		"enabled": true,
		"cooldown": DEFAULT_COOLDOWN_MIN,
		"_next_fire": 0.0,
	}
	_next_id += 1
	rules.append(rule)
	EventBus.rule_added.emit(rule)
	return rule

func remove_rule(id: int) -> void:
	for r in rules.duplicate():
		if r["id"] == id:
			rules.erase(r)
			EventBus.rule_removed.emit(id)
			return

func describe(rule: Dictionary) -> String:
	var c := "%s %s" % [COND_NAMES.get(rule["cond_type"], "?"), _cond_detail(rule)]
	var a := "%s %s" % [ACT_NAMES.get(rule["act_type"], "?"), _act_detail(rule)]
	return "SI %s → %s" % [c, a]

func _cond_detail(rule: Dictionary) -> String:
	var p: Dictionary = rule["cond_params"]
	match rule["cond_type"]:
		Cond.STOCK_BELOW, Cond.STOCK_ABOVE:
			return "%s (%d)" % [ItemDB.display_name(p.get("item", "")), int(p.get("amount", 0))]
		Cond.STORAGE_FILL_ABOVE:
			return "%d%%" % int(float(p.get("ratio", 0.9)) * 100.0)
		_:
			return ""

func _act_detail(rule: Dictionary) -> String:
	var p: Dictionary = rule["act_params"]
	match rule["act_type"]:
		Act.BUY, Act.SELL:
			return "%d× %s" % [int(p.get("amount", 0)), ItemDB.display_name(p.get("item", ""))]
		Act.PAY_DEBT:
			return Fmt.money(float(p.get("amount", 0)))
		_:
			return ""

# --- Evaluación -------------------------------------------------------------
func _on_minute(_d: int, _h: int, _m: int) -> void:
	var now := _now_minutes()
	for rule in rules:
		if not rule["enabled"]:
			continue
		if now < float(rule["_next_fire"]):
			continue
		if _check(rule):
			_execute(rule)
			rule["_next_fire"] = now + float(rule["cooldown"])
			EventBus.rule_triggered.emit(rule)

func _check(rule: Dictionary) -> bool:
	var p: Dictionary = rule["cond_params"]
	match rule["cond_type"]:
		Cond.STOCK_BELOW:
			return GameManager.storage.count(String(p.get("item", ""))) < int(p.get("amount", 0))
		Cond.STOCK_ABOVE:
			return GameManager.storage.count(String(p.get("item", ""))) > int(p.get("amount", 0))
		Cond.STORAGE_FILL_ABOVE:
			return GameManager.storage.fill_ratio() >= float(p.get("ratio", 0.9))
		Cond.ANY_MACHINE_BROKEN:
			for m in GameManager.machines.machines:
				if m.state == Machine.State.BROKEN:
					return true
			return false
		Cond.POWER_OVERLOAD:
			return GameManager.power.overload
	return false

func _execute(rule: Dictionary) -> void:
	var p: Dictionary = rule["act_params"]
	match rule["act_type"]:
		Act.BUY:
			GameManager.market.buy(String(p.get("item", "")), int(p.get("amount", 0)), String(p.get("supplier", "")))
		Act.SELL:
			GameManager.market.sell(String(p.get("item", "")), int(p.get("amount", 0)))
		Act.REPAIR_ALL:
			for m in GameManager.machines.machines:
				if m.condition < 60.0:
					GameManager.maintenance.repair(m)
		Act.PAY_DEBT:
			GameManager.economy.pay_debt(float(p.get("amount", 0)))
		Act.DISABLE_LOW_PRIORITY:
			GameManager.priority.disable_priority(0)
		Act.ENABLE_ALL:
			for m in GameManager.machines.machines:
				m.set_enabled(true)
	EventBus.notify.emit("Regla ejecutada: %s" % describe(rule), "info")

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var arr: Array = []
	for r in rules:
		var c: Dictionary = r.duplicate()
		c.erase("_next_fire")
		arr.append(c)
	return { "rules": arr, "next_id": _next_id }

func from_dict(data: Dictionary) -> void:
	rules.clear()
	_next_id = int(data.get("next_id", 1))
	for rd in data.get("rules", []):
		var r: Dictionary = rd.duplicate(true)
		r["_next_fire"] = 0.0
		rules.append(r)
