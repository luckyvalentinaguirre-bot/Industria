extends Node
## RivalManager — competencia y mercado regional (nueva capa estratégica).
##
## Tu fábrica no opera en el vacío: comparte la región con empresas RIVALES que
## producen en las mismas ramas, crecen semana a semana y disputan cuota de
## mercado y contratos. Esto reconvierte cada número que ya existía —volumen de
## producción, reputación, precios, contratos— en una carrera con adversarios:
##
##  • CUOTA DE MERCADO: tu "capacidad" (u/min instaladas de tu rama) frente a la
##    de los rivales define tu posición (rank) y tu cuota. Escalar producción te
##    hace subir; los rivales crecen y son un blanco móvil.
##  • PRESIÓN DE PRECIOS: cuando los rivales dominan tu rama, el precio de venta
##    en mercado abierto baja (competencia). Tu reputación amortigua esa presión:
##    una marca fuerte vende más caro. (Lo aplica MarketManager.sell()).
##  • LICITACIONES: contratos muy rentables que sólo podés tomar si tu reputación
##    supera la puja del mejor rival de la rama (ContractManager). Da una meta
##    concreta a la reputación.
##  • JUGADAS DE RIVAL: eventos con decisión (bajan precios, se retiran, te
##    desafían por un contrato) — ver EventManager.
##  • LIDERAZGO: ser #1 de tu rama es un objetivo de largo plazo (ObjectiveManager).
##
## Es event-driven: sólo trabaja al cerrarse la semana (crecimiento + jugada) y
## responde consultas bajo demanda. Sin coste por frame (spec §16).
##
## Nota de estructura: economía/mercado → vive en scripts/economy/.

## Perfil de un rival: nombre, rama, capacidad (u/min equivalentes), reputación y
## crecimiento semanal. La "capacidad" es comparable a la producción del jugador.
var rivals: Array = []   # Array[Dictionary]

const NAMES := [
	"Aceros Cordillera", "Grupo Fabril Río", "Maderas del Valle", "PetroSur Industrial",
	"Constructora Meseta", "AgroTecno Pampa", "Metalúrgica Vega", "Ensambles del Plata",
	"Ladrillera Central", "Química Litoral",
]

func _ready() -> void:
	EventBus.game_started.connect(_seed)
	EventBus.week_passed.connect(_on_week)

# --- Alta inicial -----------------------------------------------------------
func _seed() -> void:
	rivals.clear()
	var branches: Array = _branch_ids()
	var used_names: Array = []
	# Un rival por rama como base + un par extra en ramas aleatorias → variedad.
	var picks: Array = branches.duplicate()
	for i in range(2):
		picks.append(branches[randi() % branches.size()])
	for b in picks:
		var nm: String = _pick_name(used_names)
		used_names.append(nm)
		rivals.append({
			"name": nm,
			"branch": b,
			"capacity": randf_range(9.0, 26.0),   # u/min equivalentes al arranque
			"reputation": randi_range(35, 70),
			"growth": randf_range(0.02, 0.055),    # crecimiento semanal
		})

func _pick_name(used: Array) -> String:
	for _i in range(20):
		var n: String = NAMES[randi() % NAMES.size()]
		if not used.has(n):
			return n
	return "Rival %d" % (used.size() + 1)

# --- Ciclo semanal ----------------------------------------------------------
func _on_week(_week: int) -> void:
	if rivals.is_empty():
		_seed()
	for r in rivals:
		# Crecen con su tasa; la reputación deriva suavemente hacia una meta.
		r["capacity"] = float(r["capacity"]) * (1.0 + float(r["growth"]))
		var target: float = 60.0 + randf_range(-10.0, 20.0)
		r["reputation"] = int(clampf(lerpf(float(r["reputation"]), target, 0.15), 10, 95))

# --- Consultas de rama ------------------------------------------------------
func _branch_ids() -> Array:
	if GameManager.specialization:
		return GameManager.specialization.BRANCHES.keys()
	return ["metal", "wood", "energy", "construction", "regulated"]

