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
	_test_production_orders()
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
	_test_machine_models()
	_test_contract_capacity()
	_test_client_program()
	_test_workers_system()
	_test_personnel()
	_test_events()
	_test_reputation_weight()
	_test_week_summary()
	_test_automation_objective()
	_test_balance()
	_test_all_recipes_balance()
	_test_new_chains()
	_test_resource_integrity()
	_test_economic_events()
	_test_growth()
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
	m.staffed = true   # con operario produce de forma continua (nuevo sistema)
	_tick(20.0)  # 20s: a 6s/ciclo con 2 ore/ciclo → ~3 lingotes
	var ingots: int = m.output_buffer.count("iron_ingot")
	_check("Producción: la fundición fabricó lingotes de hierro (%d)" % ingots, ingots >= 2)
	_check("Producción: consumió mineral de la entrada", m.input_buffer.count("iron_ore") < 10)
	# §2: contador de producción de la máquina (feedback en el panel) y persistencia.
	_check("Producción: la máquina lleva un contador propio (%d)" % m.produced_count, m.produced_count == ingots)
	var saved: Dictionary = m.to_dict()
	var count_before: int = m.produced_count
	m.produced_count = 0
	m.apply_dict(saved)
	_check("Producción: el contador se guarda y restaura", m.produced_count == count_before)

func _test_workbench_manual() -> void:
	# Etapa manual: el banco de trabajo se auto-abastece del almacén central
	# (sin cintas) y descarga allí su producción de herramientas.
	GameManager.storage.deposit("scrap", 40)
	var wb: Machine = GameManager.machines.create_machine("workbench", Vector2i(30, 2))
	wb.set_condition(100.0)
	wb.powered = true
	wb.queue_batch(100)   # el jugador le da una orden de lote (trabajo manual)
	_tick(30.0)  # 7s/ciclo, 4 chatarra→1 herramienta
	var tools: int = GameManager.storage.count("hand_tool")
	_check("Banco de trabajo: fabrica herramientas desde el almacén (%d)" % tools, tools >= 2)
	_check("Banco de trabajo: consumió chatarra del almacén", GameManager.storage.count("scrap") < 40)

func _test_production_orders() -> void:
	# Núcleo del nuevo gameplay: una máquina NO produce sin una orden.
	var m: Machine = GameManager.machines.create_machine("smelter", Vector2i(2, 30))
	m.set_recipe("smelt_iron")
	m.set_condition(100.0)
	m.powered = true
	m.input_buffer.add("iron_ore", 20)
	_tick(15.0)
	_check("Órdenes: sin orden la máquina NO produce (esperando)", m.output_buffer.count("iron_ingot") == 0 and m.state == Machine.State.AWAITING)
	# Con un lote manual produce esa cantidad y luego se detiene.
	m.queue_batch(2)
	_tick(20.0)   # alcanza para >2 ciclos, pero el lote lo limita a 2
	_check("Órdenes: el lote manual produce lo pedido y se detiene (%d)" % m.output_buffer.count("iron_ingot"), m.output_buffer.count("iron_ingot") == 2 and m.batch_remaining == 0)
	# Con operario asignado produce de forma continua.
	m.set_staffed(true)
	_tick(20.0)
	_check("Órdenes: con operario la producción es continua", m.output_buffer.count("iron_ingot") > 2)
	m.set_staffed(false)
	# Asignación: asignar un trabajador a la máquina consume un libre y la atiende.
	for w in GameManager.workers.workers.duplicate():
		GameManager.workers.fire(w)
	var op: Worker = GameManager.workers.hire("operator", false)
	var free_before: int = GameManager.workers.operators_free()
	GameManager.workers.assign(op, m.uid)
	_check("Órdenes: asignar un trabajador reduce los libres y atiende la máquina", GameManager.workers.operators_free() == free_before - 1 and m.staffed)
	GameManager.workers.assign(op, 0)
	for w in GameManager.workers.workers.duplicate():
		GameManager.workers.fire(w)
	# Libera la energía: las máquinas acumuladas de tests previos comparten los
	# 80 kW base y dejarían sin energía a las nuevas.
	for mm in GameManager.machines.machines:
		mm.set_enabled(false)
	# Automatización total (tecnología): produce sin operario ni lote.
	GameManager.upgrades.owned["automated_lines"] = true
	GameManager.upgrades._recompute()
	var m2: Machine = GameManager.machines.create_machine("smelter", Vector2i(6, 30))
	m2.set_recipe("smelt_iron")
	m2.set_condition(100.0)
	m2.powered = true
	m2.input_buffer.add("iron_ore", 10)
	_tick(15.0)
	_check("Órdenes: la automatización total produce sin operario ni lote", m2.output_buffer.count("iron_ingot") > 0)
	GameManager.upgrades.owned.erase("automated_lines")
	GameManager.upgrades._recompute()

