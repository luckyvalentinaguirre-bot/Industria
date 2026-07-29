extends RefCounted
class_name UITheme
## UITheme — helpers de construcción de UI por código (estilo limpio y moderno).
##
## Centraliza colores y fábricas de controles para que todos los paneles de
## Industria compartan la misma estética (spec §19). Nota de estructura: helper
## de UI, vive en scripts/ui/.

const BG := Color(0.10, 0.11, 0.13, 0.94)
const BG_SOFT := Color(0.15, 0.16, 0.19, 0.96)
const ACCENT := Color(0.30, 0.78, 0.86)
const ACCENT2 := Color(0.5, 0.85, 0.55)
const TEXT := Color(0.90, 0.92, 0.94)
const WARN := Color(0.95, 0.75, 0.25)
const DANGER := Color(0.92, 0.35, 0.32)

static func panel_style(bg: Color = BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_color = Color(1, 1, 1, 0.06)
	s.set_border_width_all(1)
	return s

static func make_panel(bg: Color = BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p

static func make_label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_title(text: String) -> Label:
	return make_label(text, 18, ACCENT)

static func make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 30)
	return b

static func hsep() -> HSeparator:
	return HSeparator.new()
