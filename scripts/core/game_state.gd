extends Node
## GameState — estado global persistente de la partida (autoload).
##
## Contiene únicamente DATOS, no lógica compleja. Los managers leen y escriben
## aquí; el SaveManager (ETAPA 8) serializará este estado.
##
## En la ETAPA 1 sólo se definen los campos base; se irán rellenando conforme
## avancen las etapas (economía, inventario, máquinas, etc.).

## Dimensiones de la fábrica inicial en celdas de grid (ancho x profundidad).
const START_GRID_SIZE := Vector2i(40, 40)
## Tamaño de una celda del grid en metros de mundo.
const CELL_SIZE := 2.0

# --- Identidad de la partida ------------------------------------------------
var company_name: String = "Industria S.A."
var save_version: int = 1

# --- Economía (se usa a partir de la ETAPA 5) -------------------------------
var money: float = 15000.0
var debt: float = 120000.0
var reputation: int = 50

# --- Progresión -------------------------------------------------------------
var company_level: int = 1
var contracts_completed: int = 0
var tutorial_active: bool = true
var tutorial_index: int = 0
var difficulty: int = 1   # 0 fácil, 1 normal, 2 difícil

## Reinicia el estado para una partida nueva, aplicando la dificultad elegida.
func reset_for_new_game(p_name: String, p_difficulty: int) -> void:
	company_name = p_name if p_name.strip_edges() != "" else "Industria S.A."
	difficulty = p_difficulty
	match p_difficulty:
		0: money = 25000.0; debt = 90000.0    # fácil
		2: money = 10000.0; debt = 150000.0   # difícil
		_: money = 15000.0; debt = 120000.0   # normal
	reputation = 50
	company_level = 1
	contracts_completed = 0
	tutorial_active = true
	tutorial_index = 0
	day = 1; hour = 8; minute = 0
	buildable_size = Vector2i(24, 24)

# --- Tiempo (gestionado por TimeManager) ------------------------------------
var day: int = 1
var hour: int = 8
var minute: int = 0

# --- Mundo ------------------------------------------------------------------
var grid_size: Vector2i = START_GRID_SIZE
var grid_visible: bool = true
## Terreno construible actual (subconjunto centrado del grid). Crece con la
## expansión (spec §18). Empieza pequeño y puede llegar hasta grid_size.
var buildable_size: Vector2i = Vector2i(24, 24)

## Devuelve el estado del juego como diccionario serializable.
## Cada etapa irá añadiendo sus claves. Base para SaveManager.
func to_dict() -> Dictionary:
	return {
		"save_version": save_version,
		"company_name": company_name,
		"money": money,
		"debt": debt,
		"reputation": reputation,
		"company_level": company_level,
		"contracts_completed": contracts_completed,
		"tutorial_active": tutorial_active,
		"tutorial_index": tutorial_index,
		"difficulty": difficulty,
		"day": day,
		"hour": hour,
		"minute": minute,
		"grid_size": [grid_size.x, grid_size.y],
		"buildable_size": [buildable_size.x, buildable_size.y],
	}

## Restaura el estado desde un diccionario (SaveManager, ETAPA 8).
func from_dict(data: Dictionary) -> void:
	save_version = int(data.get("save_version", save_version))
	company_name = String(data.get("company_name", company_name))
	money = float(data.get("money", money))
	debt = float(data.get("debt", debt))
	reputation = int(data.get("reputation", reputation))
	company_level = int(data.get("company_level", company_level))
	contracts_completed = int(data.get("contracts_completed", contracts_completed))
	tutorial_active = bool(data.get("tutorial_active", false))
	tutorial_index = int(data.get("tutorial_index", tutorial_index))
	difficulty = int(data.get("difficulty", difficulty))
	day = int(data.get("day", day))
	hour = int(data.get("hour", hour))
	minute = int(data.get("minute", minute))
	var gs: Variant = data.get("grid_size", null)
	if gs is Array and gs.size() == 2:
		grid_size = Vector2i(int(gs[0]), int(gs[1]))
	var bs: Variant = data.get("buildable_size", null)
	if bs is Array and bs.size() == 2:
		buildable_size = Vector2i(int(bs[0]), int(bs[1]))
