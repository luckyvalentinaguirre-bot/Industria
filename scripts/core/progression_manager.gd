extends Node
## ProgressionManager — nivel de empresa y desbloqueos (spec Fase 3 §2, §3).
##
## El nivel sube según métricas reales (valor de fábrica, máquinas, contratos) y
## desbloquea construcciones progresivamente, dando forma a los "capítulos".
## No inventa datos: lee la economía y la producción existentes.
##
## Nota de estructura: progresión global → vive en scripts/core/.

## Niveles industriales alcanzables DESDE CERO (spec §7). value = caja + capital
## invertido. Cada nivel desbloquea nuevas máquinas/edificios.
const LEVELS := [
	{ "name": "Taller", "value": 0, "machines": 0, "contracts": 0 },
	{ "name": "Pequeño productor", "value": 6000, "machines": 1, "contracts": 0 },
	{ "name": "Fabricante", "value": 20000, "machines": 3, "contracts": 2 },
	{ "name": "Industrial", "value": 60000, "machines": 8, "contracts": 8 },
	{ "name": "Complejo industrial", "value": 150000, "machines": 18, "contracts": 20 },
]

# Nivel de empresa mínimo para desbloquear cada construcción (capítulos). El
# banco de trabajo NO está listado → disponible desde el nivel 1 (etapa manual).
# La PRIMERA máquina industrial (fundición/prensa) se gana al alcanzar nivel 2.
const UNLOCK_LEVEL := {
	"small_storage": 1,
	"smelter": 2,
	"press": 2,
	"sawmill": 2,
	"planer": 2,
	"refinery": 2,
	"brick_kiln": 2,
	"block_press": 2,
	"grow_module": 2,
	"generator": 2,
	"splitter": 2,
	"merger": 2,
	"assembler": 3,
	"large_storage": 3,
	"substation": 3,
	"filter": 3,
	"workshop": 3,
}

func _ready() -> void:
	EventBus.day_passed.connect(func(_d): evaluate())
	EventBus.contract_completed.connect(func(_c): evaluate())
	EventBus.machine_placed.connect(func(_m): evaluate())
	EventBus.building_placed.connect(func(_b): evaluate())
	EventBus.money_changed.connect(func(_m): evaluate())
	EventBus.game_started.connect(_announce)
	EventBus.game_loaded.connect(_announce)

func _announce() -> void:
	EventBus.company_level_changed.emit(GameState.company_level, level_name())

func factory_value() -> float:
	var invested := 0.0
	if GameManager.machines:
		for m in GameManager.machines.machines:
			invested += float(m.def.get("cost", 0))
	if GameManager.buildings:
		for b in GameManager.buildings.buildings:
			invested += float(b.def.get("cost", 0))
	return GameState.money + invested

func level_name(level: int = -1) -> String:
	if level < 0:
		level = GameState.company_level
	var idx: int = clampi(level - 1, 0, LEVELS.size() - 1)
	return String(LEVELS[idx]["name"])

## Recalcula el nivel según las métricas y notifica si ascendió.
func evaluate() -> void:
	var machines: int = GameManager.machines.count() if GameManager.machines else 0
	var contracts: int = GameState.contracts_completed
	var value := factory_value()
	var new_level := 1
	for i in range(LEVELS.size()):
		var req: Dictionary = LEVELS[i]
		if value >= float(req["value"]) and machines >= int(req["machines"]) and contracts >= int(req["contracts"]):
			new_level = i + 1
	if new_level > GameState.company_level:
		var old := GameState.company_level
		GameState.company_level = new_level
		var bonus: float = new_level * 2500.0
		GameManager.economy.earn(bonus, "misc")
		EventBus.company_level_changed.emit(new_level, level_name())
		EventBus.notify.emit("¡Tu empresa ascendió a %s! (+%s)" % [level_name(), Fmt.money(bonus)], "success")

# --- Desbloqueos ------------------------------------------------------------
func required_level(id: String) -> int:
	return int(UNLOCK_LEVEL.get(id, 1))

func is_unlocked(id: String) -> bool:
	return GameState.company_level >= required_level(id)