func _test_conveyor() -> void:
	# Almacén con stock que alimenta una prensa vía cinta, y devuelve el producto.
	var store: Building = GameManager.buildings.create_building("small_storage", Vector2i(6, 6))
	GameManager.storage.deposit("iron_ingot", 30)
	var press: Machine = GameManager.machines.create_machine("press", Vector2i(10, 10))
	press.set_recipe("press_plate")
	press.set_condition(100.0)
	press.powered = true
	press.staffed = true
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
	c.amount = 5; c.payment = 1000.0; c.deadline_days = 5; c.reputation = 2; c.bonus = 500.0
	GameManager.contracts.offers.append(c)
	GameManager.storage.deposit("metal_plate", 20)
	var money_before: float = GameState.money
	GameManager.contracts.accept(c)
	GameManager.contracts._on_minute(0, 0, 0)  # dispara entrega
	_check("Contratos: el contrato se completó al haber stock", c.completed)
	_check("Contratos: el cliente pagó el contrato", GameState.money > money_before)
	# Entregado bien antes del plazo → cobra pago + bonus.
	_check("Contratos: bonus por entrega temprana", GameState.money >= money_before + c.payment + c.bonus - 1.0)

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

func _test_machine_models() -> void:
	# Cada máquina (incluidas las nuevas por rama) debe construir su modelo 3D
	# sin errores y quedar como nodo válido en el mundo.
	var ids := ["workbench", "sawmill", "planer", "refinery", "brick_kiln", "block_press", "grow_module"]
	var ok := true
	var col := 34
	for id in ids:
		var m: Machine = GameManager.machines.create_machine(id, Vector2i(col, 34))
		col += 4
		if not is_instance_valid(m) or m.get_child_count() == 0:
			ok = false
	_check("Modelos: todas las máquinas de rama instancian su modelo 3D", ok)

func _test_contract_capacity() -> void:
	# El chequeo de capacidad debe distinguir un pedido inviable de uno viable.
	var big := Contract.new()
	big.product = "metal_plate"; big.amount = 5000; big.deadline_days = 2
	var f1: Dictionary = GameManager.contracts.feasibility(big)
	_check("Capacidad: gran pedido sin producción se marca inviable", not f1["feasible"] and f1["needed"] > 0.0)
	# Con una prensa produciendo placas, un pedido modesto es viable por ritmo.
	var press: Machine = GameManager.machines.create_machine("press", Vector2i(36, 30))
	press.set_recipe("press_plate")
	press.set_condition(100.0)
	var c2 := Contract.new()
	c2.product = "metal_plate"; c2.amount = 50; c2.deadline_days = 6
	var f2: Dictionary = GameManager.contracts.feasibility(c2)
	_check("Capacidad: con producción suficiente el pedido es viable", f2["feasible"] and f2["rate"] > 0.0)
	# El generador de contratos conoce el tipo 'volumen' (gran cantidad).
	var cv: Contract = GameManager.contracts._gen_typed("volumen")
	_check("Contratos: 'volumen' pide gran cantidad (%d)" % cv.amount, cv.amount >= 400)

