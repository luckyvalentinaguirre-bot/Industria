extends RefCounted
class_name Fmt
## Fmt — utilidades de formato de texto compartidas (dinero, cantidades).

## Formatea un número entero con separador de miles (punto).
static func thousands(value: float) -> String:
	var n := int(round(abs(value)))
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if value < 0 else "") + out

## Dinero con símbolo, p.ej. "$15.000".
static func money(value: float) -> String:
	return "$" + thousands(value)

## Cantidad corta para HUD, p.ej. 1500 -> "1.5k".
static func short(value: float) -> String:
	var a := absf(value)
	if a >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if a >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return str(int(round(value)))
