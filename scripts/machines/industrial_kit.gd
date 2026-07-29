extends RefCounted
class_name IndKit
## IndKit — kit visual industrial compartido de Industria (fase de arte §2, §3, §15).
##
## Centraliza los MATERIALES y las PIEZAS DE DETALLE (tornillos, rejillas,
## tuberías, cables, barandas, franjas de peligro, señales, plataformas) para que
## todas las máquinas, edificios, cintas y vehículos compartan el mismo lenguaje
## visual: metal + hormigón + amarillo de seguridad + desgaste moderado.
##
## Es sólo geometría/materiales: NO contiene lógica de gameplay. Así el modelo
## queda separado de la lógica (spec §16) y es fácil de sustituir por assets
## definitivos. Los constructores añaden hijos a un `parent` dado.

# --- Paleta de materiales (coherencia visual) -------------------------------
static func steel() -> StandardMaterial3D:
	return _m(Color(0.56, 0.58, 0.62), 0.38, 0.9)

static func dark_metal() -> StandardMaterial3D:
	return _m(Color(0.13, 0.14, 0.16), 0.5, 0.85)

static func housing(color: Color) -> StandardMaterial3D:
	return _m(color, 0.42, 0.6)

static func concrete() -> StandardMaterial3D:
	return _m(Color(0.24, 0.24, 0.26), 0.95, 0.0)

static func rubber() -> StandardMaterial3D:
	return _m(Color(0.07, 0.07, 0.08), 0.9, 0.0)

static func copper() -> StandardMaterial3D:
	return _m(Color(0.72, 0.45, 0.2), 0.45, 0.75)

static func hazard() -> StandardMaterial3D:
	var m := _m(Color(0.85, 0.72, 0.1), 0.55, 0.2)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.5, 0.05)
	m.emission_energy_multiplier = 0.35
	return m

static func glass() -> StandardMaterial3D:
	var m := _m(Color(0.4, 0.6, 0.7, 0.25), 0.1, 0.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.2, 0.4, 0.5)
	m.emission_energy_multiplier = 0.3
	return m

static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := _m(color, 0.4, 0.0)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

static func _m(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

# --- Primitivas base --------------------------------------------------------
static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func cyl(parent: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

# --- Piezas de detalle industrial -------------------------------------------
## Fila de tornillos/pernos a lo largo del eje X.
static func bolt_row(parent: Node3D, count: int, x0: float, x1: float, y: float, z: float, mat: Material) -> void:
	for i in range(count):
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		var b := cyl(parent, 0.05, 0.05, 0.06, Vector3(lerpf(x0, x1, t), y, z), mat)
		b.rotation_degrees = Vector3(90, 0, 0)

## Rejilla de ventilación (marco + lamas).
static func grille(parent: Node3D, w: float, h: float, pos: Vector3, mat: Material) -> void:
	box(parent, Vector3(w, h, 0.05), pos, mat)
	var slats := maxi(3, int(h / 0.12))
	var slat_mat := dark_metal()
	for i in range(slats):
		var y := lerpf(-h * 0.42, h * 0.42, float(i) / float(slats - 1))
		box(parent, Vector3(w * 0.9, 0.04, 0.08), pos + Vector3(0, y, 0.03), slat_mat)

## Tramo de tubería recto entre dos puntos locales.
static func pipe(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var mi := cyl(parent, radius, radius, length, mid, mat)
	mi.look_at_from_position(mid, b, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

## Cable colgante (dos segmentos con leve caída).
static func cable(parent: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	var sag := (a + b) * 0.5 + Vector3(0, -0.25, 0)
	pipe(parent, a, sag, 0.03, mat)
	pipe(parent, sag, b, 0.03, mat)

## Escalera vertical con largueros y peldaños.
static func ladder(parent: Node3D, base: Vector3, height: float, mat: Material) -> void:
	for side in [-1, 1]:
		cyl(parent, 0.03, 0.03, height, base + Vector3(side * 0.16, height * 0.5, 0), mat)
	var rungs := int(height / 0.35)
	for i in range(rungs):
		var r := cyl(parent, 0.025, 0.025, 0.34, base + Vector3(0, 0.3 + i * 0.35, 0), mat)
		r.rotation_degrees = Vector3(0, 0, 90)

## Baranda de seguridad con postes.
static func railing(parent: Node3D, center: Vector3, length: float, mat: Material) -> void:
	var top := cyl(parent, 0.03, 0.03, length, center + Vector3(0, 1.0, 0), mat)
	top.rotation_degrees = Vector3(0, 0, 90)
	var posts := maxi(2, int(length / 0.8))
	for i in range(posts + 1):
		var x := lerpf(-length * 0.5, length * 0.5, float(i) / float(posts))
		cyl(parent, 0.03, 0.03, 1.0, center + Vector3(x, 0.5, 0), mat)

## Plataforma/pasarela con rejilla.
static func platform(parent: Node3D, size: Vector2, pos: Vector3, mat: Material) -> void:
	box(parent, Vector3(size.x, 0.1, size.y), pos, mat)

## Franja de peligro (amarillo/negro) sobre una cara.
static func hazard_stripe(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	box(parent, size, pos, hazard())

## Señal de advertencia triangular sobre poste.
static func warning_sign(parent: Node3D, pos: Vector3) -> void:
	cyl(parent, 0.04, 0.04, 1.2, pos + Vector3(0, 0.6, 0), dark_metal())
	var plate := box(parent, Vector3(0.5, 0.5, 0.04), pos + Vector3(0, 1.3, 0), emissive(Color(0.9, 0.75, 0.1), 0.6))
	plate.rotation.z = deg_to_rad(45)
