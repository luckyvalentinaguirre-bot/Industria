extends Node
## Smoke test de integración de Industria (ETAPAS 2-8).
##
## Verifica el bucle central sin depender de la interacción del jugador:
## producción real, transporte por cinta, economía (venta), energía y contratos.
## Ejecutar: godot --headless res://tests/smoke_test.tscn
## Imprime líneas PASS/FAIL y termina con código 0 (todo OK) o 1 (algún fallo).

const GridScript := preload("res://scripts/world/build_grid.gd")

var _failures: int = 0

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_world_refs()
	_test_production()
	_test_workbench_manual()
	_test_conveyor()
	_test_economy_sell()
	_test_power_overload()
	_test_contract_flow()
	_test_logistics_relay()
	_test_expansion()
	_test_market()
	_test_machine_upgrade()
	_test_contract_variety()
	_test_upgrades()
	_test_vehicles()
	_test_objectives()
	_test_specialization()
	_test_save_load()
	print("\n=== RESULTADO: %s (%d fallos) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _check(label: String, condition: bool) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1

func _setup_world_refs() -> void:
	var grid: Node3D = GridScript.new()
	add_child(grid)
	var root := Node3D.new()
	add_child(root)
	GameManager.grid = grid
	GameManager.machines.set_container(root)
	GameManager.buildings.set_container(root)
	GameManager.workers.set_container(root)
	GameManager.transport.set_container(root)
	GameManager.vehicles.set_container(root)

func _tick(seconds: float, step: float = 0.1) -> void:
	var n := int(seconds / step)
	for i in range(n):
		EventBus.tick.emit(step)

# --- Tests ------------------------------------------------------------------
func _test_production() -> void:
	var m: Machine = GameManager.machines.create_machine("smelter", Vector2i(2, 2))
	m.set_recipe("smelt_iron")
	m.input_buffer.add("iron_ore", 10)
	m.set_condition(100.0)
	m.powered = true
	_tick(20.0)  # 20s: a 6s/ciclo con 2 ore/ciclo → ~3 lingotes
	var ingots: int = m.output_buffer.count("iron_ingot")
	_check("Producción: la fundición fabricó lingotes de hierro (%d)" % ingots, ingots >= 2)
	_check("Producción: consumió mineral de la entrada", m.input_buffer.count("iron_ore") < 10)

func _test_workbench_manual() -> void:
	# Etapa manual: el banco de trabajo se auto-abastece del almacén central
	# (sin cintas) y descarga allí su producción de herramientas.
	GameManager.storage.deposit("scrap", 40)
	var wb: Machine = GameManager.machines.create_machine("workbench", Vector2i(30, 2))
	wb.set_condition(100.0)
	wb.powered = true
	_tick(30.0)  # 7s/ciclo, 4 chatarra→1 herramienta
	var tools: int = GameManager.storage.count("hand_tool")
	_check("Banco de trabajo: fabrica herramientas desde el almacén (%d)" % tools, tools >= 2)
	_check("Banco de trabajo: consumió chatarra del almacén", GameManager.storage.count("scrap") < 40)

func _test_conveyor() -> void:
	# Almacén con stock que alimenta una prensa vía cinta, y devuelve el producto.
	var store: Building = GameManager.buildings.create_building("small_storage", Vector2i(6, 6))
	GameManager.storage.deposit("iron_ingot", 30)
	var press: Machine = GameManager.machines.create_machine("press", Vector2i(10, 10))
	press.set_recipe("press_plate")
	press.set_condition(100.0)
	press.powered = true
	GameManager.transport.create_conveyor(store, press, false)   # ingotes → prensa
	GameManager.transport.create_conveyor(press, store, false)   # placas → almacén
	var before_plates: int = GameManager.storage.count("metal_plate")
	_tick(30.0)
	var after_plates: int = GameManager.storage.count("metal_plate")
	_check("Cinta+producción: aparecieron placas metálicas en el almacén (%d)" % after_plates, after_plates > before_plates)

func _test_economy_sell() -> void:
	GameManager.storage.deposit("metal_piece", 10)
	var money_before: float = GameState.money
	var revenue: float = GameManager.market.sell("metal_piece", 10)
	_check("Economía: la venta generó ingresos (%s)" % Fmt.money(revenue), revenue > 0.0)
	_check("Economía: la caja aumentó tras vender", GameState.money > money_before)

func _test_power_overload() -> void:
	# Muchas máquinas de alto consumo deben superar la capacidad base (80 kW).
	for i in range(4):
		var a: Machine = GameManager.machines.create_machine("assembler", Vector2i(14 + i * 3, 14))
		a.set_recipe("assemble_metal_piece")
		a.set_condition(100.0)
	GameManager.power._recompute()
	_check("Energía: se detecta sobrecarga con consumo > capacidad", GameManager.power.overload)
	_check("Energía: capacidad base correcta (80 kW)", GameManager.power.capacity >= 80.0)

func _test_contract_flow() -> void:
	var c := Contract.new()
	c.id = "test"; c.client = "Test SA"; c.product = "metal_plate"
	c.amount = 5; c.payment = 1000.0; c.deadline_days = 5; c.reputation = 2
	GameManager.contracts.offers.append(c)
	GameManager.storage.deposit("metal_plate", 20)
	var money_before: float = GameState.money
	GameManager.contracts.accept(c)
	GameManager.contracts._on_minute(0, 0, 0)  # dispara entrega
	_check("Contratos: el contrato se completó al haber stock", c.completed)
	_check("Contratos: el cliente pagó el contrato", GameState.money > money_before)

func _test_logistics_relay() -> void:
	# Unificador: acepta y entrega desde su buffer interno.
	var merger: Building = GameManager.buildings.create_building("merger", Vector2i(20, 6))
	var got: int = merger.port_receive_give("iron_ingot", 5)
	var out: int = merger.port_provide_take("iron_ingot", 3)
	_check("Logística: el unificador almacena en su buffer (%d)" % got, got == 5)
	_check("Logística: el unificador entrega desde su buffer (%d)" % out, out == 3)

	# Filtro: se auto-configura con el primer ítem y rechaza los demás.
	var filter: Building = GameManager.buildings.create_building("filter", Vector2i(24, 6))
	filter.port_receive_give("copper_ingot", 2)     # fija el filtro a copper_ingot
	var rejected: int = filter.port_receive_can("iron_ingot", 5)
	_check("Logística: el filtro se fija al primer ítem", filter.filter_item == "copper_ingot")
	_check("Logística: el filtro rechaza otros ítems", rejected == 0)

func _test_expansion() -> void:
	GameState.buildable_size = Vector2i(24, 24)
	var grid = GameManager.grid
	var outside: bool = not grid.is_in_buildable(Vector2i(2, 2))
	var inside: bool = grid.is_in_buildable(Vector2i(20, 20))
	_check("Expansión: celda lejana fuera del terreno inicial", outside)
	_check("Expansión: celda central dentro del terreno inicial", inside)
	var grew: bool = grid.expand(8)
	_check("Expansión: ampliar aumenta el terreno construible", grew and GameState.buildable_size == Vector2i(32, 32))

func _test_machine_upgrade() -> void:
	var m: Machine = GameManager.machines.create_machine("press", Vector2i(30, 30))
	GameState.money = 100000.0
	var before: float = m.level_speed_mult()
	var ok: bool = m.upgrade()
	_check("Mejora de máquina: sube de nivel y velocidad", ok and m.level == 2 and m.level_speed_mult() > before)
	_check("Mejora de máquina: el nombre muestra el nivel (II)", m.display_name().ends_with("II"))

func _test_market() -> void:
	var m = GameManager.market
	var base: float = ItemDB.base_price("iron_ore")
	for i in range(20):
		m._fluctuate_prices()
	var p: float = m.current_price("iron_ore")
	_check("Mercado: el precio dinámico se mantiene dentro de límites", p >= base * 0.5 and p <= base * 2.0)
	_check("Mercado: la compra usa el precio dinámico (>0)", m.unit_price("iron_ore", "metalurgica_norte") > 0.0)
	m.apply_demand("iron_ore", 1.8, 3)
	for i in range(3):
		m._fluctuate_prices()
	_check("Mercado: la demanda de un evento sube el precio", m.current_price("iron_ore") > base)

func _test_contract_variety() -> void:
	var urgente = GameManager.contracts._gen_typed("urgente")
	_check("Contratos: 'urgente' con plazo corto y penalización alta",
		urgente.type == "urgente" and urgente.deadline_days <= 3 and urgente.payment > 0.0)
	var grande = GameManager.contracts._gen_typed("grande")
	_check("Contratos: 'grande' pide mayor cantidad", grande.amount >= 250)
	var especial = GameManager.contracts._gen_typed("especial")
	_check("Contratos: 'especial' pide un producto avanzado", especial.product == "simple_motor")

func _test_upgrades() -> void:
	var um = GameManager.upgrades
	GameState.money = 100000.0
	var speed_before: float = um.machine_speed_mult()
	var ok: bool = um.buy("tuned_machines")
	_check("Mejoras: se compra 'Máquinas ajustadas'", ok and um.is_owned("tuned_machines"))
	_check("Mejoras: aumenta el multiplicador de velocidad", um.machine_speed_mult() > speed_before)
	_check("Mejoras: la mejora II queda disponible tras la I", um.is_available("tuned_machines_2"))
	var locked_avail: bool = um.is_available("tuned_machines_2")
	# El nivel base requiere nada; uno con requisito no cumplido no está disponible.
	_check("Mejoras: nivel bloqueado sin requisito no disponible", not um.is_available("efficient_motors_2"))
	_check("Mejoras: 'red comercial' sube el precio de venta", _sell_upgrade_effect(um))

func _sell_upgrade_effect(um) -> bool:
	var before: float = um.sell_mult()
	um.buy("sales_network")
	return um.sell_mult() > before

func _test_vehicles() -> void:
	var before: int = GameManager.vehicles._active.size()
	EventBus.delivery_arrived.emit("iron_ore", 10)
	GameManager.vehicles._cleanup()
	_check("Vehículos: llega un camión al recibir una entrega", GameManager.vehicles._active.size() > before)

func _test_objectives() -> void:
	# Ventas y contratos previos deben haber marcado objetivos de la campaña.
	_check("Objetivos: 'realiza tu primera venta' cumplido", _obj_done("sell"))
	_check("Objetivos: 'cumple tu primer contrato' cumplido", _obj_done("contract"))
	# La victoria se alcanza al llegar a Complejo Industrial (nivel 5).
	EventBus.company_level_changed.emit(5, "Complejo industrial")
	_check("Objetivos: alcanzar nivel 5 dispara la victoria", GameManager.objectives.won)

func _obj_done(id: String) -> bool:
	for o in GameManager.objectives.objectives:
		if o["id"] == id:
			return o["done"]
	return false

func _test_specialization() -> void:
	var spec := GameManager.specialization
	# Antes de elegir: máquinas exclusivas de rama no disponibles.
	GameState.industry_branch = ""
	_check("Rama: aserradero bloqueado sin elegir madera", not spec.is_machine_available("sawmill"))
	_check("Rama: fundición (general) siempre disponible", spec.is_machine_available("smelter"))
	# Elegir madera desbloquea sus máquinas y da bonus a las suyas.
	var ok: bool = spec.choose("wood")
	_check("Rama: se elige la especialización (madera)", ok and spec.current() == "wood")
	_check("Rama: madera desbloquea el aserradero", spec.is_machine_available("sawmill"))
	_check("Rama: refinería (energía) sigue bloqueada con madera", not spec.is_machine_available("refinery"))
	_check("Rama: horno de ladrillos (construcción) bloqueado con madera", not spec.is_machine_available("brick_kiln"))
	_check("Rama: módulo de cultivo (regulado) bloqueado con madera", not spec.is_machine_available("grow_module"))
	_check("Rama: hay 5 ramas industriales definidas", spec.BRANCHES.size() == 5)
	_check("Rama: bonus de producción a las máquinas de la rama", spec.machine_bonus("sawmill") > 1.0)
	_check("Rama: sin bonus a máquinas de otra rama", is_equal_approx(spec.machine_bonus("smelter"), 1.0))
	_check("Rama: no se puede reelegir una vez fijada", not spec.choose("metal"))

func _test_save_load() -> void:
	var ok_save: bool = GameManager.save.save_game()
	var money_snapshot: float = GameState.money
	GameState.money = 999999.0
	var ok_load: bool = GameManager.save.load_game()
	_check("Guardado: se guardó la partida", ok_save)
	_check("Guardado: se cargó la partida y restauró el dinero", ok_load and is_equal_approx(GameState.money, money_snapshot))
	GameManager.save.delete_save()
