extends RefCounted
class_name UITheme
## UITheme — estilo visual de la UI de Industria (industrial moderno, acento ámbar).
##
## Centraliza colores y fábricas de controles con estilo (paneles redondeados con
## borde, botones con hover/pressed, chips del HUD) para que todo comparta la
## misma identidad. Mantiene las firmas usadas por los paneles existentes.

const BG := Color(0.09, 0.10, 0.13, 0.96)
const BG_SOFT := Color(0.14, 0.15, 0.18, 0.97)
const CHIP := Color(0.13, 0.14, 0.17, 0.9)
const ACCENT := Color(0.92, 0.63, 0.20)      # ámbar industrial
const ACCENT2 := Color(0.40, 0.82, 0.48)     # verde (dinero/éxito)
const TEXT := Color(0.90, 0.92, 0.94)
const MUTED := Color(0.62, 0.65, 0.70)
const WARN := Color(0.95, 0.75, 0.25)
const DANGER := Color(0.92, 0.38, 0.34)
const BORDER := Color(1, 1, 1, 0.08)

# --- Paneles ----------------------------------------------------------------
static func panel_style(bg: Color = BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s

static func make_panel(bg: Color = BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p

# --- Etiquetas --------------------------------------------------------------
static func make_label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_title(text: String) -> Label:
	var l := make_label(text, 18, ACCENT)
	l.add_theme_font_size_override("font_size", 18)
	return l

# --- Botones ----------------------------------------------------------------
static func _btn_box(bg: Color, border: Color, radius: int = 7) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func _style_button(b: Button, primary: bool) -> void:
	var base := ACCENT if primary else Color(0.18, 0.19, 0.23)
	var hover := ACCENT.lightened(0.12) if primary else Color(0.24, 0.25, 0.30)
	var press := ACCENT.darkened(0.15) if primary else Color(0.15, 0.16, 0.20)
	var border := ACCENT.darkened(0.1) if primary else BORDER
	b.add_theme_stylebox_override("normal", _btn_box(base, border))
	b.add_theme_stylebox_override("hover", _btn_box(hover, ACCENT if not primary else border))
	b.add_theme_stylebox_override("pressed", _btn_box(press, border))
	b.add_theme_stylebox_override("focus", _btn_box(base, border))
	var db := _btn_box(Color(0.14, 0.14, 0.16), BORDER)
	b.add_theme_stylebox_override("disabled", db)
	var fg := Color(0.1, 0.08, 0.05) if primary else TEXT
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1) if not primary else fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", MUTED)

static func make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 32)
	_style_button(b, false)
	return b

## Botón destacado (ámbar) para acciones principales (CTA).
static func make_primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 36)
	_style_button(b, true)
	return b

# --- Chip del HUD (etiqueta con fondo redondeado) ---------------------------
static func make_chip(icon: String, color: Color = TEXT) -> Label:
	# Devuelve la Label interna (para actualizar el texto); el chip la envuelve.
	var l := make_label(icon, 15, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func chip_panel(inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = CHIP
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	s.set_border_width_all(1)
	s.border_color = BORDER
	p.add_theme_stylebox_override("panel", s)
	p.add_child(inner)
	return p

static func hsep() -> HSeparator:
	return HSeparator.new()

# --- Theme GLOBAL -----------------------------------------------------------
## Un Theme que estiliza TODOS los controles estándar (no sólo los que pasan por
## las fábricas de arriba): barras de progreso, desplegables, scrollbars,
## separadores, checkboxes, campos de texto y sus menús emergentes. Se aplica al
## root de la UI para que nada quede con el look gris genérico de Godot.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	# Paneles.
	t.set_stylebox("panel", "PanelContainer", panel_style(BG))
	t.set_stylebox("panel", "Panel", panel_style(BG))

	# Botones estándar (los creados sin la fábrica también quedan bien).
	_theme_button(t, "Button")
	_theme_button(t, "OptionButton")
	_theme_button(t, "MenuButton")

	# Menú emergente de los OptionButton / MenuButton.
	var popbg := _flat(BG_SOFT, 10, BORDER, 1)
	popbg.content_margin_left = 6; popbg.content_margin_right = 6
	popbg.content_margin_top = 6; popbg.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", popbg)
	var hov := _flat(Color(0.22, 0.23, 0.28), 6, Color(0, 0, 0, 0), 0)
	t.set_stylebox("hover", "PopupMenu", hov)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	t.set_color("font_accelerator_color", "PopupMenu", MUTED)
	t.set_constant("v_separation", "PopupMenu", 4)

	# Etiquetas.
	t.set_color("font_color", "Label", TEXT)

	# Barra de progreso: fondo hundido + relleno ámbar redondeado.
	var pbbg := _flat(Color(0.06, 0.07, 0.09), 6, BORDER, 1)
	var pbfill := _flat(ACCENT, 6, Color(0, 0, 0, 0), 0)
	t.set_stylebox("background", "ProgressBar", pbbg)
	t.set_stylebox("fill", "ProgressBar", pbfill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 11)

	# Campo de texto.
	var le := _flat(Color(0.06, 0.07, 0.09), 7, BORDER, 1)
	le.content_margin_left = 10; le.content_margin_right = 10
	le.content_margin_top = 6; le.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le)
	var lef := _flat(Color(0.06, 0.07, 0.09), 7, ACCENT, 1)
	lef.content_margin_left = 10; lef.content_margin_right = 10
	lef.content_margin_top = 6; lef.content_margin_bottom = 6
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)

	# CheckBox / CheckButton.
	for ct in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", ct, TEXT)
		t.set_color("font_hover_color", ct, Color(1, 1, 1))
		t.set_color("font_pressed_color", ct, ACCENT)

	# Separadores: una línea fina y sutil (no el gris duro por defecto).
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.10)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("separator", "VSeparator", line)
	t.set_constant("separation", "HSeparator", 8)

	# Scrollbars finas y redondeadas (grabber ámbar al pasar el mouse).
	for sb in ["VScrollBar", "HScrollBar"]:
		var track := _flat(Color(0, 0, 0, 0.18), 5, Color(0, 0, 0, 0), 0)
		var grab := _flat(Color(0.32, 0.33, 0.38), 5, Color(0, 0, 0, 0), 0)
		var grab_hi := _flat(ACCENT.darkened(0.1), 5, Color(0, 0, 0, 0), 0)
		t.set_stylebox("scroll", sb, track)
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab_hi)
		t.set_stylebox("grabber_pressed", sb, grab_hi)

	# Tooltips coherentes con el resto.
	var tip := _flat(Color(0.06, 0.07, 0.09, 0.98), 8, BORDER, 1)
	tip.content_margin_left = 10; tip.content_margin_right = 10
	tip.content_margin_top = 6; tip.content_margin_bottom = 6
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)

	return t

static func _theme_button(t: Theme, type: String) -> void:
	var base := Color(0.18, 0.19, 0.23)
	t.set_stylebox("normal", type, _btn_box(base, BORDER))
	t.set_stylebox("hover", type, _btn_box(Color(0.24, 0.25, 0.30), ACCENT))
	t.set_stylebox("pressed", type, _btn_box(Color(0.15, 0.16, 0.20), BORDER))
	t.set_stylebox("focus", type, _btn_box(base, BORDER))
	t.set_stylebox("disabled", type, _btn_box(Color(0.14, 0.14, 0.16), BORDER))
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, Color(1, 1, 1))
	t.set_color("font_pressed_color", type, ACCENT)
	t.set_color("font_disabled_color", type, MUTED)

static func _flat(bg: Color, radius: int, border_col: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.set_border_width_all(border_w)
		s.border_color = border_col
	return s
