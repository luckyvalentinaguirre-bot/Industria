# Industria

Juego de **gestión empresarial + construcción de fábricas + producción + automatización progresiva**, completamente en 3D. Motor: **Godot 4.3**. Esta es la **VERSIÓN 1 / MVP**, en desarrollo incremental por etapas.

## Estado de desarrollo

| Etapa | Contenido | Estado |
|-------|-----------|--------|
| **1 — Base 3D** | Proyecto, mundo 3D, iluminación PBR, terreno, cámara estratégica (pan/rotación/zoom), grid de construcción | ✅ Completada |
| 2 — Construcción | Colocación, selección, rotación, eliminación, costos, primera máquina | ⏳ Pendiente |
| 3 — Producción | Recursos, inventario, recetas, máquina funcional, producción real | ⏳ Pendiente |
| 4 — Logística | Cintas, movimiento de materiales, almacén, E/S de máquinas | ⏳ Pendiente |
| 5 — Economía | Dinero, gastos, venta, contratos, deuda | ⏳ Pendiente |
| 6 — Mantenimiento | Durabilidad, reparación, averías, mecánico | ⏳ Pendiente |
| 7 — Automatización | Prioridades, sensores, reglas, producción automática | ⏳ Pendiente |
| 8 — UI y guardado | HUD, paneles, menú de construcción, panel de máquina, finanzas, save | ⏳ Pendiente |

## Cómo ejecutar

1. Abrir el proyecto con **Godot 4.3** (`project.godot`).
2. Ejecutar (F5). Escena principal: `scenes/main/main.tscn`.

## Controles de cámara (Etapa 1)

| Acción | Control |
|--------|---------|
| Desplazar (pan) | `W A S D` o bordes de pantalla |
| Pan por arrastre | Mantener **botón central** del ratón |
| Rotar | `Q` / `E` |
| Zoom | Rueda del ratón |
| Mostrar/ocultar cuadrícula | `G` |

## Arquitectura

Sistemas desacoplados que se comunican por señales a través del **EventBus** (`scripts/core/event_bus.gd`), evitando dependencias circulares.

Autoloads (orden en `project.godot`):

- `EventBus` — bus de señales global.
- `GameState` — datos persistentes de la partida (sin lógica).
- `TimeManager` — reloj de simulación (días/horas/minutos, ticks).
- `GameManager` — orquestador del ciclo de vida de la partida.

### Estructura de carpetas

Se respeta la estructura definida en la especificación. `assets/` (recursos 3D/2D), `audio/`, `data/` (JSON configurable), `scenes/` (`.tscn`), `scripts/` (lógica por sistema), `tests/`.

**Notas de estructura (adiciones dentro de carpetas existentes, sin alterar la organización):**

- `scripts/world/build_grid.gd` — cuadrícula lógica + visual de construcción.
- `scripts/world/camera_rig.gd` — cámara estratégica.

Ambos pertenecen al mundo/terreno y viven en `scripts/world/`.

### Datos V1 (`data/`)

Ya contienen el conjunto **controlado** de la V1: materias primas y materiales (`resources`), componentes y productos (`products`), recetas (`recipes`), máquinas (`machines`), economía y proveedores (`economy/prices`), contratos, trabajadores y edificios. Estos JSON alimentarán las etapas 2–5.

## Notas técnicas

- Renderizado **Forward+**, materiales PBR, SSAO, glow, tonemap ACES, sombras direccionales — con ajustes pensados para **gama media**.
- El terreno, la cuadrícula y los materiales se generan por código como **placeholders 3D**, preparados para sustituirse por los modelos definitivos del pipeline gráfico sin tocar la lógica.