## Rama a la que pertenece un producto (por su firma) o "" si no encaja en ninguna.
func branch_of(item_id: String) -> String:
	if GameManager.specialization == null:
		return ""
	for b in GameManager.specialization.BRANCHES.keys():
		var sig: Array = GameManager.specialization.BRANCHES[b].get("signature", [])
		if sig.has(item_id):
			return String(b)
	return ""

func rivals_in(branch: String) -> Array:
	var out: Array = []
	for r in rivals:
		if branch == "" or String(r["branch"]) == branch:
			out.append(r)
	return out

func rival_capacity(branch: String) -> float:
	var t := 0.0
	for r in rivals_in(branch):
		t += float(r["capacity"])
	return t

## Capacidad de producción del jugador en una rama = suma de u/min instaladas de
## los productos insignia de esa rama. Representa tu "poder productivo".
func player_capacity(branch: String) -> float:
	if GameManager.production == null or GameManager.specialization == null:
		return 0.0
	var b := branch
	if b == "":
		b = GameManager.specialization.current()
	var sig: Array = GameManager.specialization.BRANCHES.get(b, {}).get("signature", [])
	var t := 0.0
	for p in sig:
		t += GameManager.production.capacity_for(String(p))
	return t

# --- Posición de mercado ----------------------------------------------------
## {branch, rank, total, share, player_cap, rival_cap} de la rama del jugador.
func market_position() -> Dictionary:
	var branch: String = GameManager.specialization.current() if GameManager.specialization else ""
	var others: Array = rivals_in(branch)
	var pcap: float = player_capacity(branch)
	var rank := 1
	for r in others:
		if float(r["capacity"]) > pcap:
			rank += 1
	var rcap: float = rival_capacity(branch)
	var total_cap: float = rcap + pcap
	var share: float = 0.0 if total_cap <= 0.0 else pcap / total_cap
	return {
		"branch": branch, "rank": rank, "total": others.size() + 1,
		"share": share, "player_cap": pcap, "rival_cap": rcap,
	}

## ¿Es el jugador el líder (rank 1) de su rama? (con capacidad real > 0).
func is_market_leader() -> bool:
	var mp := market_position()
	return int(mp["rank"]) == 1 and float(mp["player_cap"]) > 0.0

## Reputación de puja del mejor rival de una rama (para licitaciones).
func top_rival_reputation(branch: String) -> int:
	var best := 0
	for r in rivals_in(branch):
		best = maxi(best, int(r["reputation"]))
	return best

# --- Presión de precios (la usa MarketManager.sell) -------------------------
## Multiplicador del precio de venta según la competencia en la rama del ítem.
## Rivales dominantes bajan el precio; tu reputación lo sostiene. Rango [0.82, 1.08].
func sell_pressure_mult(item_id: String) -> float:
	var branch := branch_of(item_id)
	if branch == "":
		return 1.0
	var rcap: float = rival_capacity(branch)
	var pcap: float = player_capacity(branch)
	var competition: float = rcap / (rcap + pcap + 1.0)
	var rep_bonus: float = clampf(GameState.reputation / 100.0, 0.0, 1.0) * 0.12
	return clampf(1.0 - competition * 0.18 + rep_bonus, 0.82, 1.08)

# --- Jugadas de rival (las disparan eventos) --------------------------------
## Un rival de la rama crece de golpe (si el jugador no defiende su cuota).
func rival_gains_capacity(branch: String, factor: float = 1.06) -> void:
	var pool: Array = rivals_in(branch)
	if pool.is_empty():
		return
	var r = pool[randi() % pool.size()]
	r["capacity"] = float(r["capacity"]) * factor

## Un rival se retira de la región: mejora tu posición relativa.
func remove_random_rival(branch: String = "") -> String:
	var pool: Array = rivals_in(branch)
	if pool.is_empty():
		return ""
	var r = pool[randi() % pool.size()]
	rivals.erase(r)
	return String(r["name"])

## Un rival cualquiera (o de una rama) para redactar textos de evento.
func random_rival(branch: String = "") -> Dictionary:
	var pool: Array = rivals_in(branch)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]

# --- Serialización ----------------------------------------------------------
func to_dict() -> Dictionary:
	return { "rivals": rivals.duplicate(true) }

func from_dict(data: Dictionary) -> void:
	rivals = (data.get("rivals", []) as Array).duplicate(true)
