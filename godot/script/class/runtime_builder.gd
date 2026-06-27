extends RefCounted
class_name RuntimeBuilder

func prepare_and_launch(game_name: String, mod_name: String) -> Util.Stats:
	if(game_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.game_name_empty"))

	var game_config := Filesys.load_game_config(game_name)
	if(!game_config.ok):
		return game_config

	var run_path := str(game_config.data.get("run_path", "")).trim_prefix("/").trim_prefix("\\")
	if(run_path.is_empty()):
		return Util.Stats.new(false, tr("error.game_run_path_empty"))

	var game_dir := Filesys.GamePath.path_join(game_name)
	var run_dir := Filesys.RunPath
	Filesys.clear_run_directory()

	var build_result := Util.Stats.new(false, tr("error.unknown"))
	if(mod_name.strip_edges().is_empty()):
		build_result = Filesys.copy_directory(game_dir, run_dir)
	else:
		var mod_config := Filesys.load_mod_config(game_name, mod_name)
		if(!mod_config.ok): return mod_config

		var mod_dir := Filesys.ModPath.path_join(game_name).path_join(mod_name)
		build_result = Filesys.copy_directory(game_dir, run_dir)
		if(build_result.ok):
			build_result = Filesys.merge_directory_without_configs(mod_dir, run_dir)

	if(!build_result.ok):
		return build_result

	var executable_path := run_dir.path_join(run_path)
	if(!FileAccess.file_exists(executable_path)):
		return Util.Stats.new(false, tr("error.prepared_executable_not_found"))

	var steam_uri := str(game_config.data.get("steam_uri", "")).strip_edges()
	var steam_game_path := str(game_config.data.get("steam_game_path", "")).strip_edges()
	if(!steam_uri.is_empty() || !steam_game_path.is_empty()):
		return _launch_with_steam(game_dir, run_dir, executable_path, steam_uri, steam_game_path)

	var pid := OS.create_process(executable_path, PackedStringArray(), false)
	if(pid == -1):
		return Util.Stats.new(false, tr("error.failed_to_launch_executable"))

	return Util.Stats.new(true, tr("status.launched_game"), {"pid": pid, "path": executable_path})

func _launch_with_steam(game_dir: String, run_dir: String, executable_path: String, steam_uri: String, steam_game_path: String) -> Util.Stats:
	if(steam_uri.is_empty() || steam_game_path.is_empty()):
		return Util.Stats.new(false, tr("error.steam_settings_pair_required"))
	if(!DirAccess.dir_exists_absolute(steam_game_path)):
		return Util.Stats.new(false, tr("error.steam_game_path_not_found"))

	Global.begin_close_block(tr("error.close_blocked_while_updating_steam_files"))
	var backup_dir := Filesys.ModPath.path_join("__tmp__steam_backup_" + Time.get_datetime_string_from_system().replace(":", "_"))
	Filesys._delete_directory_if_exists(backup_dir)
	var backup_result := Filesys.copy_directory(steam_game_path, backup_dir)
	if(!backup_result.ok):
		Global.end_close_block()
		return backup_result

	var state_result := Filesys.save_runtime_state({
		"steam_game_path": steam_game_path,
		"backup_dir": backup_dir,
		"phase": "deploying",
		"executable_name": executable_path.get_file(),
	})
	if(!state_result.ok):
		Filesys._delete_directory_if_exists(backup_dir)
		Global.end_close_block()
		return state_result

	var deploy_result := _deploy_to_steam_game_path(run_dir, steam_game_path)
	if(!deploy_result.ok):
		_restore_steam_backup(steam_game_path, backup_dir)
		Global.end_close_block()
		return deploy_result

	state_result = Filesys.save_runtime_state({
		"steam_game_path": steam_game_path,
		"backup_dir": backup_dir,
		"phase": "launched",
		"executable_name": executable_path.get_file(),
	})
	if(!state_result.ok):
		_restore_steam_backup(steam_game_path, backup_dir)
		Global.end_close_block()
		return state_result
	Global.end_close_block()

	var launch_ok := OS.shell_open(steam_uri) == OK
	if(!launch_ok):
		Global.begin_close_block(tr("error.close_blocked_while_updating_steam_files"))
		_restore_steam_backup(steam_game_path, backup_dir)
		Global.end_close_block()
		return Util.Stats.new(false, tr("error.failed_to_launch_steam"))

	var wait_result := _wait_for_process_exit(executable_path.get_file())
	if(!wait_result.ok):
		return wait_result

	Global.begin_close_block(tr("error.close_blocked_while_updating_steam_files"))
	var restore_result := _restore_steam_backup(steam_game_path, backup_dir)
	Global.end_close_block()
	if(!restore_result.ok):
		return restore_result
	return Util.Stats.new(true, tr("status.launched_game"), {"path": steam_game_path, "steam_uri": steam_uri})

func _deploy_to_steam_game_path(run_dir: String, steam_game_path: String) -> Util.Stats:
	Filesys._delete_directory_contents(steam_game_path)
	return Filesys.merge_directory_without_configs(run_dir, steam_game_path)

func _restore_steam_backup(steam_game_path: String, backup_dir: String) -> Util.Stats:
	Filesys._delete_directory_contents(steam_game_path)
	var restore_result := Filesys.copy_directory(backup_dir, steam_game_path)
	if(!restore_result.ok):
		return Util.Stats.new(false, tr("error.failed_to_restore_steam_backup"))
	Filesys._delete_directory_if_exists(backup_dir)
	Filesys.clear_runtime_state()
	return Util.Stats.new(true, tr("status.ok"))

func _wait_for_process_exit(executable_name: String) -> Util.Stats:
	if(!OS.has_feature("windows")):
		return Util.Stats.new(false, tr("error.steam_wait_windows_only"))

	var saw_process := false
	for _i in range(120):
		if(_is_process_running(executable_name)):
			saw_process = true
			break
		OS.delay_msec(1000)
	if(!saw_process):
		return Util.Stats.new(false, tr("error.steam_game_process_not_found"))

	while _is_process_running(executable_name):
		OS.delay_msec(1000)
	return Util.Stats.new(true, tr("status.ok"))

func _is_process_running(executable_name: String) -> bool:
	var output: Array = []
	var exit_code := OS.execute("cmd", PackedStringArray(["/c", "tasklist", "/FI", "IMAGENAME eq " + executable_name]), output, true, false)
	if(exit_code != 0):
		return false
	return "\n".join(output).to_lower().contains(executable_name.to_lower())