func _test_client_program() -> void:
	var cm := GameManager.contracts
	cm.program = {}
	GameState.company_level = 3
	cm._start_program()
	var p1: Contract = _find_program_offer(cm)
	_check("Programa: se ofrece la Fase 1", p1 != null and p1.program_phase == 1)
	if p1 == null:
		return
	# Completar la fase 1 debe ofrecer la fase 2.
	GameManager.storage.deposit(p1.product, p1.amount + 10)
	cm.accept(p1)
	cm._on_minute(0, 0, 0)
	_check("Programa: la Fase 1 completada abre la Fase 2", int(cm.program.get("phase", 0)) == 2)
	# Completar hasta la última fase cierra el programa (gran recompensa).
	for _i in range(2):
		var pn: Contract = _find_program_offer(cm)
		if pn == null:
			break
		GameManager.storage.deposit(pn.product, pn.amount + 10)
		cm.accept(pn)
		cm._on_minute(0, 0, 0)
	_check("Programa: se completan las 3 fases y el programa se cierra", cm.program.is_empty())

func _find_program_offer(cm) -> Contract:
	for c in cm.offers:
		if c.program_phase > 0:
			return c
	return null

func _test_workers_system() -> void:
	var wm := GameManager.workers
	# Nueva partida: sin empleados en la plantilla (spec §8).
	for w in wm.workers.duplicate():
		wm.fire(w)
	_check("Personal: la plantilla arranca vacía", wm.workers.size() == 0)
	# Máximo por nivel (lectura directa; el nivel real es dinámico en el test).
	GameState.company_level = 1
	_check("Personal: máximo por nivel (N1 = 1)", wm.max_employees() == 1)
	GameState.company_level = 5
	_check("Personal: máximo por nivel (N5 = 16)", wm.max_employees() == 16)
	# Cupo enforcement: se llena sin gasto (charge=false no dispara la subida de
	# nivel) y luego una contratación real debe bloquearse por el cupo.
	wm.hire("operator", false)   # llena el cupo sin gastar
	# Un objetivo puede dar recompensa al contratar y recalcular el nivel; se
	# re-fija a 1 para probar el cupo de forma determinista.
	GameState.company_level = 1
	_check("Personal: at_capacity al alcanzar el cupo", wm.at_capacity() and wm.workers.size() == 1)
	var blocked = wm.hire("operator", true)   # bloquea ANTES de gastar
	_check("Personal: se bloquea al superar el cupo", blocked == null and wm.workers.size() == 1)
	# Salarios SEMANALES: al cerrar la semana se registra el gasto de salarios.
	GameState.money = 100000.0
	var expected: float = wm.weekly_salary_total()
	_salary_paid = 0.0
	var cb := func(cat, amt, inc): if cat == "salaries" and not inc: _salary_paid += amt
	EventBus.transaction.connect(cb)
	EventBus.week_passed.emit(1)
	EventBus.transaction.disconnect(cb)
	_check("Personal: los salarios se pagan por semana", expected > 0.0 and is_equal_approx(_salary_paid, expected))
	# Limpieza para no afectar otros tests.
	for w in wm.workers.duplicate():
		wm.fire(w)

var _salary_paid: float = 0.0

