class_name Util
extends RefCounted

class Stats:
	var ok:bool;
	var message:String;
	var data:Dictionary;
	func _init(p_ok:bool, p_message:String, p_data:Dictionary = {}) -> void:
		ok = p_ok;
		message = p_message;
		data = p_data;
	
	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"message": message,
			"data": data,
		};
