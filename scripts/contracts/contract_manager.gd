extends Node
## ContractManager — ofertas de clientes, aceptación y cumplimiento (spec §15).
##
## Genera ofertas a partir de data/contracts/contracts.json. Al aceptar, fija el
## plazo. Cada minuto entrega producto disponible del stock; al completar, paga
## y sube reputación. Si vence el plazo, aplica penalización y baja reputación.

const OFFER_REFRESH_DAYS := 2
const MAX_OFFERS := 4

var templates: Array = []
var offers: Array = []            # Array[Contract] disponibles
var active: Array = []            # Array[Contract] aceptados
var _last_refresh_day: int = 0

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
	for i in range(min(3, templates.size())):
		offers.append(_make_from_template(templates[i]))
	for c in offers:
		EventBus.contract_offered.emit(c)

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
	# Nuevas ofertas periódicas.
	if day - _last_refresh_day >= OFFER_REFRESH_DAYS and offers.size() < MAX_OFFERS and not templates.is_empty():
		_last_refresh_day = day
		var t: Dictionary = templates[randi() % templates.size()]
		var c := _make_from_template(t)
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
