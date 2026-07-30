extends Node
## TimeManager — reloj de simulación de Industria (autoload).
##
## Convierte el tiempo real en tiempo de juego (días / horas / minutos) y emite
## señales de tick a través del EventBus. Todos los sistemas que dependen del
## paso del tiempo (producción, economía, mantenimiento...) se sincronizan aquí
## en lugar de usar su propio _process, evitando cálculos dispersos por frame.

## Minutos de juego que transcurren por cada segundo real a velocidad x1.
const GAME_MINUTES_PER_REAL_SECOND := 5.0
## Velocidades de simulación seleccionables.
const SPEED_STEPS: Array[float] = [0.0, 1.0, 2.0, 3.0]

var time_scale: float = 1.0
var _minute_accumulator: float = 0.0
var _running: bool = false

func _ready() -> void:
	# El reloj arranca cuando GameManager inicia la partida.
	set_process(false)

func start() -> void:
	_running = true
	set_process(true)

func stop() -> void:
	_running = false
	set_process(false)

func _process(delta: float) -> void:
	if not _running or time_scale <= 0.0:
		return

	EventBus.tick.emit(delta * time_scale)

	_minute_accumulator += delta * time_scale * GAME_MINUTES_PER_REAL_SECOND
	while _minute_accumulator >= 1.0:
		_minute_accumulator -= 1.0
		_advance_one_minute()

func _advance_one_minute() -> void:
	GameState.minute += 1
	if GameState.minute >= 60:
		GameState.minute = 0
		GameState.hour += 1
		EventBus.hour_passed.emit(GameState.day, GameState.hour)
		if GameState.hour >= 24:
			GameState.hour = 0
			GameState.day += 1
			EventBus.day_passed.emit(GameState.day)
	EventBus.minute_passed.emit(GameState.day, GameState.hour, GameState.minute)

## Fija la velocidad de simulación (0 = pausa). Emite señal.
func set_time_scale(scale: float) -> void:
	time_scale = max(0.0, scale)
	EventBus.time_scale_changed.emit(time_scale)

## Alterna entre pausa y la última velocidad activa.
func toggle_pause() -> void:
	if time_scale > 0.0:
		set_time_scale(0.0)
	else:
		set_time_scale(1.0)

## Devuelve el reloj formateado, p.ej. "Día 3 · 08:05".
func get_clock_string() -> String:
	return "Día %d · %02d:%02d" % [GameState.day, GameState.hour, GameState.minute]
