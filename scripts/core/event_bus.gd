extends Node
## EventBus — bus de señales global de Industria.
##
## Punto central de comunicación desacoplada entre sistemas. Ningún sistema
## debe conocer directamente a otro: emiten y escuchan señales aquí.
## Esto evita dependencias circulares y mantiene la arquitectura modular.
##
## Se irá ampliando por etapas. En la ETAPA 1 sólo existen las señales de
## mundo, cámara y tiempo. Las demás se agregarán en sus etapas.

# --- Núcleo / juego ---------------------------------------------------------
signal game_started()
signal game_paused(paused: bool)

# --- Tiempo -----------------------------------------------------------------
## Emitida cada vez que avanza un "tick" lógico del juego.
signal tick(delta: float)
## Emitida cuando cambia el minuto del reloj de juego.
signal minute_passed(day: int, hour: int, minute: int)
## Emitida cuando cambia la hora del reloj de juego.
signal hour_passed(day: int, hour: int)
## Emitida cuando pasa un día completo.
signal day_passed(day: int)
## Emitida cuando cambia la velocidad de simulación (0 = pausa).
signal time_scale_changed(scale: float)

# --- Mundo / cámara ---------------------------------------------------------
## Emitida cuando el mundo 3D terminó de construirse y está listo.
signal world_ready()
## Emitida cuando la cámara enfoca una nueva celda del grid.
signal camera_focus_changed(cell: Vector2i)
## Emitida cuando se muestra/oculta la cuadrícula de construcción.
signal grid_visibility_changed(visible: bool)

# --- Economía ---------------------------------------------------------------
signal money_changed(money: float)
signal debt_changed(debt: float)
signal transaction(category: String, amount: float, is_income: bool)
signal insufficient_funds(amount: float)
signal reputation_changed(reputation: int)

# --- Mercado / proveedores --------------------------------------------------
signal purchase_ordered(item_id: String, qty: int, cost: float, eta_day: int)
signal delivery_arrived(item_id: String, qty: int)

# --- Construcción -----------------------------------------------------------
signal build_mode_changed(active: bool, kind: String)
signal building_placed(building: Node)
signal building_removed(building: Node)

# --- Máquinas ---------------------------------------------------------------
signal machine_placed(machine: Node)
signal machine_removed(machine: Node)
signal machine_state_changed(machine: Node)
signal machine_selected(machine: Node)
signal recipe_changed(machine: Node)

# --- Producción -------------------------------------------------------------
signal item_produced(item_id: String, qty: int)

# --- Mantenimiento ----------------------------------------------------------
signal machine_breakdown(machine: Node)
signal machine_repaired(machine: Node)

# --- Energía ----------------------------------------------------------------
signal power_changed(consumption: float, capacity: float)
signal power_overload(is_overload: bool)

# --- Contratos --------------------------------------------------------------
signal contract_offered(contract: Resource)
signal contract_accepted(contract: Resource)
signal contract_completed(contract: Resource)
signal contract_failed(contract: Resource)

# --- Trabajadores -----------------------------------------------------------
signal worker_hired(worker: Node)
signal worker_fired(worker: Node)

# --- Automatización ---------------------------------------------------------
signal rule_added(rule: Dictionary)
signal rule_removed(rule_id: int)
signal rule_triggered(rule: Dictionary)

# --- Guardado ---------------------------------------------------------------
signal game_saved()
signal game_loaded()

# --- Objetivos / progresión -------------------------------------------------
signal objective_completed(id: String, title: String)
signal objectives_updated()
signal game_won()

# --- UI / notificaciones ----------------------------------------------------
## level: "info" | "success" | "warning" | "error"
signal notify(message: String, level: String)
