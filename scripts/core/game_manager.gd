extends Node
## GameManager — orquestador principal y contenedor de sistemas (autoload).
##
## Crea e interconecta todos los managers de la V1 y coordina el ciclo de vida
## (arranque, pausa, nueva partida). Los sistemas se comunican por EventBus; este
## nodo sólo los instancia y expone referencias, evitando dependencias circulares.

enum GamePhase { BOOT, PLAYING, PAUSED }

var phase: int = GamePhase.BOOT

# --- Referencias de mundo (las registra WorldManager) -----------------------
var world: Node3D = null
var grid: Node3D = null           # BuildGrid

# --- Managers ---------------------------------------------------------------
var economy: Node
var finance: Node
var bank: Node
var market: Node
var recipes: Node
var quality: Node
var storage: Node
var machines: Node
var maintenance: Node
var production: Node
var transport: Node
var logistics: Node
var buildings: Node
var contracts: Node
var workers: Node
var skills: Node
var power: Node
var priority: Node
var rules: Node
var automation: Node
var events: Node
var vehicles: Node
var progression: Node
var specialization: Node
var tutorial: Node
var objectives: Node
var upgrades: Node
var audio: Node
var save: Node
var ui: Node

func _ready() -> void:
	_create_managers()
	EventBus.world_ready.connect(_on_world_ready)

func _create_managers() -> void:
	# Orden: primero los que otros consultan en _ready diferido.
	recipes = _add("res://scripts/production/recipe_manager.gd", "RecipeManager")
	finance = _add("res://scripts/economy/finance_manager.gd", "FinanceManager")
	economy = _add("res://scripts/economy/economy_manager.gd", "EconomyManager")
	bank = _add("res://scripts/economy/bank_manager.gd", "BankManager")
	storage = _add("res://scripts/logistics/storage_manager.gd", "StorageManager")
	market = _add("res://scripts/economy/market_manager.gd", "MarketManager")
	quality = _add("res://scripts/production/quality_manager.gd", "QualityManager")
	machines = _add("res://scripts/machines/machine_manager.gd", "MachineManager")
	maintenance = _add("res://scripts/machines/maintenance_manager.gd", "MaintenanceManager")
	production = _add("res://scripts/production/production_manager.gd", "ProductionManager")
	transport = _add("res://scripts/logistics/transport_manager.gd", "TransportManager")
	logistics = _add("res://scripts/logistics/logistics_manager.gd", "LogisticsManager")
	buildings = _add("res://scripts/buildings/building_manager.gd", "BuildingManager")
	power = _add("res://scripts/world/power_manager.gd", "PowerManager")
	contracts = _add("res://scripts/contracts/contract_manager.gd", "ContractManager")
	workers = _add("res://scripts/workers/worker_manager.gd", "WorkerManager")
	skills = _add("res://scripts/workers/skill_manager.gd", "SkillManager")
	priority = _add("res://scripts/automation/priority_manager.gd", "PriorityManager")
	rules = _add("res://scripts/automation/rule_manager.gd", "RuleManager")
	automation = _add("res://scripts/automation/automation_manager.gd", "AutomationManager")
	events = _add("res://scripts/events/event_manager.gd", "EventManager")
	vehicles = _add("res://scripts/vehicles/vehicle_manager.gd", "VehicleManager")
	progression = _add("res://scripts/core/progression_manager.gd", "ProgressionManager")
	specialization = _add("res://scripts/core/specialization_manager.gd", "SpecializationManager")
	tutorial = _add("res://scripts/core/tutorial_manager.gd", "TutorialManager")
	objectives = _add("res://scripts/core/objective_manager.gd", "ObjectiveManager")
	upgrades = _add("res://scripts/core/upgrade_manager.gd", "UpgradeManager")
	audio = _add("res://scripts/core/audio_manager.gd", "AudioManager")
	save = _add("res://scripts/save/save_manager.gd", "SaveManager")
	ui = _add("res://scripts/ui/ui_manager.gd", "UIManager")

func _add(path: String, node_name: String) -> Node:
	var n: Node = load(path).new()
	n.name = node_name
	add_child(n)
	return n

# --- Registro del mundo -----------------------------------------------------
## Llamado por WorldManager cuando la escena 3D está lista, pasando contenedores.
func register_world(world_node: Node3D, grid_node: Node3D, containers: Dictionary) -> void:
	# Limpia colecciones de un mundo anterior (los nodos ya se liberaron al
	# cambiar de escena); evita referencias colgantes al iniciar/cargar partida.
	machines.machines.clear()
	buildings.buildings.clear()
	transport.conveyors.clear()
	workers.workers.clear()
	if "stock" in storage and storage.stock:
		storage.stock.clear()
	world = world_node
	grid = grid_node
	machines.set_container(containers.get("machines"))
	buildings.set_container(containers.get("buildings"))
	transport.set_container(containers.get("conveyors"))
	workers.set_container(containers.get("workers"))
	vehicles.set_container(containers.get("vehicles"))

func _on_world_ready() -> void:
	start_game()

# --- Flujo de partida (lo usa el menú principal) ----------------------------
var pending_load: bool = false
const FACTORY_SCENE := "res://scenes/main/main.tscn"

## Inicia una partida nueva con nombre y dificultad, y carga la fábrica.
func request_new_game(company_name: String, difficulty: int) -> void:
	GameState.reset_for_new_game(company_name, difficulty)
	pending_load = false
	get_tree().change_scene_to_file(FACTORY_SCENE)

## Continúa / carga el último guardado (una sola ranura en la V1).
func request_load_game() -> bool:
	if not save.has_save():
		return false
	pending_load = true
	get_tree().change_scene_to_file(FACTORY_SCENE)
	return true

# --- Ciclo de vida ----------------------------------------------------------
func start_game() -> void:
	phase = GamePhase.PLAYING
	TimeManager.start()
	EventBus.game_started.emit()

func pause_game() -> void:
	if phase != GamePhase.PLAYING:
		return
	phase = GamePhase.PAUSED
	TimeManager.set_time_scale(0.0)
	EventBus.game_paused.emit(true)

func resume_game() -> void:
	if phase != GamePhase.PAUSED:
		return
	phase = GamePhase.PLAYING
	TimeManager.set_time_scale(1.0)
	EventBus.game_paused.emit(false)

func toggle_pause() -> void:
	if phase == GamePhase.PAUSED:
		resume_game()
	elif phase == GamePhase.PLAYING:
		pause_game()
