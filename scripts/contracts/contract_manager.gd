extends Node
## ContractManager — ofertas de clientes, aceptación y cumplimiento (spec §15).
##
## Genera ofertas a partir de data/contracts/contracts.json. Al aceptar, fija el
## plazo. Cada minuto entrega producto disponible del stock; al completar, paga
## y sube reputación. Si vence el plazo, aplica penalización y baja reputación.

const OFFER_REFRESH_DAYS := 2
const MAX_OFFERS := 5

const TYPES := ["facil", "grande", "urgente", "rentable", "especial"]
const TYPE_LABELS := {
	"facil": "🟢 Fácil", "grande": "📦 Grande", "urgente": "⏱ Urgente",
	"rentable": "💎 Rentable", "especial": "⭐ Especial", "normal": "Contrato",
}
const CLIENTS := ["Construcciones Delta", "Metalúrgica Andes", "Ensambladora Rivas",
	"Talleres Sur", "Industrias Kappa", "Logística Omega", "Fábrica Zeta"]
const PRODUCTS := ["metal_plate", "copper_part", "industrial_part",
	"metal_piece", "industrial_comp"]

var templates: Array = []
var offers: Array = []            # Array[Contract] disponibles
var active: Array = []            # Array[Contract] aceptados
var _last_refresh_day: int = 0
var _seq: int = 0

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
	var product: String = PRODUCTS[randi() % PRODUCTS.size()]
	var unit: float = _unit_value(product)
	var amount := 100
	var pay_mult := 1.2
	var pen_mult := 0.3
	var deadline := 7
	var rep := 4
	match type:
		"facil":
			product = ["metal_plate", "iron_ingot", "copper_part"][randi() % 3]
			unit = _unit_value(product)
			amount = randi_range(30, 80); pay_mult = 1.15; pen_mult = 0.2; deadline = randi_range(6, 9); rep = 2
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
	c.product = product
	c.amount = amount
	c.payment = round(unit * amount * pay_mult / 100.0) * 100.0
	c.penalty = round(unit * amount * pen_mult / 100.0) * 100.0
	c.deadline_days = deadline
	c.reputation = rep
	return c

func _unit_value(product: String) -> float:
	if GameManager.market:
		return GameManager.market.current_price(product)
	return ItemDB.base_price(product)

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

func decline(c: Contract) -> void:
	offers.erase(c)

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
	_add_reputation(c.reputation)
	EventBus.contract_completed.emit(c)
	EventBus.notify.emit("¡Contrato cumplido! %s pagó %s" % [c.client, Fmt.money(c.payment)], "success")

func _fail(c: Contract) -> void:
	c.failed = true
	active.erase(c)
	# Devuelve lo ya entregado al stock (no se malgasta el producto).
	if c.delivered > 0:
		GameManager.storage.deposit(c.product, c.delivered)
	GameManager.economy.force_spend(c.penalty, "contract_penalty")
	_add_reputation(-c.reputation - 3)
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

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	var off: Array = []
	for c in offers:
		off.append(c.to_dict())
	var act: Array = []
	for c in active:
		act.append(c.to_dict())
	return { "offers": off, "active": act, "last_refresh": _last_refresh_day }

func from_dict(data: Dictionary) -> void:
	offers.clear()
	active.clear()
	for d in data.get("offers", []):
		offers.append(Contract.from_dict(d))
	for d in data.get("active", []):
		active.append(Contract.from_dict(d))
	_last_refresh_day = int(data.get("last_refresh", 0))
