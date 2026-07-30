extends Node
## ObjectiveManager — campaña guiada y metas de la partida (spec §2, §3, §10, §11).
##
## Da al juego un LOOP con propósito: una secuencia ordenada de objetivos donde
## cada uno lleva naturalmente al siguiente (reactivar → producir → vender →
## contratar → crecer → ascender → construir → expandir → saldar la deuda). Cada
## objetivo tiene recompensa y, cuando aplica, progreso numérico (X/Y) para que
## el jugador sepa siempre QUÉ hacer, POR QUÉ y CUÁNTO le falta.
##
## Se apoya en señales del EventBus (no se acopla a los sistemas). Además de la
## campaña guiada mantiene metas de largo plazo y la condición de victoria
## (saldar la deuda). Nota de estructura: progresión del juego → scripts/core/.

var objectives: Array = []         # [{id, title, done, reward, long, target, progress, hint}]
var won: bool = false
var _initial_debt: float = 0.0
var _started: bool = false

func _ready() -> void:
	_define_objectives()
	EventBus.machine_repaired.connect(_on_repair)
	EventBus.item_produced.connect(_on_produced)
	EventBus.transaction.connect(_on_transaction)
	EventBus.contract_completed.connect(_on_contract)
	EventBus.worker_hired.connect(_on_worker_hired)
	EventBus.machine_placed.connect(_on_machine_placed)
	EventBus.factory_expanded.connect(_on_expanded)
	EventBus.debt_changed.connect(_on_debt_changed)
	EventBus.day_passed.connect(_on_day)
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_loaded.connect(_on_game_started)
	EventBus.money_changed.connect(_on_money)
	EventBus.reputation_changed.connect(func(_r): _check_long_term())
	EventBus.company_level_changed.connect(_on_level)

func _on_game_started() -> void:
	_started = true
	_initial_debt = maxf(1.0, GameState.debt)
	EventBus.objectives_updated.emit()

## Campaña guiada: cada paso tiene una RAZÓN dentro del desarrollo de la empresa.
func _define_objectives() -> void:
	objectives = [
		{"id": "repair", "title": "Reactivá la fundición averiada", "hint": "Seleccioná la fundición y pulsá 🔧 Reparar para que la línea vuelva a producir.", "done": false, "reward": 1500, "long": false},
		{"id": "iron50", "title": "Producí 50 lingotes de hierro", "hint": "Comprá mineral en 💰 Economía y dejá que la fundición trabaje.", "done": false, "reward": 1500, "long": false, "target": 50, "progress": 0},
		{"id": "sell", "title": "Vendé tu primer lote en el mercado", "hint": "Abrí 💰 Economía → Vender y convertí producto en dinero.", "done": false, "reward": 1200, "long": false},
		{"id": "contract", "title": "Cumplí tu primer contrato", "hint": "Aceptá un contrato en 📋 Contratos y entregá lo pedido a tiempo.", "done": false, "reward": 2000, "long": false},
		{"id": "cash25k", "title": "Reuní $25.000 en caja", "hint": "Vendé producto y cumplí contratos para financiar tu crecimiento.", "done": false, "reward": 2500, "long": false, "target": 25000, "progress": 0},
		{"id": "hire", "title": "Contratá a tu primer trabajador", "hint": "En 👷 Personal contratá un operario: aumenta la productividad.", "done": false, "reward": 1500, "long": false},
		{"id": "plates100", "title": "Producí 100 placas metálicas", "hint": "La prensa convierte lingotes en placas: alimentá la cadena.", "done": false, "reward": 2500, "long": false, "target": 100, "progress": 0},
		{"id": "level2", "title": "Ascendé tu empresa a Nivel 2", "hint": "Sumá valor, máquinas y contratos: desbloquea nuevas construcciones.", "done": false, "reward": 3000, "long": false},
		{"id": "new_machine", "title": "Construí una máquina nueva", "hint": "Menú ☰ → 🏗 Construcción. Amplía tu capacidad de producción.", "done": false, "reward": 2500, "long": false},
		{"id": "expand", "title": "Ampliá el terreno de tu fábrica", "hint": "En 🔬 Investigación ampliá el terreno para construir más.", "done": false, "reward": 3000, "long": false},
		{"id": "halve_debt", "title": "Reducí la deuda a la mitad", "hint": "Pagá deuda desde 💰 Economía con tus ganancias.", "done": false, "reward": 5000, "long": false},
		{"id": "solvent", "title": "Saldá por completo la deuda", "hint": "Última meta: dejar la empresa libre de deuda.", "done": false, "reward": 10000, "long": false},
		# Metas de largo plazo (spec §12).
		{"id": "machines50", "title": "🏭 Construí 50 máquinas", "done": false, "reward": 20000, "long": true},
		{"id": "million", "title": "💰 Alcanzá $1.000.000 de capital", "done": false, "reward": 25000, "long": true},
		{"id": "units10k", "title": "⚙️ Producí 10.000 unidades", "done": false, "reward": 20000, "long": true},
		{"id": "contracts100", "title": "📦 Completá 100 contratos", "done": false, "reward": 30000, "long": true},
		{"id": "rep100", "title": "⭐ Alcanzá reputación 100", "done": false, "reward": 20000, "long": true},
		{"id": "corporation", "title": "🏢 Convertite en Corporación (nivel 5)", "done": false, "reward": 50000, "long": true},
	]