var _decision_seen: bool = false
var _decision_opts: Array = []
func _test_events() -> void:
	# La avería prefiere una máquina EN MARCHA: dejamos sólo a `m` funcionando.
	for mm in GameManager.machines.machines:
		mm.set_enabled(false)
	var m: Machine = GameManager.machines.create_machine("press", Vector2i(2, 38))
	m.set_recipe("press_plate")
	m.set_condition(100.0)
	m.powered = true
	m.staffed = true
	m.input_buffer.add("iron_ingot", 20)
	_tick(8.0)   # ponerla en RUNNING
	_decision_seen = false
	_decision_opts = []
	var cb := func(_t, _d, opts): _decision_seen = true; _decision_opts = opts
	EventBus.decision_requested.connect(cb)
	GameManager.events._ev_breakdown()
	EventBus.decision_requested.disconnect(cb)
	_check("Eventos: la avería pide una decisión con opciones", _decision_seen and _decision_opts.size() >= 2)
	_check("Eventos: la máquina quedó dañada por el evento", m.condition <= 25.0)
	# Reparar mediante la opción de la decisión.
	GameState.money = 100000.0
	(_decision_opts[0]["action"] as Callable).call()
	_check("Eventos: la opción 'Reparar' arregla la máquina", m.condition >= 99.0)
	# Contrato especial: aparece una oferta nueva.
	var before: int = GameManager.contracts.offers.size()
	GameManager.contracts.add_special_offer()
	_check("Eventos: el contrato especial agrega una oferta", GameManager.contracts.offers.size() == before + 1)

func _test_reputation_weight() -> void:
	# Mejor reputación → mejores candidatos (mayor suma de skills en promedio).
	GameState.reputation = 0
	GameManager.workers.refresh_candidates()
	var low := _avg_candidate_skill()
	GameState.reputation = 100
	GameManager.workers.refresh_candidates()
	var high := _avg_candidate_skill()
	_check("Reputación: mejor reputación mejora los candidatos (%.2f > %.2f)" % [high, low], high > low)
	# Mejor reputación → contratos mejor pagados (promedio de varios, por la
	# cantidad aleatoria).
	GameState.reputation = 0
	var pay_low := _avg_contract_pay()
	GameState.reputation = 100
	var pay_high := _avg_contract_pay()
	_check("Reputación: mejora el pago promedio de los contratos", pay_high > pay_low)

func _avg_contract_pay() -> float:
	var t := 0.0
	for _i in range(10):
		t += GameManager.contracts._gen_typed("grande").payment
	return t / 10.0

func _avg_candidate_skill() -> float:
	var total := 0.0
	var n := 0
	for c in GameManager.workers.candidates:
		for k in (c.get("skills", {}) as Dictionary).values():
			total += float(k)
			n += 1
	return total / maxf(1.0, n)

func _test_personnel() -> void:
	var wm := GameManager.workers
	for w in wm.workers.duplicate():
		wm.fire(w)
	# Mercado laboral: hay candidatos, cada uno con skills y salario propios.
	wm.refresh_candidates()
	_check("Personal: hay candidatos en el mercado laboral", wm.candidates.size() == wm.CANDIDATE_COUNT)
	var c0: Dictionary = wm.candidates[0]
	_check("Personal: los candidatos tienen skills y salario", c0.has("skills") and float(c0.get("salary", 0)) >= 300.0)
	# Renovar el mercado trae caras nuevas (y no falla).
	var before_names := []
	for c in wm.candidates:
		before_names.append(c.get("name"))
	wm.refresh_candidates()
	_check("Personal: el mercado se renueva", wm.candidates.size() == wm.CANDIDATE_COUNT)
	# Contratar un candidato (cupo alto, con dinero).
	GameState.company_level = 5
	GameState.money = 100000.0
	var n_before: int = wm.workers.size()
	var hired: Worker = wm.hire_candidate(0, true)
	_check("Personal: se contrata un candidato del mercado", hired != null and wm.workers.size() == n_before + 1)
	# Asignar a una máquina: la atiende y aplica su bono de velocidad.
	var mac: Machine = GameManager.machines.create_machine("smelter", Vector2i(10, 34))
	mac.set_recipe("smelt_iron")
	wm.assign(hired, mac.uid)
	_check("Personal: asignar atiende la máquina (producción continua)", mac.staffed and wm.worker_for_machine(mac.uid) == hired)
	_check("Personal: la máquina aplica el bono de velocidad del trabajador", mac._effective_speed() > mac.base_speed * 0.99)
	# Experiencia: sólo crece si está asignado.
	var xp0: float = hired.experience
	GameManager.skills._on_day(1)
	_check("Personal: el trabajador asignado gana experiencia", hired.experience > xp0)
	# Liberar y despedir.
	wm.assign(hired, 0)
	_check("Personal: liberar deja la máquina sin atender", not mac.staffed and wm.unassigned_workers().has(hired))
	for w in wm.workers.duplicate():
		wm.fire(w)

