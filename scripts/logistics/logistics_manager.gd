extends Node
## LogisticsManager — coordinador logístico de alto nivel.
##
## Aglutina almacenamiento y transporte para el resto del juego y ofrece
## utilidades como encontrar el puerto/objeto seleccionable más cercano a una
## posición (usado por la herramienta de cinta). No duplica lógica: delega en
## StorageManager y TransportManager.

func stock() -> Node:
	return GameManager.storage

func transport() -> Node:
	return GameManager.transport

## Nodo conectable (máquina o edificio con puerto) más cercano a un punto.
func nearest_connectable(world_pos: Vector3, max_dist: float = 6.0) -> Node:
	var best: Node = null
	var best_d := max_dist
	for m in GameManager.machines.machines:
		var d: float = m.global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = m
	for b in GameManager.buildings.buildings:
		if not b.has_method("port_receive_give"):
			continue
		var d: float = b.global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = b
	return best
