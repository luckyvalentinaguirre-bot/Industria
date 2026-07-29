extends Node
## GameManager — orquestador principal de Industria (autoload).
##
## Coordina el arranque de la partida y el ciclo de vida global (pausa, nueva
## partida, más adelante carga/guardado). No implementa la lógica de cada
## sistema: sólo los pone en marcha y media entre ellos vía EventBus.

enum GamePhase { BOOT, PLAYING, PAUSED }

var phase: int = GamePhase.BOOT

func _ready() -> void:
	# Se ejecuta después de que todos los autoloads existen.
	# El mundo llamará a start_game() cuando la escena principal esté lista,
	# para garantizar que el reloj no corra sin mundo.
	EventBus.world_ready.connect(_on_world_ready)

func _on_world_ready() -> void:
	start_game()

## Inicia (o reinicia) una partida nueva.
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