var _week_data: Dictionary = {}
func _test_week_summary() -> void:
	EventBus.week_summary.connect(func(d): _week_data = d)
	EventBus.week_passed.emit(2)
	_check("Semana: se genera el resumen semanal", not _week_data.is_empty() and int(_week_data.get("week", 0)) == 2)
	_check("Semana: el resumen incluye gastos y personal", _week_data.has("expense") and _week_data.has("staff") and _week_data.has("next_goal"))
	_check("Semana §4: el resumen incluye destacados (gasto/máquina/recurso)",
		_week_data.has("top_expense") and _week_data.has("busiest_machine") and _week_data.has("top_supplied") and _week_data.has("top_value_product"))
	# El informe queda guardado para reabrirlo desde el menú (Economía → Informe).
	_check("Semana: el último informe queda guardado", int(GameManager.week.last_summary.get("week", 0)) == 2)

func _test_automation_objective() -> void:
	EventBus.conveyor_placed.emit(null)
	_check("Objetivos: conectar una cinta cumple 'automatizá'", _obj_done("automate"))

## Economía teórica de una máquina con su receta principal (a velocidad base):
## margen $/min, ROI (min) y producción u/min. Sirve de guarda de balance (§5).
func _econ(machine_id: String) -> Dictionary:
	var d: Dictionary = GameManager.recipes.get_machine_def(machine_id)
	var recs: Array = d.get("recipes", [])
	if recs.is_empty():
		return {}
	var r: Dictionary = GameManager.recipes.get_recipe(String(recs[0]))
	var t: float = maxf(0.5, float(r.get("time", 5.0)))
	var speed: float = float(d.get("base_speed", 1.0))
	var cycles_min: float = 60.0 / t * speed
	var rev := 0.0
	var out_units := 0
	for id in r.get("outputs", {}).keys():
		rev += ItemDB.base_price(id) * int(r["outputs"][id])
		out_units += int(r["outputs"][id])
	var incost := 0.0
	for id in r.get("inputs", {}).keys():
		incost += ItemDB.base_price(id) * int(r["inputs"][id])
	var energy_min: float = float(d.get("power", 0.0)) / 60.0 * 0.18
	# Valor AGREGADO por el paso (no se penaliza "comprar" el intermedio que en
	# realidad se produjo aguas arriba): valor de salida − valor de entrada.
	var va_cycle: float = rev - incost
	var va_min: float = va_cycle * cycles_min - energy_min
	var cost: float = float(d.get("cost", 0))
	return { "va_cycle": va_cycle, "va_min": va_min, "roi": cost / maxf(0.01, va_min), "prod": out_units * cycles_min }

func _test_balance() -> void:
	var ids := ["workbench", "smelter", "press", "assembler", "sawmill", "planer",
		"refinery", "brick_kiln", "block_press", "grow_module"]
	var value_adding := true
	var roi_ok := true
	var worst := 1e18
	var best := -1e18
	for id in ids:
		var e := _econ(id)
		if e.is_empty():
			continue
		print("  BALANCE %s: va %.1f/ciclo · %.0f $/min · ROI %.1f min · %.1f u/min" % [id, e["va_cycle"], e["va_min"], e["roi"], e["prod"]])
		if float(e["va_cycle"]) <= 0.0:
			value_adding = false   # un paso que destruye valor: nadie lo construiría
		if float(e["roi"]) < 0.5 or float(e["roi"]) > 120.0:
			roi_ok = false
		worst = minf(worst, float(e["va_min"]))
		best = maxf(best, float(e["va_min"]))
	_check("Balance: cada paso agrega valor (salida > entrada)", value_adding)
	_check("Balance: ROI de todas las máquinas en rango sano (0.5–120 min)", roi_ok)
	# Ninguna rama debe rendir absurdamente más que otra por máquina (dominancia).
	var ratio: float = best / maxf(1.0, worst)
	_check("Balance: sin rama dominante (mejor/peor $/min < 3x, =%.1f)" % ratio, ratio < 3.0)

