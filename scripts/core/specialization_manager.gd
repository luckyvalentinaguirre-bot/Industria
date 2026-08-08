extends Node
## SpecializationManager — ramas industriales (spec §8-§18).
##
## A partir del Nivel 2 el jugador elige una RAMA que da identidad a la partida:
## desbloquea máquinas propias, aplica un bonus de producción a sus máquinas y
## define su producto insignia (objetivos/contratos). No es una clase rígida
## (spec §16): las máquinas "generales" (metal básico) siguen disponibles para
## todos; sólo las máquinas EXCLUSIVAS de una rama requieren haberla elegido.
##
## La rama elegida se guarda en GameState.industry_branch (persistencia gratis).

## +25% de velocidad a las máquinas de tu rama (★★★★★ vs ★★ de otras).
const BONUS := 1.25

const BRANCHES := {
	"metal": {
		"name": "Metalurgia", "icon": "🪨",
		"tagline": "Producción pesada y maquinaria. Alto valor, mucho consumo.",
		"machines": ["smelter", "press", "assembler"],
		"signature": ["iron_ingot", "metal_plate", "metal_piece"],
	},
	"wood": {
		"name": "Madera", "icon": "🌲",
		"tagline": "Procesamiento y fabricación. Inicio barato, margen medio.",
		"machines": ["sawmill", "planer", "assembler"],
		"signature": ["plank", "pallet"],
	},
	"energy": {
		"name": "Energía", "icon": "🔋",
		"tagline": "Generación y refinado. Ingresos estables, gran inversión.",
		"machines": ["refinery", "generator", "substation"],
		"signature": ["fuel"],
	},
	"construction": {
		"name": "Construcción", "icon": "🏗",
		"tagline": "Materiales y estructuras. Contratos grandes y estables.",
		"machines": ["brick_kiln", "block_press", "assembler"],
		"signature": ["brick", "block"],
	},
	"regulated": {
		"name": "Cultivo regulado", "icon": "🌿",
		"tagline": "Alto beneficio y alto riesgo: mercado inestable, penalizaciones duras.",
		"machines": ["grow_module"],
		"signature": ["regulated_goods"],
	},
}

## Máquinas EXCLUSIVAS de una rama (requieren haberla elegido). El resto son
## generales: gobernadas sólo por el nivel de empresa.
const EXCLUSIVE := {
	"sawmill": "wood",
	"planer": "wood",
	"refinery": "energy",
	"brick_kiln": "construction",
	"block_press": "construction",
	"grow_module": "regulated",
}

func current() -> String:
	return GameState.industry_branch

func has_chosen() -> bool:
	return GameState.industry_branch != ""

func branch_name(id: String = "") -> String:
	if id == "":
		id = current()
	return String(BRANCHES.get(id, {}).get("name", "—"))

func branch_icon(id: String = "") -> String:
	if id == "":
		id = current()
	return String(BRANCHES.get(id, {}).get("icon", "🏭"))

## Fija la rama elegida (una vez). Devuelve true si se aplicó.
func choose(id: String) -> bool:
	if not BRANCHES.has(id) or has_chosen():
		return false
	GameState.industry_branch = id
	EventBus.branch_chosen.emit(id, branch_name(id))
	EventBus.notify.emit("Rama industrial elegida: %s %s" % [branch_icon(id), branch_name(id)], "success")
	return true

## Rama exclusiva de una máquina, o "" si es general.
func exclusive_branch(machine_id: String) -> String:
	return String(EXCLUSIVE.get(machine_id, ""))

## ¿La rama permite construir esta máquina? (independiente del nivel).
func is_machine_available(machine_id: String) -> bool:
	var ex := exclusive_branch(machine_id)
	if ex == "":
		return true
	return current() == ex

## Bonus de velocidad si la máquina pertenece a tu rama elegida.
func machine_bonus(machine_id: String) -> float:
	if not has_chosen():
		return 1.0
	var mns: Array = BRANCHES[current()].get("machines", [])
	return BONUS if mns.has(machine_id) else 1.0

## Productos insignia de la rama (para objetivos/contratos). Sin rama elegida,
## acepta los insignia de todas las ramas.
func signature_products() -> Array:
	if has_chosen():
		return BRANCHES[current()].get("signature", [])
	var all: Array = []
	for b in BRANCHES.values():
		for s in b.get("signature", []):
			all.append(s)
	return all
