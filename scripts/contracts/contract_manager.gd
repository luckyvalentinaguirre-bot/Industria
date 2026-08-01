extends Node
## ContractManager — ofertas de clientes, aceptación y cumplimiento (spec §15).
##
## Genera ofertas a partir de data/contracts/contracts.json. Al aceptar, fija el
## plazo. Cada minuto entrega producto disponible del stock; al completar, paga
## y sube reputación. Si vence el plazo, aplica penalización y baja reputación.

const OFFER_REFRESH_DAYS := 2
const MAX_OFFERS := 5

const TYPES := ["facil", "grande", "urgente", "rentable", "especial", "volumen"]
const TYPE_LABELS := {
	"facil": "🟢 Fácil", "grande": "📦 Grande", "urgente": "⏱ Urgente",
	"rentable": "💎 Rentable", "especial": "⭐ Especial", "volumen": "🏭 Volumen",
	"programa": "🤝 Programa", "normal": "Contrato",
}
const CLIENTS := ["Construcciones Delta", "Metalúrgica Andes", "Ensambladora Rivas",
	"Talleres Sur", "Industrias Kappa", "Logística Omega", "Fábrica Zeta"]
const PRODUCTS := ["metal_plate", "copper_part", "industrial_part",
	"metal_piece", "industrial_comp", "plank", "pallet", "brick", "block", "fuel",
	"steel", "glass", "plastic", "copper_wire", "electronic_component", "machine_part"]

var templates: Array = []
var offers: Array = []            # Array[Contract] disponibles
var active: Array = []            # Array[Contract] aceptados
var _last_refresh_day: int = 0
var _seq: int = 0

## Programa de cliente de mediano plazo (spec §6/§7): fases escalonadas del
## mismo cliente por tu producto insignia. {} = sin programa activo.
const PROGRAM_PHASES := 3
var program: Dictionary = {}      # {client, product, phase}

func _ready() -> void:
	templates = _load_templates()
	EventBus.minute_passed.connect(_on_minute)
	EventBus.day_passed.connect(_on_day)
	call_deferred("_seed_offers")

func _load_templates() -> Array:
	var path := "res://data/contracts/contracts.json"
	if not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return data.get("contracts", [])
	return []

func _seed_offers() -> void:
	# Arranca con una mezcla de tipos para variedad inmediata.
	for t in ["facil", "grande", "rentable"]:
		offers.append(_gen_typed(t))
	for c in offers:
		EventBus.contract_offered.emit(c)

## Genera un contrato de un tipo dado con perfil propio (spec §15).
func _gen_typed(type: String) -> Contract:
	_seq += 1
	var c := Contract.new()
	c.type = type
	c.id = "%s_%d" % [type, _seq]
	c.client = CLIENTS[randi() % CLIENTS.size()]
	var product: String = _pick_product()
	var unit: float = _unit_value(product)
	var amount := 100
	var pay_mult := 1.2
	var pen_mult := 0.3
	var deadline := 7
	var rep := 4
	match type:
		"facil":
			product = ["hand_tool", "metal_plate", "iron_ingot", "copper_part"][randi() % 4]
			unit = _unit_value(product)
			amount = randi_range(20, 60); pay_mult = 1.2; pen_mult = 0.2; deadline = randi_range(6, 9); rep = 2
		"grande":
			amount = randi_range(250, 500); pay_mult = 1.3; pen_mult = 0.35; deadline = randi_range(10, 14); rep = 6
		"urgente":
			amount = randi_range(60, 140); pay_mult = 1.65; pen_mult = 0.6; deadline = randi_range(2, 3); rep = 5
			if GameManager.market:
				GameManager.market.apply_demand(product, 1.35, 4)
		"rentable":
			amount = randi_range(80, 160); pay_mult = 1.9; pen_mult = 0.3; deadline = randi_range(6, 9); rep = 4
		"especial":
			product = "simple_motor"; unit = _unit_value(product)
			amount = randi_range(20, 50); pay_mult = 1.55; pen_mult = 0.5; deadline = randi_range(8, 12); rep = 8
		"volumen":
			# Gran pedido: obliga a ampliar capacidad (¿otra máquina? ¿automatizar?).
			amount = randi_range(400, 800); pay_mult = 1.4; pen_mult = 0.45; deadline = randi_range(5, 8); rep = 10
	c.product = product
	c.amount = amount
	# La reputación mejora las ofertas: mejores clientes pagan más (spec §8).
	var rep_mult: float = 0.9 + clampf(GameState.reputation / 100.0, 0.0, 1.0) * 0.3   # 0.9 .. 1.2
	c.payment = round(unit * amount * pay_mult * rep_mult / 100.0) * 100.0
	c.penalty = round(unit * amount * pen_mult / 100.0) * 100.0
	c.deadline_days = deadline
	c.reputation = rep
	# Bonus por entrega temprana (spec §6/§23): premia tener capacidad de sobra.
	# El cultivo regulado paga bonus mayor (alto riesgo/alta recompensa).
	var bonus_mult := 0.35 if type == "rentable" else 0.25
	if c.product == "regulated_goods":
		bonus_mult = 0.5
	c.bonus = round(c.payment * bonus_mult / 100.0) * 100.0
	return c

