extends Node
## ObjectiveManager — campaña guiada DESDE CERO (spec §2, §3, §7, §8, §23).
##
## El juego arranca con un terreno vacío y poco capital. Esta campaña acompaña el
## crecimiento: banco de trabajo manual → primeras ventas → capital → primera
## máquina industrial → producción → contratos → personal → línea → expansión →
## complejo industrial. Cada objetivo lleva naturalmente al siguiente y explica
## QUÉ hacer, POR QUÉ y CUÁNTO falta (progreso X/Y).
##
## Se apoya en señales del EventBus. Mantiene metas de largo plazo y la condición
## de victoria (llegar a Complejo Industrial, nivel 5). scripts/core/.

var objectives: Array = []         # [{id, title, done, reward, long, target, progress, hint, money}]
var won: bool = false
var _started: bool = false

## Reputación extra por hitos (spec §5): cada objetivo importante da prestigio.
const REP_REWARD := {
	"sell": 2, "contract": 3, "choose_branch": 2, "first_machine": 4,
	"level2": 3, "produce50": 3, "line": 5, "expand": 5, "top": 15,
}

func _ready() -> void:
	_define_objectives()
	EventBus.item_produced.connect(_on_produced)
	EventBus.transaction.connect(_on_transaction)
	EventBus.contract_completed.connect(_on_contract)
	EventBus.worker_hired.connect(_on_worker_hired)
	EventBus.machine_placed.connect(_on_machine_placed)
	EventBus.factory_expanded.connect(_on_expanded)
	EventBus.branch_chosen.connect(func(_id, _n): _complete("choose_branch"))
	EventBus.day_passed.connect(func(_d): _check_long_term())
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_loaded.connect(_on_game_started)
	EventBus.money_changed.connect(_on_money)
	EventBus.reputation_changed.connect(func(_r): _check_long_term())
	EventBus.company_level_changed.connect(_on_level)

func _on_game_started() -> void:
	_started = true
	EventBus.objectives_updated.emit()

## Campaña guiada: cada paso tiene una RAZÓN dentro del crecimiento de la empresa.
func _define_objectives() -> void:
	objectives = [
		{"id": "workbench", "title": "Instalá tu banco de trabajo", "hint": "Abrí ☰ Menú → 🏭 Fábrica y construí el Banco de trabajo: tu primer puesto de producción manual.", "done": false, "reward": 800, "long": false},
		{"id": "craft", "title": "Fabricá tu primera herramienta", "hint": "Comprá chatarra en 💰 Economía; el banco la convierte en herramientas para vender.", "done": false, "reward": 800, "long": false},
		{"id": "sell", "title": "Vendé tu primer lote", "hint": "Abrí 💰 Economía → Vender y convertí tus herramientas en dinero.", "done": false, "reward": 1000, "long": false},
		{"id": "cash6k", "title": "Reuní $6.000 de capital", "hint": "Producí y vendé para financiar tu primera máquina industrial.", "done": false, "reward": 1500, "long": false, "target": 6000, "progress": 0, "money": true},
		{"id": "level2", "title": "Alcanzá Nivel 2 (Pequeño productor)", "hint": "Sumá valor y producción: al subir de nivel elegís tu rama y se desbloquean máquinas.", "done": false, "reward": 2000, "long": false},
		{"id": "choose_branch", "title": "Elegí tu rama industrial", "hint": "En 🔬 Tecnología elegí Metalurgia, Madera o Energía: definirá tu fábrica.", "done": false, "reward": 1500, "long": false},
		{"id": "first_machine", "title": "Construí tu primera máquina industrial", "hint": "Colocá una máquina de tu rama desde 🏗 Construcción. ¡Un gran salto!", "done": false, "reward": 2500, "long": false},
		{"id": "produce50", "title": "Producí 50 unidades industriales", "hint": "Comprá materia prima y conectá una cinta hacia tu máquina de producción.", "done": false, "reward": 2000, "long": false, "target": 50, "progress": 0},
		{"id": "contract", "title": "Cumplí tu primer contrato", "hint": "En 📋 Contratos aceptá un pedido y entregá lo solicitado a tiempo.", "done": false, "reward": 2500, "long": false},
		{"id": "hire", "title": "Contratá a tu primer trabajador", "hint": "En 👷 Personal contratá un operario: aumenta la productividad de la fábrica.", "done": false, "reward": 1500, "long": false},
		{"id": "line", "title": "Montá una segunda máquina industrial", "hint": "Encadená máquinas con cintas para formar tu primera línea de producción.", "done": false, "reward": 2500, "long": false},
		{"id": "expand", "title": "Ampliá el terreno de tu fábrica", "hint": "En 🔬 Tecnología ampliá el terreno para poder construir más.", "done": false, "reward": 3000, "long": false},
		{"id": "top", "title": "Convertite en Complejo Industrial (Nivel 5)", "hint": "La gran meta: hacé crecer tu taller hasta el mayor complejo industrial de la región.", "done": false, "reward": 15000, "long": false},
		# Metas de largo plazo (spec §12).
		{"id": "machines50", "title": "🏭 Construí 50 máquinas", "done": false, "reward": 20000, "long": true},
		{"id": "million", "title": "💰 Alcanzá $1.000.000 de capital", "done": false, "reward": 25000, "long": true},
		{"id": "units10k", "title": "⚙️ Producí 10.000 unidades", "done": false, "reward": 20000, "long": true},
		{"id": "contracts100", "title": "📦 Completá 100 contratos", "done": false, "reward": 30000, "long": true},
		{"id": "rep100", "title": "⭐ Alcanzá reputación 100", "done": false, "reward": 20000, "long": true},
	]

