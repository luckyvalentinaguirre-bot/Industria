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
	# Eventos económicos con DECISIÓN (spec §3): descuento de proveedor, cliente
	# con adelanto y pico de demanda. Sólo cuando hay contexto para decidir.
	if GameManager.market and GameManager.storage:
		out.append(_ev_supplier_discount)
	if GameManager.contracts and GameManager.economy:
		out.append(_ev_rush_client)
	if _a_produced_product() != "":
		out.append(_ev_demand_decision)
	# Jugadas de la competencia (nueva capa): sólo si hay rivales en juego.
	if GameManager.rival and not GameManager.rival.rivals.is_empty():
		out.append(_ev_rival_price_war)
		out.append(_ev_rival_retires)
		if GameState.company_level >= 3:
			out.append(_ev_rival_tender)
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

# --- Eventos económicos con DECISIÓN (spec §3) ------------------------------
## Un proveedor ofrece un lote con descuento: comprar ahora barato u omitir.
func _ev_supplier_discount() -> void:
	var raw: String = RAW_ITEMS[randi() % RAW_ITEMS.size()]
	var qty := 40
	var unit: float = GameManager.market.current_price(raw)
	var full: float = unit * qty
	var deal: float = full * 0.85    # 15% de descuento
	var name := ItemDB.display_name(raw)
	var opts: Array = [
		{ "label": "📦 Comprar %d %s con -15%% (%s)" % [qty, name, Fmt.money(deal)],
		  "action": func():
			if GameManager.economy.spend(deal, "purchases"):
				GameManager.storage.deposit(raw, qty)
				EventBus.notify.emit("📦 Aprovechaste el descuento de %s." % name, "success")
			else:
				EventBus.notify.emit("Sin caja para el descuento de %s." % name, "error") },
		{ "label": "Rechazar la oferta", "action": func(): pass },
	]
	EventBus.decision_requested.emit("📦 Descuento de proveedor",
		"El proveedor de %s ofrece un 15%% de descuento por un lote de %d unidades." % [name, qty],
		opts)

## Un cliente ofrece un adelanto por sumar un contrato especial a tu cartera.
func _ev_rush_client() -> void:
	var advance := 1200.0 + GameState.company_level * 400.0
	var opts: Array = [
		{ "label": "🤝 Aceptar adelanto (+%s) y tomar el contrato" % Fmt.money(advance),
		  "action": func():
			GameManager.economy.earn(advance, "misc")
			if GameManager.contracts.has_method("add_special_offer"):
				GameManager.contracts.add_special_offer()
			EventBus.notify.emit("🤝 Cliente asegurado: contrato especial en 📋 Contratos.", "success") },
		{ "label": "Rechazar (mantené tu cartera actual)", "action": func(): pass },
	]
	EventBus.decision_requested.emit("🏭 Un cliente quiere tu producción",
		"Una empresa te ofrece un adelanto de %s a cambio de comprometer parte de tu producción." % Fmt.money(advance),
		opts)

## Pico de demanda de un producto: decidir si apostar fuerte o mantener.
func _ev_demand_decision() -> void:
	var p := _a_produced_product()
	if p == "" or GameManager.market == null:
		return
	var name := ItemDB.display_name(p)
	var opts: Array = [
		{ "label": "📈 Apostar a %s (demanda alta, más días)" % name,
		  "action": func():
			GameManager.market.apply_demand(p, 1.55, 6)
			EventBus.notify.emit("📈 Apostaste a %s: precio alto por varios días." % name, "success") },
		{ "label": "Mantener (subida moderada y corta)",
		  "action": func(): GameManager.market.apply_demand(p, 1.2, 3) },
		{ "label": "Ignorar", "action": func(): pass },
	]
	EventBus.decision_requested.emit("📈 Sube la demanda de %s" % name,
		"La demanda de %s aumentó esta semana. ¿Cómo respondés?" % name,
		opts)

# --- Jugadas de la competencia (spec competencia) ---------------------------
## Un rival baja precios en tu rama: defendé tu cuota (bajás margen) o mantené
## tu precio (el rival gana capacidad). Trade-off margen vs. cuota de mercado.
func _ev_rival_price_war() -> void:
	var branch: String = GameManager.specialization.current() if GameManager.specialization else ""
	var r: Dictionary = GameManager.rival.random_rival(branch)
	if r.is_empty():
		return
	var rname: String = String(r["name"])
	var sig: Array = []
	if GameManager.specialization and GameManager.specialization.has_chosen():
		sig = GameManager.specialization.signature_products()
	var opts: Array = [
		{ "label": "⚔ Igualar precios (defendé tu cuota, -margen)",
		  "action": func():
			for p in sig:
				GameManager.market.apply_demand(String(p), 0.9, 4)
			GameState.reputation = clampi(GameState.reputation + 2, 0, 100)
			EventBus.reputation_changed.emit(GameState.reputation)
			EventBus.notify.emit("⚔ Defendiste tu cuota frente a %s." % rname, "info") },
		{ "label": "Mantener precio (el rival crece)",
		  "action": func():
			GameManager.rival.rival_gains_capacity(branch, 1.06)
			EventBus.notify.emit("%s ganó terreno en tu rama." % rname, "warning") },
	]
	EventBus.decision_requested.emit("⚔ Guerra de precios",
		"%s bajó sus precios en tu rama. ¿Defendés tu cuota de mercado o protegés tu margen?" % rname,
		opts)

## Un rival se retira de la región: mejora tu posición relativa (positivo).
func _ev_rival_retires() -> void:
	var branch: String = GameManager.specialization.current() if GameManager.specialization else ""
	var name: String = GameManager.rival.remove_random_rival(branch)
	if name == "":
		return
	EventBus.notify.emit("📉 %s se retiró de la región: tu cuota de mercado sube." % name, "success")

## Un rival te desafía por un contrato: aparece una licitación (requiere reputación).
func _ev_rival_tender() -> void:
	var c: Contract = GameManager.contracts._gen_typed("licitacion")
	GameManager.contracts.offers.append(c)
	EventBus.contract_offered.emit(c)
	EventBus.notify.emit("🏆 Licitación disputada en 📋 Contratos: superá la puja del rival (reputación %d)." % c.rival_bid, "info")

# --- Helpers ----------------------------------------------------------------
func _a_produced_product() -> String:
	if GameManager.production == null:
		return ""
	for id in GameManager.production.produced_total.keys():
		if int(GameManager.production.produced_total[id]) > 0:
			return String(id)
	return ""