## Elige un producto para el contrato, sesgado hacia el producto insignia de la
## rama industrial elegida (spec §20: los contratos refuerzan tu identidad).
func _pick_product() -> String:
	var pool: Array = PRODUCTS.duplicate()
	if GameManager.specialization and GameManager.specialization.has_chosen():
		for s in GameManager.specialization.signature_products():
			pool.append(s); pool.append(s); pool.append(s)   # triple peso
	return String(pool[randi() % pool.size()])

func _unit_value(product: String) -> float:
	if GameManager.market:
		return GameManager.market.current_price(product)
	return ItemDB.base_price(product)

## ¿Puede la fábrica cumplir el contrato a tiempo con su capacidad actual?
## Devuelve {feasible, rate (u/min actual), needed (u/min requerido), stock}.
## Es la información que convierte cada oferta en una DECISIÓN (spec §7).
func feasibility(c: Contract) -> Dictionary:
	var stock: int = GameManager.storage.count(c.product) if GameManager.storage else 0
	var rate: float = GameManager.production.capacity_for(c.product) if GameManager.production else 0.0
	# Minutos reales hasta el plazo (los días de juego pasan en tiempo real).
	var real_min: float = maxf(0.1, c.deadline_days * 1440.0 / TimeManager.GAME_MINUTES_PER_REAL_SECOND / 60.0)
	var needed: float = maxf(0.0, (float(c.amount) - float(stock)) / real_min)
	var feasible: bool = stock >= c.amount or rate >= needed - 0.01
	return { "feasible": feasible, "rate": rate, "needed": needed, "stock": stock }

func type_label(c: Contract) -> String:
	return TYPE_LABELS.get(c.type, "Contrato")

func _make_from_template(t: Dictionary) -> Contract:
	var c := Contract.new()
	c.id = "%s_%d" % [String(t.get("id", "c")), Time.get_ticks_msec()]
	c.client = String(t.get("client", "Cliente"))
	c.product = String(t.get("product", ""))
	c.amount = int(t.get("amount", 0))
	c.payment = float(t.get("payment", 0.0))
	c.deadline_days = int(t.get("deadline_days", 7))
	c.penalty = float(t.get("penalty", 0.0))
	c.reputation = int(t.get("reputation", 0))
	return c

# --- Aceptación / rechazo ---------------------------------------------------
func accept(c: Contract) -> void:
	if not offers.has(c):
		return
	offers.erase(c)
	c.accepted = true
	c.deadline_day = GameState.day + c.deadline_days
	active.append(c)
	EventBus.contract_accepted.emit(c)
	EventBus.notify.emit("Contrato aceptado: %d× %s para %s" % [c.amount, ItemDB.display_name(c.product), c.client], "info")

## Oferta especial temporal (la dispara un evento): muy rentable, plazo corto.
func add_special_offer() -> Contract:
	var c := _gen_typed("rentable")
	c.payment = round(c.payment * 1.3 / 100.0) * 100.0
	c.bonus = round(c.payment * 0.35 / 100.0) * 100.0
	c.reputation += 4
	offers.append(c)
	EventBus.contract_offered.emit(c)
	return c

func decline(c: Contract) -> void:
	offers.erase(c)
	# Rechazar una fase abandona el programa (podrá reaparecer más adelante).
	if c.program_phase > 0:
		program = {}

# --- Cumplimiento -----------------------------------------------------------
func _on_minute(_d: int, _h: int, _m: int) -> void:
	for c in active.duplicate():
		if c.completed or c.failed:
			continue
		_deliver(c)
		if c.delivered >= c.amount:
			_complete(c)

func _deliver(c: Contract) -> void:
	var need := c.remaining()
	if need <= 0:
		return
	var taken: int = GameManager.storage.withdraw(c.product, need)
	c.delivered += taken

func _complete(c: Contract) -> void:
	c.completed = true
	active.erase(c)
	GameState.contracts_completed += 1
	GameManager.economy.earn(c.payment, "sales")
	# Bonus si se entregó ANTES del último día del plazo (planificar capacidad).
	var early: bool = c.bonus > 0.0 and GameState.day < c.deadline_day
	if early:
		GameManager.economy.earn(c.bonus, "sales")
	_add_reputation(c.reputation)
	# Programa de cliente: avanzar a la siguiente fase (o gran recompensa final).
	if c.program_phase > 0:
		_advance_program(c)
	EventBus.contract_completed.emit(c)
	if early:
		EventBus.notify.emit("¡Contrato cumplido antes de plazo! %s pagó %s (+bonus %s)" % [c.client, Fmt.money(c.payment), Fmt.money(c.bonus)], "success")
	else:
		EventBus.notify.emit("¡Contrato cumplido! %s pagó %s" % [c.client, Fmt.money(c.payment)], "success")