func _find(id: String) -> Dictionary:
	for o in objectives:
		if o["id"] == id:
			return o
	return {}

## Objetivo actual: el primer objetivo guiado sin completar (alimenta el HUD, §11).
func current() -> Dictionary:
	for o in objectives:
		if not o.get("long", false) and not o["done"]:
			return o
	return {}

## Texto de progreso legible ("32 / 50", "$4.200 / $6.000" o "").
func progress_text(o: Dictionary) -> String:
	if not o.has("target"):
		return ""
	var target := int(o["target"])
	var prog := int(o.get("progress", 0))
	if o.get("money", false):
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
	# Reputación por hito.
	var rep: int = int(REP_REWARD.get(id, 0))
	if rep > 0:
		GameState.reputation = clampi(GameState.reputation + rep, 0, 100)
		EventBus.reputation_changed.emit(GameState.reputation)
	EventBus.objective_completed.emit(id, o["title"])
	EventBus.objectives_updated.emit()
	var rep_txt := "  ⭐+%d" % rep if rep > 0 else ""
	EventBus.notify.emit("Objetivo cumplido: %s (+%s)%s" % [o["title"], Fmt.money(reward), rep_txt], "success")
	if id == "top":
		_win()

func completed_count() -> int:
	var n := 0
	for o in objectives:
		if o["done"]:
			n += 1
	return n

# --- Detección --------------------------------------------------------------
func _on_produced(item_id: String, qty: int) -> void:
	if item_id == "hand_tool":
		_complete("craft")
	# El producto insignia depende de la rama elegida (metal/madera/energía).
	if GameManager.specialization and GameManager.specialization.signature_products().has(item_id):
		_advance("produce50", qty)
	_check_long_term()

func _on_transaction(category: String, _amount: float, is_income: bool) -> void:
	if is_income and category == "sales":
		_complete("sell")

func _on_contract(_c: Resource) -> void:
	_complete("contract")

func _on_worker_hired(_w: Node) -> void:
	if GameManager.workers and GameManager.workers.workers.size() >= 1:
		_complete("hire")

func _on_machine_placed(m: Node) -> void:
	var mid := String(m.machine_id) if ("machine_id" in m) else ""
	if mid == "workbench":
		_complete("workbench")
		return
	# Máquina industrial (cualquiera que no sea el banco de trabajo).
	_complete("first_machine")
	if _industrial_count() >= 2:
		_complete("line")

func _industrial_count() -> int:
	var n := 0
	if GameManager.machines:
		for m in GameManager.machines.machines:
			if String(m.machine_id) != "workbench":
				n += 1
	return n

func _on_expanded(_size: Vector2i) -> void:
	_complete("expand")

func _on_level(level: int, _name: String) -> void:
	if level >= 2:
		_complete("level2")
	if level >= 5:
		_complete("top")
	_check_long_term()

func _on_money(money: float) -> void:
	_set_progress("cash6k", int(money))
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
	EventBus.notify.emit("¡Complejo industrial alcanzado! Tu taller se convirtió en una gran industria.", "success")

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "objectives": objectives.duplicate(true), "won": won }

func from_dict(data: Dictionary) -> void:
	if data.has("objectives"):
		objectives = (data["objectives"] as Array).duplicate(true)
	won = bool(data.get("won", false))
	EventBus.objectives_updated.emit()
