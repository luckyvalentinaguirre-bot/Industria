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
