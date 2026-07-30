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
