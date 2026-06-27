class_name Util
extends RefCounted

static var loading_status := ""

class Stats:
	var ok:bool;
	var message:String;
	var data:Dictionary;
	func _init(p_ok:bool, p_message:String, p_data:Dictionary = {}) -> void:
		ok = p_ok;
		message = Util.trans(p_message);
		data = p_data;
	
	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"message": message,
			"data": data,
		};

static func trans(key: String) -> String:
	return TranslationServer.translate(key);

static func set_loading_status(message: String) -> void:
	loading_status = message

static func get_loading_status(default_message: String = "") -> String:
	return default_message if loading_status.is_empty() else loading_status

static func clear_loading_status() -> void:
	loading_status = ""
