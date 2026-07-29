extends Node
## AutomationManager — coordinador de automatización (spec §16).
##
## Punto de acceso unificado a reglas y prioridades. En la V1 delega en
## RuleManager (motor SI→ENTONCES) y PriorityManager. Preparado para incorporar
## sensores y sistemas automáticos más avanzados en versiones futuras.

func rules() -> Node:
	return GameManager.rules

func priorities() -> Node:
	return GameManager.priority

## Atajo para crear una regla desde la UI.
func add_rule(cond_type: int, cond_params: Dictionary, act_type: int, act_params: Dictionary) -> Dictionary:
	return GameManager.rules.add_rule(cond_type, cond_params, act_type, act_params)

func rule_count() -> int:
	return GameManager.rules.rules.size()