func _find(id: String) -> Dictionary:
	for o in objectives:
		if o["id"] == id:
			return o
	return {}

## Objetivo actual de la campaña: el primer objetivo guiado sin completar.
## Alimenta el rastreador compacto del HUD (spec §11).
func current() -> Dictionary:
	for o in objectives:
		if not o.get("long", false) and not o["done"]:
			return o
	return {}

## Texto de progreso legible para el HUD ("32 / 50", "$18.400 / $25.000" o "").
func progress_text(o: Dictionary) -> String:
	if not o.has("target"):
		return ""
	var target := int(o["target"])
	var prog := int(o.get("progress", 0))
	if o["id"] == "cash25k":
		return "%s / %s" % [Fmt.money(prog), Fmt.money(target)]
	return "%d / %d" % [prog, target]

func progress_ratio(o: Dictionary) -> float:
	if not o.has("target") or int(o["target"]) <= 0:
		return 0.0
	return clampf(float(o.get("progress", 0)) / float(o["target"]), 0.0, 1.0)

# --- Avance de progreso / cumplimiento --------------------------------------
func _advance(id: String, amount: int) -> void:
	var o := _find(id)
	if o.is_empty() or o["done"]:
		return
	o["progress"] = int(o.get("progress", 0)) + amount
	if int(o["progress"]) >= int(o.get("target", 0)):
		_complete(id)
	else:
		EventBus.objectives_updated.emit()

func _set_progress(id: String, value: int) -> void:
	var o := _find(id)
	if o.is_empty() or o["done"]:
		return
	var clamped: int = min(value, int(o.get("target", 0)))
	if clamped == int(o.get("progress", 0)):
		return
	o["progress"] = clamped
	if clamped >= int(o.get("target", 0)):
		_complete(id)
	else:
		EventBus.objectives_updated.emit()

func _complete(id: String) -> void:
	var o := _find(id)
	if o.is_empty() or o["done"]:
		return
	o["done"] = true
	if o.has("target"):
		o["progress"] = int(o["target"])
	var reward := int(o.get("reward", 0))
	if reward > 0 and GameManager.economy:
		GameManager.economy.earn(reward, "misc")
		EventBus.objective_reward.emit("%s: +%s" % [o["title"], Fmt.money(reward)])
	EventBus.objective_completed.emit(id, o["title"])
	EventBus.objectives_updated.emit()
	EventBus.notify.emit("Objetivo cumplido: %s (+%s)" % [o["title"], Fmt.money(reward)], "success")
	if id == "solvent":
		_win()

func completed_count() -> int:
	var n := 0
	for o in objectives:
		if o["done"]:
			n += 1
	return n

# --- Detección --------------------------------------------------------------
func _on_repair(_m: Node) -> void:
	_complete("repair")

func _on_produced(item_id: String, qty: int) -> void:
	if item_id == "iron_ingot":
		_advance("iron50", qty)
	elif item_id == "metal_plate":
		_advance("plates100", qty)
	_check_long_term()

func _on_transaction(category: String, _amount: float, is_income: bool) -> void:
	if is_income and category == "sales":
		_complete("sell")

func _on_contract(_c: Resource) -> void:
	_complete("contract")

func _on_worker_hired(_w: Node) -> void:
	# Sólo cuenta la plantilla real (los operarios ambientales no se añaden a ella).
	if GameManager.workers and GameManager.workers.workers.size() >= 1:
		_complete("hire")

func _on_machine_placed(_m: Node) -> void:
	# El escenario inicial coloca máquinas ANTES de arrancar la partida; sólo
	# cuentan las que construye el jugador una vez iniciado el juego.
	if _started:
		_complete("new_machine")

func _on_expanded(_size: Vector2i) -> void:
	_complete("expand")

func _on_level(level: int, _name: String) -> void:
	if level >= 2:
		_complete("level2")
	_check_long_term()

func _on_money(money: float) -> void:
	_set_progress("cash25k", int(money))
	_check_long_term()

func _on_debt_changed(debt: float) -> void:
	if _initial_debt > 1.0 and debt <= _initial_debt * 0.5:
		_complete("halve_debt")
	if debt <= 0.0:
		_complete("solvent")

func _on_day(_day: int) -> void:
	_check_long_term()

## Metas de largo plazo: se comprueban por métricas reales de la simulación.
func _check_long_term() -> void:
	if GameManager.machines and GameManager.machines.count() >= 50:
		_complete("machines50")
	if GameState.money >= 1000000.0:
		_complete("million")
	if _units_produced() >= 10000:
		_complete("units10k")
	if GameState.contracts_completed >= 100:
		_complete("contracts100")
	if GameState.reputation >= 100:
		_complete("rep100")
	if GameState.company_level >= 5:
		_complete("corporation")

func _units_produced() -> int:
	var total := 0
	if GameManager.production:
		for v in GameManager.production.produced_total.values():
			total += int(v)
	return total

func _win() -> void:
	if won:
		return
	won = true
	EventBus.game_won.emit()
	EventBus.notify.emit("¡La empresa está saneada! Has salvado Industria.", "success")

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "objectives": objectives.duplicate(true), "won": won, "initial_debt": _initial_debt }

func from_dict(data: Dictionary) -> void:
	if data.has("objectives"):
		objectives = (data["objectives"] as Array).duplicate(true)
	won = bool(data.get("won", false))
	_initial_debt = float(data.get("initial_debt", _initial_debt))
	EventBus.objectives_updated.emit()
