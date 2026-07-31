extends Node
## AudioManager — sonido del juego (spec §4 audio).
##
## Reproduce el ambiente de fábrica en bucle, un zumbido de máquinas cuyo volumen
## escala con las máquinas en marcha, y efectos por eventos (venta, entrega,
## contrato, error, colocación). Los .wav son placeholders sintetizados en
## audio/, sustituibles por sonido final. Si falta un archivo, se ignora sin fallar.
##
## Nota de estructura: servicio global → vive en scripts/core/; los assets en audio/.

const AMBIENCE := "res://audio/ambience/factory_ambience.wav"
const MACHINE := "res://audio/machines/machine_loop.wav"
const SFX := {
	"cash": "res://audio/sfx/cash.wav",
	"success": "res://audio/sfx/success.wav",
	"alert": "res://audio/sfx/alert.wav",
	"thud": "res://audio/sfx/thud.wav",
	"confirm": "res://audio/ui/confirm.wav",
	"click": "res://audio/ui/click.wav",
}

var _ambient: AudioStreamPlayer
var _machine: AudioStreamPlayer
var _sfx_pool: Array = []
var _sfx_idx: int = 0
var _sfx_streams: Dictionary = {}

func _ready() -> void:
	_ambient = _make_player(-14.0)
	_machine = _make_player(-80.0)
	for i in range(5):
		_sfx_pool.append(_make_player(-6.0))
	_load_streams()
	_start_loops()
	_connect_signals()

func _make_player(vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = vol_db
	add_child(p)
	return p

func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: Resource = load(path)
	return s as AudioStream

func _load_streams() -> void:
	for key in SFX.keys():
		var s := _load_stream(SFX[key])
		if s:
			_sfx_streams[key] = s

func _start_loops() -> void:
	var amb := _load_stream(AMBIENCE)
	if amb:
		_ambient.stream = amb
		_ambient.finished.connect(_ambient.play)   # bucle manual
		_ambient.play()
	var mac := _load_stream(MACHINE)
	if mac:
		_machine.stream = mac
		_machine.finished.connect(_machine.play)
		_machine.play()

func _connect_signals() -> void:
	EventBus.transaction.connect(_on_transaction)
	EventBus.contract_completed.connect(func(_c): play("success"))
	EventBus.delivery_arrived.connect(func(_i, _q): play("confirm"))
	EventBus.machine_placed.connect(func(_m): play("thud"))
	EventBus.building_placed.connect(func(_b): play("thud"))
	# Hitos de progresión: refuerzo sonoro discreto (spec §16/§17).
	EventBus.company_level_changed.connect(func(l, _n): if l >= 2: play("success"))
	EventBus.branch_chosen.connect(func(_i, _n): play("success"))
	EventBus.objective_completed.connect(func(_i, _t): play("confirm"))
	EventBus.factory_expanded.connect(func(_s): play("confirm"))
	EventBus.notify.connect(_on_notify)
	EventBus.minute_passed.connect(_on_minute)

func _on_transaction(category: String, _amount: float, is_income: bool) -> void:
	if is_income and category == "sales":
		play("cash")

func _on_notify(_msg: String, level: String) -> void:
	if level == "error":
		play("alert")

func _on_minute(_d: int, _h: int, _m: int) -> void:
	# Volumen del zumbido según máquinas en marcha (silencio si no hay ninguna).
	if not GameManager.machines:
		return
	var running := 0
	for m in GameManager.machines.machines:
		if m.state == Machine.State.RUNNING:
			running += 1
	if running <= 0:
		_machine.volume_db = -80.0
	else:
		_machine.volume_db = clampf(-24.0 + running * 2.5, -24.0, -8.0)

## Reproduce un efecto por su clave (round-robin en el pool).
func play(key: String) -> void:
	if not _sfx_streams.has(key):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = _sfx_streams[key]
	p.play()