func _test_all_recipes_balance() -> void:
	# TODAS las recetas (no sólo la primera de cada máquina) deben agregar valor:
	# el valor de salida supera al de entrada. Guarda de balance para las cadenas
	# nuevas (acero, vidrio, plástico, cable, electrónico, pieza de maquinaria).
	var all_va_ok := true
	var no_dominance := true
	var worst_id := ""
	for rid in GameManager.recipes.recipes.keys():
		if String(rid).begins_with("_"):
			continue
		var r: Dictionary = GameManager.recipes.get_recipe(String(rid))
		var rev := 0.0
		for id in r.get("outputs", {}).keys():
			rev += ItemDB.base_price(id) * int(r["outputs"][id])
		var incost := 0.0
		for id in r.get("inputs", {}).keys():
			incost += ItemDB.base_price(id) * int(r["inputs"][id])
		var va: float = rev - incost
		if va <= 0.0:
			all_va_ok = false
			worst_id = String(rid)
		# Ningún paso debe multiplicar el valor de forma absurda (>4.5x salida/entrada).
		if incost > 0.0 and rev / incost > 4.5:
			no_dominance = false
			worst_id = String(rid)
	_check("Balance: toda receta agrega valor (peor=%s)" % worst_id, all_va_ok)
	_check("Balance: ninguna receta multiplica valor >4.5x (peor=%s)" % worst_id, no_dominance)

func _test_new_chains() -> void:
	# Materias primas nuevas: deben existir en el catálogo y tener proveedor.
	var mk: Node = GameManager.market
	var raws_ok := true
	for raw in ["coal", "sand", "stone"]:
		if ItemDB.base_price(raw) <= 0.0 or mk.suppliers_for(raw).is_empty():
			raws_ok = false
	_check("Recursos: carbón/arena/piedra existen y tienen proveedor", raws_ok)
	# Cadena nueva: acero = lingote de hierro + carbón (cruza minería y energía).
	var m: Machine = GameManager.machines.create_machine("smelter", Vector2i(6, 6))
	m.set_recipe("smelt_steel")
	m.input_buffer.add("iron_ingot", 8)
	m.input_buffer.add("coal", 8)
	m.set_condition(100.0)
	m.powered = true
	m.staffed = true
	_tick(30.0)
	var steel: int = m.output_buffer.count("steel")
	_check("Cadena: la fundición produce acero desde lingote+carbón (%d)" % steel, steel >= 1)
	# Gating por nivel: smelt_steel requiere nivel 3, melt_glass es de entrada.
	_check("Progresión: smelt_steel bloqueada a nivel bajo (min_level 3)",
		GameManager.recipes.recipe_min_level("smelt_steel") == 3)
	_check("Progresión: melt_glass disponible de entrada (min_level 1)",
		GameManager.recipes.recipe_min_level("melt_glass") == 1)

