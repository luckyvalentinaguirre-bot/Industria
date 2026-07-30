extends Control
## MainMenu — pantalla de inicio de Industria (intro + menú principal).
##
## Es la escena principal del juego (project.godot). Reutiliza GameManager/
## SaveManager existentes: Nueva partida → request_new_game; Continuar/Cargar →
## request_load_game. Fondo 2D barato (siluetas industriales), sin coste 3D.

var _root: Control
var _panel_slot: Control   # contenedor donde se intercambian intro/menu/formularios

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_panel_slot = Control.new()
	_panel_slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_slot)
	_show_intro()

# --- Fondo industrial estilizado (2D, muy barato) ---------------------------
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.11)
	add_child(bg)
	# Cielo tenue arriba.
	var sky := ColorRect.new()
	sky.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sky.offset_bottom = 380
	sky.color = Color(0.13, 0.16, 0.22)
	add_child(sky)
	# Siluetas de chimeneas/silos (rectángulos oscuros a distintas alturas).
	var sil := Color(0.05, 0.06, 0.08)
	var heights := [220, 320, 180, 400, 260, 340, 200, 300, 240]
	var vp := get_viewport_rect().size
	var n := heights.size()
	for i in range(n):
		var r := ColorRect.new()
		var w: float = vp.x / float(n)
		r.color = sil
		r.position = Vector2(i * w, 420 - heights[i])
		r.size = Vector2(w * 0.7, heights[i])
		add_child(r)
	# Suelo.
	var ground := ColorRect.new()
	ground.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ground.offset_top = -220
	ground.color = Color(0.06, 0.06, 0.07)
	add_child(ground)

func _clear_slot() -> void:
	for c in _panel_slot.get_children():
		c.queue_free()

func _center_panel(min_w: float, min_h: float) -> VBoxContainer:
	_clear_slot()
	var p := UITheme.make_panel(UITheme.BG)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -min_w * 0.5
	p.offset_right = min_w * 0.5
	p.offset_top = -min_h * 0.5
	p.offset_bottom = min_h * 0.5
	_panel_slot.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return v

