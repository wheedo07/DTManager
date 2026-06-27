extends Node

const APP_TITLE := "DT Manager"
var close_block_message := ""

func _ready() -> void:
	get_tree().auto_accept_quit = false
	var restore_result := Filesys.restore_pending_runtime_if_needed(true)
	if(!restore_result.ok):
		alert(restore_result.message)

func _notification(what: int) -> void:
	if(what == NOTIFICATION_WM_CLOSE_REQUEST):
		if(!close_block_message.is_empty()):
			alert(close_block_message)
			return
		if(Filesys.has_pending_runtime_state()):
			if(Filesys.is_pending_runtime_game_running()):
				alert(tr("error.close_blocked_while_game_running"))
				return
			var restore_result := Filesys.restore_pending_runtime_if_needed()
			if(!restore_result.ok):
				alert(restore_result.message)
				return
		if(Filesys.has_pending_runtime_state()):
			alert(tr("error.close_blocked_while_game_running"))
			return
		get_tree().quit()

func begin_close_block(message: String) -> void:
	close_block_message = message

func end_close_block() -> void:
	close_block_message = ""

func alert(message: String) -> void:
	OS.alert(message, APP_TITLE);

func open_directory(path: String) -> bool:
	return OS.shell_open(ProjectSettings.globalize_path(path)) == OK

func open_target(target: String) -> bool:
	var output: Array = []
	var exit_code := OS.execute("cmd.exe", PackedStringArray([
		"/c",
		"start",
		"",
		target,
	]), output, false, false)
	return exit_code == OK
