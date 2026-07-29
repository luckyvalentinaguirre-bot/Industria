extends RefCounted
class_name RandomEvent
## RandomEvent — descripción de un evento aleatorio.

var id: String = ""
var title: String = ""
var description: String = ""
var apply: Callable

func _init(p_id: String, p_title: String, p_desc: String, p_apply: Callable) -> void:
	id = p_id
	title = p_title
	description = p_desc
	apply = p_apply