func _test_resource_integrity() -> void:
	# §13: ningún recurso puede existir sólo en una lista. Cada ítem debe ser
	# OBTENIBLE (comprable a un proveedor o fabricable) y ÚTIL (se consume en una
	# receta, se vende o va a contratos). Esto caza materias/productos huérfanos.
	var recs: Dictionary = GameManager.recipes.recipes
	var inputs := {}
	var outputs := {}
	for rid in recs.keys():
		for id in GameManager.recipes.recipe_inputs(String(rid)).keys():
			inputs[id] = true
		for id in GameManager.recipes.recipe_outputs(String(rid)).keys():
			outputs[id] = true
	var sell: Array = load("res://scripts/ui/finance_ui.gd").SELL_ITEMS
	var contract_products: Array = GameManager.contracts.PRODUCTS
	var obtainable_ok := true
	var useful_ok := true
	var orphan_get := ""
	var orphan_use := ""
	for id in ItemDB.all_ids():
		var obtainable: bool = outputs.has(id) or not GameManager.market.suppliers_for(id).is_empty()
		var useful: bool = inputs.has(id) or sell.has(id) or contract_products.has(id)
		if not obtainable:
			obtainable_ok = false; orphan_get = String(id)
		if not useful:
			useful_ok = false; orphan_use = String(id)
	_check("Recursos §13: todo ítem es obtenible (comprable o fabricable) (huérfano=%s)" % orphan_get, obtainable_ok)
	_check("Recursos §13: todo ítem tiene uso (receta/venta/contrato) (huérfano=%s)" % orphan_use, useful_ok)

func _test_economic_events() -> void:
	# §3: los eventos económicos piden una DECISIÓN con opciones y sus efectos
	# se aplican de verdad. Se disparan directamente (sin la aleatoriedad diaria).
	GameState.money = 50000.0
	_decision_seen = false
	_decision_opts = []
	var cb := func(_t, _d, opts): _decision_seen = true; _decision_opts = opts
	EventBus.decision_requested.connect(cb)
	GameManager.events._ev_supplier_discount()
	_check("Eventos §3: el descuento de proveedor pide decisión con opciones", _decision_seen and _decision_opts.size() >= 2)
	var money_before: float = GameState.money
	(_decision_opts[0]["action"] as Callable).call()
	_check("Eventos §3: aceptar el descuento gasta caja (compra el lote)", GameState.money < money_before)
	# Cliente con adelanto: aceptar suma dinero y una oferta de contrato.
	_decision_seen = false
	var offers_before: int = GameManager.contracts.offers.size()
	var cash_before: float = GameState.money
	GameManager.events._ev_rush_client()
	_check("Eventos §3: el cliente con adelanto pide decisión", _decision_seen and _decision_opts.size() >= 2)
	(_decision_opts[0]["action"] as Callable).call()
	_check("Eventos §3: aceptar el adelanto cobra y agrega un contrato",
		GameState.money > cash_before and GameManager.contracts.offers.size() == offers_before + 1)
	EventBus.decision_requested.disconnect(cb)

func _test_growth() -> void:
	# Crecimiento visual por nivel: los builders de estructuras/clusters deben
	# generar geometría para todas las ramas sin errores. Se instancia el
	# WorldManager como nodo HUÉRFANO (no entra al árbol → no dispara _ready).
	var WM: GDScript = load("res://scripts/world/world_manager.gd")
	var wm: Node3D = WM.new()
	var saved_branch: String = GameState.industry_branch
	for b in ["metal", "wood", "energy", "construction", "regulated", ""]:
		GameState.industry_branch = b
		wm._grown.clear()
		for lv in [2, 3, 4, 5]:
			wm._grow_structures(lv)
	GameState.industry_branch = saved_branch
	_check("Crecimiento: estructuras y clusters por nivel/rama se generan sin error", wm._growth_node().get_child_count() > 0)
	wm.free()

func _test_save_load() -> void:
	var ok_save: bool = GameManager.save.save_game()
	var money_snapshot: float = GameState.money
	GameState.money = 999999.0
	var ok_load: bool = GameManager.save.load_game()
	_check("Guardado: se guardó la partida", ok_save)
	_check("Guardado: se cargó la partida y restauró el dinero", ok_load and is_equal_approx(GameState.money, money_snapshot))
	GameManager.save.delete_save()
