extends Node
## QualityManager — calidad de la producción (spec §11 calidad, §19).
##
## La calidad depende de la condición de la máquina y de la especialización del
## personal (ingenieros). En la V1 influye en el valor de venta del producto.

func roll_quality(machine: Machine) -> float:
	var cond := clampf(machine.condition / 100.0, 0.0, 1.0)
	# Base 0.7..1.0 según condición.
	var q := lerpf(0.7, 1.0, cond)
	# Pequeña variación aleatoria.
	q += randf_range(-0.03, 0.03)
	# Bono global por ingenieros (calidad) si el sistema de trabajadores existe.
	if GameManager.workers:
		q += GameManager.workers.quality_bonus()
	return clampf(q, 0.5, 1.15)

## Multiplicador de precio de venta según la calidad media del stock (simplificado V1).
func sale_multiplier(quality: float) -> float:
	return clampf(quality, 0.5, 1.15)
