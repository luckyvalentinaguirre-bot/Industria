# Industria

Juego de **gestión empresarial + construcción de fábricas + producción + automatización progresiva**, completamente en 3D. Motor: **Godot 4.3**. Esta es la **VERSIÓN 1 / MVP**.

Recibes una fábrica deteriorada y endeudada, y debes ponerla a producir, cumplir contratos, reducir gastos, automatizar y volverla rentable.

## Estado de desarrollo — V1 completa

| Etapa | Contenido | Estado |
|-------|-----------|--------|
| **1 — Base 3D** | Proyecto, mundo 3D, iluminación PBR, terreno, cámara estratégica, grid | ✅ |
| **2 — Construcción** | Colocación con vista previa, selección, rotación, eliminación, costos, primera máquina | ✅ |
| **3 — Producción** | Recursos, inventario, recetas, máquinas funcionales, producción real | ✅ |
| **4 — Logística** | Cintas con ítems visibles, almacén, entrada/salida de máquinas | ✅ |
| **5 — Economía** | Dinero, gastos, ventas, proveedores, contratos, deuda e intereses | ✅ |
| **6 — Mantenimiento** | Durabilidad, desgaste, averías, reparación, mecánicos y talleres | ✅ |
| **7 — Automatización** | Prioridades, deslastre por energía, reglas SI→ENTONCES | ✅ |
| **8 — UI y guardado** | HUD, paneles (máquina, finanzas, contratos, personal, automatización), guardado | ✅ |
| **Pulido** | Objetivos/meta, condición de victoria, ayuda inicial | ✅ |
| **V2 (en curso)** | Logística de distribución (divisor/unificador/filtro) y expansión de terreno | ✅ |

Verificado con un test de integración headless (`tests/smoke_test.tscn`, **20/20 PASS**): producción, transporte por cinta, venta, sobrecarga eléctrica, contratos, logística de distribución, expansión de terreno, objetivos/victoria y guardado/carga.

### Logística de distribución (spec §9)

- **Divisor / Unificador:** nodos con buffer interno; varias cintas pueden converger (unificar) o salir (dividir) desde un mismo nodo.
- **Filtro:** relé que se auto-configura con el primer ítem que recibe y sólo deja pasar ese tipo.

### Expansión de terreno (spec §18)

El terreno construible empieza reducido (marco luminoso) y se amplía comprando expansiones desde el menú *Construcción → Expansión*. Más terreno permite más líneas, pero eleva los costos fijos (impuesto de terreno diario).

## Meta del juego

Una lista de **objetivos** guía la partida (panel 🎯 Objetivos): reparar la máquina, fabricar el primer producto, primera venta, cumplir un contrato, automatizar, cerrar un día con ganancias, reducir la deuda a la mitad y **saldarla por completo** (victoria). Al iniciar se muestra una ayuda con los primeros pasos.

## Cómo ejecutar

1. Abrir el proyecto con **Godot 4.3** (`project.godot`) y ejecutar (F5), o
2. Headless / test: `godot --headless res://tests/smoke_test.tscn`

## El bucle de juego

Reparar la fundición vieja → comprar materia prima a un proveedor → almacenarla →
construir cintas que la lleven a las máquinas → procesar y fabricar productos →
devolverlos al almacén → vender o cumplir contratos → ganar dinero → pagar
salarios, energía, mantenimiento y deuda → mejorar la línea → **automatizar** con
reglas y dejar la fábrica funcionando sola.

## Controles

| Acción | Control |
|--------|---------|
| Mover cámara | `W A S D` / bordes de pantalla / arrastrar botón central |
| Rotar cámara | `Q` / `E` |
| Zoom | Rueda del ratón |
| Mostrar/ocultar cuadrícula | `G` |
| Colocar construcción | Elegir en el menú *Construcción*, clic para colocar |
| Rotar pieza a colocar | `R` |
| Cancelar modo construcción | `Esc` |
| Conectar cinta | Herramienta *Cinta* → clic en origen, clic en destino |
| Inspeccionar máquina | *Seleccionar* → clic sobre la máquina |
| Velocidad / pausa | Botones ⏸ ▶ ▶▶ ▶▶▶ (barra superior) |

## Interfaz

- **HUD superior:** dinero, deuda, reputación, reloj (día/hora), energía (consumo/capacidad) y velocidad.
- **Menú de construcción (izquierda):** Producción, Logística, Energía, Mantenimiento + herramientas.
- **Panel de máquina:** estado, receta, prioridad, activación, condición, reparación, buffers de entrada/salida y consumo.
- **Barra inferior:** Finanzas, Contratos, Personal, Automatización, Guardar, Cargar.

## Arquitectura

Sistemas desacoplados que se comunican por señales a través del **EventBus**, evitando dependencias circulares. **GameManager** (autoload) instancia e interconecta todos los managers; **GameState** guarda los datos; **TimeManager** emite los ticks de simulación.

Managers por sistema: economía (`economy_manager`, `finance_manager`, `bank_manager`, `market_manager`), producción (`recipe_manager`, `production_manager`, `quality_manager`), máquinas (`machine_manager`, `maintenance_manager`), logística (`storage_manager`, `transport_manager`, `logistics_manager`), construcción (`building_manager`), contratos, trabajadores (`worker_manager`, `skill_manager`), automatización (`rule_manager`, `priority_manager`, `automation_manager`), energía (`power_manager`), eventos, guardado y UI.

### Estructura de carpetas

Se respeta la estructura de la especificación: `assets/`, `audio/`, `data/` (JSON configurable), `scenes/`, `scripts/` (lógica por sistema), `tests/`.

**Adiciones dentro de carpetas existentes (no alteran la organización):**

- `scripts/core/format_util.gd` — formato de dinero/cantidades.
- `scripts/core/objective_manager.gd` — objetivos y condición de victoria.
- `scripts/world/build_grid.gd`, `camera_rig.gd`, `build_controller.gd`, `power_manager.gd` — mundo/infraestructura.
- `scripts/logistics/conveyor.gd` — cinta transportadora.
- `scripts/ui/ui_theme.gd` — helpers de estilo de UI.

Los datos configurables de la V1 (recursos, productos, recetas, máquinas, edificios, economía/proveedores, contratos, trabajadores) viven en `data/` como JSON.

## Notas técnicas

- Renderizado **Forward+**, materiales PBR, SSAO, glow, tonemap ACES, sombras direccionales; ajustes para **gama media**.
- Objetos 3D generados por código como **placeholders**, preparados para sustituirse por los modelos definitivos del pipeline gráfico sin tocar la lógica.
- Optimización: cintas con paquetes de ítems reutilizados y limitados; simulación por ticks del EventBus en lugar de cálculos dispersos por frame.