# --- Introducción -----------------------------------------------------------
func _show_intro() -> void:
	var v := _center_panel(600, 320)
	v.add_child(UITheme.make_title("INDUSTRIA"))
	var lines := [
		"Conseguiste un terreno vacío y un pequeño capital.",
		"Empezás desde cero: un banco de trabajo y tus primeras ventas.",
		"Tu objetivo: convertir ese taller en el mayor complejo industrial de la región.",
	]
	for t in lines:
		var l := UITheme.make_label(t, 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(540, 0)
		v.add_child(l)
	var b := UITheme.make_button("Continuar")
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(_show_menu)
	v.add_child(b)

# --- Menú principal ---------------------------------------------------------
func _show_menu() -> void:
	var v := _center_panel(440, 520)
	var title := UITheme.make_label("INDUSTRIA", 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var tag := UITheme.make_label("CONSTRUYE. PRODUCE. PROGRESA.", 13, UITheme.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	v.add_child(UITheme.hsep())

	var info: Dictionary = GameManager.save.get_save_info()
	var has_save: bool = not info.is_empty()
	# CONTINUAR: destacado si hay partida; deshabilitado si no.
	_menu_btn(v, "▶  Continuar", _on_continue, has_save, not has_save)
	if has_save:
		var sub := UITheme.make_label("%s · Día %d · %s · Nivel %d" % [
			info["company"], int(info["day"]), Fmt.money(info["money"]), int(info["level"])], 11, UITheme.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sub)
	_menu_btn(v, "＋  Nueva Partida", _show_new_game, not has_save)
	_menu_btn(v, "📁  Cargar Partida", _show_load)
	_menu_btn(v, "🏆  Desafíos", func(): _notice("Desafíos: próximamente."))
	_menu_btn(v, "⚙  Ajustes", _show_config)
	_menu_btn(v, "ℹ  Créditos", _show_credits)
	_menu_btn(v, "⏻  Salir", func(): get_tree().quit())

func _menu_btn(v: VBoxContainer, text: String, cb: Callable, primary: bool = false, disabled: bool = false) -> void:
	var b := UITheme.make_primary_button(text) if primary else UITheme.make_button(text)
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.disabled = disabled
	b.pressed.connect(cb)
	v.add_child(b)

# --- Nueva partida ----------------------------------------------------------
func _show_new_game() -> void:
	var v := _center_panel(460, 360)
	v.add_child(UITheme.make_title("Nueva Partida"))
	v.add_child(UITheme.make_label("Nombre de la empresa:", 13, UITheme.ACCENT))
	var name_edit := LineEdit.new()
	name_edit.text = "Industria S.A."
	name_edit.custom_minimum_size = Vector2(0, 34)
	v.add_child(name_edit)
	v.add_child(UITheme.make_label("Dificultad:", 13, UITheme.ACCENT))
	var diff := OptionButton.new()
	diff.add_item("Fácil", 0)
	diff.add_item("Normal", 1)
	diff.add_item("Difícil", 2)
	diff.select(1)
	v.add_child(diff)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var start := UITheme.make_button("Comenzar")
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func(): GameManager.request_new_game(name_edit.text, diff.selected))
	var back := UITheme.make_button("Volver")
	back.pressed.connect(_show_menu)
	row.add_child(start)
	row.add_child(back)
	v.add_child(row)

# --- Continuar / Cargar -----------------------------------------------------
func _on_continue() -> void:
	if not GameManager.request_load_game():
		_notice("No hay una partida disponible.")

func _show_load() -> void:
	var v := _center_panel(460, 340)
	v.add_child(UITheme.make_title("Cargar Partida"))
	var info: Dictionary = GameManager.save.get_save_info()
	if info.is_empty():
		v.add_child(UITheme.make_label("NO HAY PARTIDAS GUARDADAS.", 14, UITheme.WARN))
	else:
		var t := "%s\nDía %d · %s · Nivel %d\nGuardado: %s" % [
			info["company"], int(info["day"]), Fmt.money(info["money"]), int(info["level"]), info["date"]]
		var lbl := UITheme.make_label(t, 13)
		v.add_child(lbl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var load_btn := UITheme.make_button("Cargar")
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.pressed.connect(func(): GameManager.request_load_game())
		var del := UITheme.make_button("Eliminar")
		del.pressed.connect(func(): GameManager.save.delete_save(); _show_load())
		row.add_child(load_btn)
		row.add_child(del)
		v.add_child(row)
	var back := UITheme.make_button("Volver")
	back.pressed.connect(_show_menu)
	v.add_child(back)

func _show_config() -> void:
	var v := _center_panel(440, 240)
	v.add_child(UITheme.make_title("Configuración"))
	v.add_child(UITheme.make_label("Volumen, gráficos y controles: próximamente.\nGuardado automático cada 2 días de juego.", 13))
	var back := UITheme.make_button("Volver")
	back.pressed.connect(_show_menu)
	v.add_child(back)

func _show_credits() -> void:
	var v := _center_panel(440, 240)
	v.add_child(UITheme.make_title("Créditos"))
	v.add_child(UITheme.make_label("INDUSTRIA — juego de gestión industrial 3D.\nDesarrollo del proyecto Industria.", 13))
	var back := UITheme.make_button("Volver")
	back.pressed.connect(_show_menu)
	v.add_child(back)

func _notice(text: String) -> void:
	var v := _center_panel(420, 180)
	v.add_child(UITheme.make_title("Aviso"))
	v.add_child(UITheme.make_label(text, 14, UITheme.WARN))
	var back := UITheme.make_button("Volver")
	back.pressed.connect(_show_menu)
	v.add_child(back)
