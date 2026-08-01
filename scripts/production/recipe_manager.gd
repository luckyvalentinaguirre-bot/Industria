extends Node
## RecipeManager — carga y consulta de recetas y definiciones de máquina.
##
## Fuente de datos: data/recipes/recipes.json y data/machines/machines.json.
## Sólo lectura; alimenta a las máquinas (qué pueden fabricar) y a la UI.

var recipes: Dictionary = {}         # recipe_id -> data
var machine_defs: Dictionary = {}    # machine_id -> data

func _ready() -> void:
	recipes = _load("res://data/recipes/recipes.json").get("recipes", {})
	machine_defs = _load("res://data/machines/machines.json").get("machines", {})

func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("RecipeManager: falta %s" % path)
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

# --- Recetas ----------------------------------------------------------------
func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})

func recipe_inputs(recipe_id: String) -> Dictionary:
	return get_recipe(recipe_id).get("inputs", {})

func recipe_outputs(recipe_id: String) -> Dictionary:
	return get_recipe(recipe_id).get("outputs", {})

func recipe_time(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("time", 5.0))

func recipe_name(recipe_id: String) -> String:
	return String(get_recipe(recipe_id).get("name", recipe_id))

## Nivel de empresa mínimo para desbloquear la receta (1 = disponible de entrada).
func recipe_min_level(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("min_level", 1))

# --- Máquinas ---------------------------------------------------------------
func get_machine_def(machine_id: String) -> Dictionary:
	return machine_defs.get(machine_id, {})

func machine_recipes(machine_id: String) -> Array:
	return get_machine_def(machine_id).get("recipes", [])

func machine_name(machine_id: String) -> String:
	return String(get_machine_def(machine_id).get("name", machine_id))

func machine_ids() -> Array:
	return machine_defs.keys()
