extends Node
## EventManager — eventos dinámicos ligados a la fábrica (spec §1/§2).
##
## Con baja probabilidad diaria dispara un evento CONTEXTUAL (según lo que el
## jugador está haciendo): averías que exigen decidir, picos/caídas de demanda,
## escasez de materias primas, un trabajador que destaca, subsidios y contratos
## especiales. Los eventos generan DECISIONES o consecuencias reales, no popups
## vacíos. Es event-driven (sólo en day_passed), sin coste por frame (spec §13).

const DAILY_CHANCE := 0.20
const RAW_ITEMS := ["scrap", "iron_ore", "copper_ore", "wood_log", "clay", "nutrients", "oil"]

func _ready() -> void:
	EventBus.day_passed.connect(_on_day)

func _on_day(_day: int) -> void:
	if randf() > DAILY_CHANCE:
		return
	var pool: Array = _applicable_events()
	if pool.is_empty():
		return
	var ev: Callable = pool[randi() % pool.size()]
	ev.call()

func _applicable_events() -> Array:
	var out: Array = []
	if GameManager.machines and not GameManager.machines.machines.is_empty():
		out.append(_ev_breakdown)
	if _a_produced_product() != "":
		out.append(_ev_demand)
		out.append(_ev_price_crash)
	out.append(_ev_shortage)
	if GameManager.workers and not GameManager.workers.workers.is_empty():
		out.append(_ev_worker_highlight)
	out.append(_ev_subsidy)
	if GameManager.contracts:
		out.append(_ev_special_contract)
	return out

# --- Evento con DECISIÓN: avería -------------------------------------------
func _ev_breakdown() -> void:
	var ms: Array = GameManager.machines.machines
	if ms.is_empty():
		return
	# Preferir una máquina en marcha (el problema se siente más).
	var target = null
	for m in ms:
		if m.state == Machine.State.RUNNING:
			target = m
			break
	if target == null:
		target = ms[randi() % ms.size()]
	target.set_condition(minf(target.condition, 25.0))
	var cost: float = GameManager.maintenance.repair_cost(target)
	var opts: Array = [
		{ "label": "🔧 Reparar ahora (%s)" % Fmt.money(cost),
		  "action": func(): GameManager.maintenance.repair(target) },
		{ "label": "Esperar (seguirá rindiendo poco)",
		  "action": func(): pass },
	]
	EventBus.decision_requested.emit("🔧 %s con problemas" % target.display_name(),
		"Se desgastó y su rendimiento cayó. ¿Qué hacés? Un buen técnico abarata la reparación.",
		opts)

# --- Eventos de mercado (consecuencia automática, notificación) --------------
func _ev_demand() -> void:
	var p := _a_produced_product()
	if p == "" or GameManager.market == null:
		return
	GameManager.market.apply_demand(p, 1.45, 4)
	EventBus.notify.emit("📈 Sube la demanda de %s: buen momento para vender." % ItemDB.display_name(p), "success")

func _ev_price_crash() -> void:
	var p := _a_produced_product()
	if p == "" or GameManager.market == null:
		return
	GameManager.market.apply_demand(p, 0.6, 4)
	EventBus.notify.emit("📉 Cae el precio de %s: quizá convenga almacenar o cambiar de producto." % ItemDB.display_name(p), "warning")

func _ev_shortage() -> void:
	if GameManager.market == null:
		return
	var raw: String = RAW_ITEMS[randi() % RAW_ITEMS.size()]
	GameManager.market.apply_demand(raw, 1.6, 4)
	EventBus.notify.emit("⚠ Escasez de %s: su precio sube. Comprá con cuidado." % ItemDB.display_name(raw), "warning")

func _ev_worker_highlight() -> void:
	var ws: Array = GameManager.workers.workers
	if ws.is_empty():
		return
	var w = ws[randi() % ws.size()]
	var best := ""
	var best_v := -1.0
	for k in Worker.SKILL_KEYS:
		var v: float = float(w.skills.get(k, 0.5))
		if v > best_v:
			best_v = v
			best = k
	w.skills[best] = clampf(best_v + 0.08, 0.2, 1.0)
	EventBus.notify.emit("👷 %s destacó esta semana y mejoró su habilidad (%s)." % [w.worker_name, best], "success")

func _ev_subsidy() -> void:
	var amount := 2000.0 + GameState.company_level * 500.0
	GameManager.economy.earn(amount, "misc")
	EventBus.notify.emit("💰 Subsidio industrial: +%s" % Fmt.money(amount), "success")

func _ev_special_contract() -> void:
	if GameManager.contracts and GameManager.contracts.has_method("add_special_offer"):
		GameManager.contracts.add_special_offer()
		EventBus.notify.emit("💎 Oportunidad: apareció un contrato especial en 📋 Contratos.", "info")

# --- Helpers ----------------------------------------------------------------
func _a_produced_product() -> String:
	if GameManager.production == null:
		return ""
	for id in GameManager.production.produced_total.keys():
		if int(GameManager.production.produced_total[id]) > 0:
			return String(id)
	return ""
