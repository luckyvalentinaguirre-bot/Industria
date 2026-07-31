extends Resource
class_name Contract
## Contract — pedido de un cliente (spec §15).
##
## El jugador decide si acepta. Al aceptar se fija un plazo; a medida que se
## produce el producto, se va entregando desde el stock. Cumplir paga y sube
## reputación; incumplir aplica penalización y baja reputación.

@export var id: String = ""
@export var type: String = "normal"   # facil | grande | urgente | rentable | especial
@export var client: String = ""
@export var product: String = ""
@export var amount: int = 0
@export var payment: float = 0.0
@export var deadline_days: int = 7
@export var penalty: float = 0.0
@export var reputation: int = 0
## Bonificación extra si se completa antes del plazo (spec §6/§23).
@export var bonus: float = 0.0

# Estado dinámico
@export var accepted: bool = false
@export var deadline_day: int = 0
@export var delivered: int = 0
@export var completed: bool = false
@export var failed: bool = false

func remaining() -> int:
	return max(0, amount - delivered)

func progress_ratio() -> float:
	return 0.0 if amount <= 0 else clampf(float(delivered) / float(amount), 0.0, 1.0)

func days_left() -> int:
	return deadline_day - GameState.day

func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "client": client, "product": product, "amount": amount,
		"payment": payment, "deadline_days": deadline_days, "penalty": penalty,
		"reputation": reputation, "bonus": bonus, "accepted": accepted, "deadline_day": deadline_day,
		"delivered": delivered, "completed": completed, "failed": failed,
	}

static func from_dict(d: Dictionary) -> Contract:
	var c := Contract.new()
	c.id = String(d.get("id", ""))
	c.type = String(d.get("type", "normal"))
	c.client = String(d.get("client", ""))
	c.product = String(d.get("product", ""))
	c.amount = int(d.get("amount", 0))
	c.payment = float(d.get("payment", 0.0))
	c.deadline_days = int(d.get("deadline_days", 7))
	c.penalty = float(d.get("penalty", 0.0))
	c.reputation = int(d.get("reputation", 0))
	c.bonus = float(d.get("bonus", 0.0))
	c.accepted = bool(d.get("accepted", false))
	c.deadline_day = int(d.get("deadline_day", 0))
	c.delivered = int(d.get("delivered", 0))
	c.completed = bool(d.get("completed", false))
	c.failed = bool(d.get("failed", false))
	return c