func _fail(c: Contract) -> void:
	c.failed = true
	active.erase(c)
	# Devuelve lo ya entregado al stock (no se malgasta el producto).
	if c.delivered > 0:
		GameManager.storage.deposit(c.product, c.delivered)
	GameManager.economy.force_spend(c.penalty, "contract_penalty")
	_add_reputation(-c.reputation - 3)
	if c.program_phase > 0:
		program = {}   # se cae el programa al incumplir una fase
	EventBus.contract_failed.emit(c)
	EventBus.notify.emit("Contrato incumplido con %s. Penalización %s" % [c.client, Fmt.money(c.penalty)], "error")

func _add_reputation(delta: int) -> void:
	GameState.reputation = clampi(GameState.reputation + delta, 0, 100)
	EventBus.reputation_changed.emit(GameState.reputation)

# --- Ciclo diario -----------------------------------------------------------
func _on_day(day: int) -> void:
	# Vencimientos.
	for c in active.duplicate():
		if not c.completed and not c.failed and GameState.day > c.deadline_day:
			_fail(c)
	# Nuevas ofertas periódicas de tipo aleatorio.
	if day - _last_refresh_day >= OFFER_REFRESH_DAYS and offers.size() < MAX_OFFERS:
		_last_refresh_day = day
		var c := _gen_typed(TYPES[randi() % TYPES.size()])
		offers.append(c)
		EventBus.contract_offered.emit(c)
	# Programa de cliente: se ofrece a partir de Fabricante (N3) si no hay uno.
	if program.is_empty() and GameState.company_level >= 3 and randf() < 0.5:
		_start_program()

# --- Programa de cliente (mediano plazo) ------------------------------------
func _start_program() -> void:
	var product := _pick_product()
	if GameManager.specialization and GameManager.specialization.has_chosen():
		var sig: Array = GameManager.specialization.signature_products()
		if not sig.is_empty():
			product = String(sig[randi() % sig.size()])
	program = { "client": CLIENTS[randi() % CLIENTS.size()], "product": product, "phase": 1 }
	_offer_program_contract()

func _offer_program_contract() -> void:
	if program.is_empty() or offers.size() >= MAX_OFFERS + 1:
		return
	var phase: int = int(program["phase"])
	var product: String = String(program["product"])
	var unit: float = _unit_value(product)
	_seq += 1
	var c := Contract.new()
	c.type = "programa"
	c.id = "prog_%d" % _seq
	c.client = String(program["client"])
	c.product = product
	c.amount = 120 * phase                     # escala con cada fase
	c.payment = round(unit * c.amount * (1.35 + phase * 0.05) / 100.0) * 100.0
	c.penalty = round(c.payment * 0.35 / 100.0) * 100.0
	c.bonus = round(c.payment * 0.3 / 100.0) * 100.0
	c.deadline_days = 5 + phase
	c.reputation = 6 + phase * 3
	c.program_phase = phase
	c.program_total = PROGRAM_PHASES
	offers.append(c)
	EventBus.contract_offered.emit(c)
	EventBus.notify.emit("%s propone un programa: Fase %d/%d (%d× %s)" % [c.client, phase, PROGRAM_PHASES, c.amount, ItemDB.display_name(product)], "info")

## Avanza el programa al completar una fase; la última da una gran recompensa.
func _advance_program(c: Contract) -> void:
	if program.is_empty() or int(program.get("phase", 0)) != c.program_phase:
		return
	if c.program_phase >= PROGRAM_PHASES:
		var reward: float = c.payment * 1.5
		GameManager.economy.earn(reward, "sales")
		_add_reputation(15)
		EventBus.notify.emit("¡Programa de %s completado! Bonificación final %s y +15 reputación." % [c.client, Fmt.money(reward)], "success")
		program = {}
	else:
		program["phase"] = c.program_phase + 1
		_offer_program_contract()

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var off: Array = []
	for c in offers:
		off.append(c.to_dict())
	var act: Array = []
	for c in active:
		act.append(c.to_dict())
	return { "offers": off, "active": act, "last_refresh": _last_refresh_day, "program": program.duplicate() }

func from_dict(data: Dictionary) -> void:
	offers.clear()
	active.clear()
	for d in data.get("offers", []):
		offers.append(Contract.from_dict(d))
	for d in data.get("active", []):
		active.append(Contract.from_dict(d))
	_last_refresh_day = int(data.get("last_refresh", 0))
	program = (data.get("program", {}) as Dictionary).duplicate()
