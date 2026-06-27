extends Node

const CONFIG_NAME := "config.dm";
const APP_CONFIG_NAME := "app_config.dm";
const MOD_METADATA_NAME := "mod.dm.json";
const THUMBNAIL_NAME := "thumbnail.dm.png";
const TEMP_PREFIX := "__tmp__";
const RUNTIME_STATE_NAME := "runtime_state.dm";
const RESTORE_DELAY_AFTER_KILL_MS := 1500;
const DATABASE_REPO_OWNER := "wheedo07";
const DATABASE_REPO_NAME := "DTManager";
const DATABASE_REPO_BRANCH := "main";

var GamePath: String
var ModPath: String
var RunPath: String
var PatcherPath: String
var VersionPath: String
var RuntimeStatePath: String
var AppConfigPath: String

func _init() -> void:
	var base_dir := get_root_path()
	GamePath = base_dir.path_join("Game")
	ModPath = base_dir.path_join("Mod")
	RunPath = base_dir.path_join("Run")
	PatcherPath = base_dir.path_join("Patcher")
	VersionPath = base_dir.path_join("GameVersions")
	RuntimeStatePath = base_dir.path_join(RUNTIME_STATE_NAME)
	AppConfigPath = base_dir.path_join(APP_CONFIG_NAME)
	_ensure_directory(GamePath)
	_ensure_directory(ModPath)
	_ensure_directory(RunPath)
	_ensure_directory(VersionPath)

func get_game_thumbnail_path(g_name: String) -> String:
	return GamePath.path_join(g_name).path_join(THUMBNAIL_NAME);

func get_mod_thumbnail_path(g_name: String, m_name) -> String:
	return ModPath.path_join(g_name).path_join(m_name).path_join(THUMBNAIL_NAME);

func get_root_path() -> String:
	if(OS.has_feature("editor")):
		return ProjectSettings.globalize_path("res://../output")
	return OS.get_executable_path().get_base_dir()

func addGame(path: String, g_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.game_name_empty"))
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, tr("error.executable_file_not_found"))

	var source_dir := path.get_base_dir()
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, tr("error.game_directory_not_found"))

	var game_dir := _game_dir(g_name)
	if(DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, tr("error.game_already_exists"))

	var copy_result := copy_directory(source_dir, game_dir)
	if(!copy_result.ok):
		return copy_result

	var run_path := _relative_path(source_dir, path)
	var config := {
		"name": g_name,
		"run_path": run_path,
	}
	var steam_info := _detect_steam_install(source_dir)
	if(!steam_info.is_empty()):
		config["steam_uri"] = str(steam_info.get("steam_uri", ""))
		config["steam_game_path"] = str(steam_info.get("steam_game_path", ""))

	var config_result := _write_json(game_dir.path_join(CONFIG_NAME), config)
	if(!config_result.ok):
		return config_result

	return Util.Stats.new(true, tr("status.game_added_successfully"), config)

func addMod(g_name: String, path: String, m_name: String, base_mod_name: String = "") -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.game_name_empty"))
	if(m_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.mod_name_empty"))
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, tr("error.mod_zip_file_not_found"))

	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, tr("error.game_directory_not_found"))

	var mod_dir := _mod_dir(g_name, m_name)
	if(DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, tr("error.mod_already_exists"))

	var patch_base_dir := game_dir
	var patch_base_temp_dir := ""
	if(!base_mod_name.strip_edges().is_empty()):
		var base_mod_dir := _mod_dir(g_name, base_mod_name)
		if(!DirAccess.dir_exists_absolute(base_mod_dir)):
			return Util.Stats.new(false, tr("error.mod_does_not_exist"))
		patch_base_temp_dir = _temp_dir("mod_base_" + g_name + "_" + m_name)
		_delete_directory_if_exists(patch_base_temp_dir)
		var base_copy_result := copy_directory(game_dir, patch_base_temp_dir)
		if(!base_copy_result.ok):
			return base_copy_result
		var base_merge_result := merge_directory_without_configs(base_mod_dir, patch_base_temp_dir)
		if(!base_merge_result.ok):
			_delete_directory_if_exists(patch_base_temp_dir)
			return base_merge_result
		patch_base_dir = patch_base_temp_dir

	var extract_dir := _temp_dir("mod_extract_" + g_name + "_" + m_name)
	_delete_directory_if_exists(extract_dir)
	var extract_result := extract_zip(path, extract_dir)
	if(!extract_result.ok):
		_delete_directory_if_exists(patch_base_temp_dir)
		return extract_result

	var package_metadata := _read_package_metadata(extract_dir)
	var metadata_base_dir := _resolve_metadata_base_dir(g_name, package_metadata)
	if(!metadata_base_dir.ok):
		_delete_directory_if_exists(extract_dir)
		_delete_directory_if_exists(patch_base_temp_dir)
		return metadata_base_dir
	if(!str(metadata_base_dir.data.get("base_dir", "")).is_empty()):
		patch_base_dir = str(metadata_base_dir.data.get("base_dir", ""))

	var xdelta_files := collect_files_with_extension(extract_dir, ".xdelta")
	var pck_files := collect_files_with_extension(extract_dir, ".pck")
	var build_result := Util.Stats.new(false, tr("error.unknown"))

	if(!xdelta_files.is_empty()):
		build_result = _build_xdelta_mod(patch_base_dir, extract_dir, xdelta_files, mod_dir)
	elif(!pck_files.is_empty()):
		var patcher_result := ensure_patchers_from_database()
		if(!patcher_result.ok):
			_delete_directory_if_exists(extract_dir)
			_delete_directory_if_exists(patch_base_temp_dir)
			return patcher_result
		build_result = _build_gddelta_mod(g_name, patch_base_dir, extract_dir, pck_files, mod_dir, m_name)
	else:
		build_result = copy_directory(extract_dir, mod_dir)

	_delete_directory_if_exists(extract_dir)
	_delete_directory_if_exists(patch_base_temp_dir)
	if(!build_result.ok):
		_delete_directory_if_exists(mod_dir)
		return build_result

	var config_result := _write_json(mod_dir.path_join(CONFIG_NAME), _mod_config_data(g_name, m_name, package_metadata))
	if(!config_result.ok):
		_delete_directory_if_exists(mod_dir)
		return config_result

	return Util.Stats.new(true, tr("status.mod_added_successfully"), {
		"name": m_name,
		"game_name": g_name,
	})

func list_games() -> Array[Dictionary]:
	var games: Array[Dictionary] = []
	for game_name in DirAccess.get_directories_at(GamePath):
		var config_result := load_game_config(game_name)
		if(config_result.ok):
			games.append(config_result.data)
	return games

func list_mods(g_name: String) -> Array[Dictionary]:
	var mods: Array[Dictionary] = []
	var game_mod_root := ModPath.path_join(g_name)
	if(!DirAccess.dir_exists_absolute(game_mod_root)):
		return mods

	for mod_name in DirAccess.get_directories_at(game_mod_root):
		var config_result := load_mod_config(g_name, mod_name)
		if(config_result.ok):
			mods.append(config_result.data)
	return mods

func load_game_config(g_name: String) -> Util.Stats:
	return _read_json(_game_dir(g_name).path_join(CONFIG_NAME))

func save_game_config(g_name: String, config: Dictionary) -> Util.Stats:
	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, tr("error.game_does_not_exist"))
	return _write_json(game_dir.path_join(CONFIG_NAME), config)

func detect_steam_install(path: String) -> Dictionary:
	return _detect_steam_install(path)

func load_app_config() -> Util.Stats:
	if(!FileAccess.file_exists(AppConfigPath)):
		return Util.Stats.new(true, tr("status.ok"), {})
	return _read_json(AppConfigPath)

func save_app_config(config: Dictionary) -> Util.Stats:
	return _write_json(AppConfigPath, config)

func check_steam_account(username: String, password: String) -> Util.Stats:
	if(username.strip_edges().is_empty() || password.is_empty()):
		return Util.Stats.new(false, tr("error.steam_credentials_not_set"))
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		var patcher_result := ensure_patchers_from_database()
		if(!patcher_result.ok):
			return patcher_result
		depot_downloader_path = _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		return Util.Stats.new(false, tr("error.depotdownloader_executable_not_found"))

	var temp_dir := _temp_dir("steam_account_check")
	_delete_directory_if_exists(temp_dir)
	_ensure_directory(temp_dir)
	var output: Array = []
	var args := PackedStringArray([
		"-app", "480",
		"-username", username,
		"-password", password,
		"-manifest-only",
		"-dir", temp_dir,
	])
	var exit_code := OS.execute(depot_downloader_path, args, output, true, false)
	_delete_directory_if_exists(temp_dir)
	if(exit_code != 0):
		return Util.Stats.new(false, tr("error.steam_account_check_failed") % ["\n".join(output)])
	return Util.Stats.new(true, tr("status.steam_account_connected"))

func load_mod_config(g_name: String, m_name: String) -> Util.Stats:
	return _read_json(_mod_dir(g_name, m_name).path_join(CONFIG_NAME))

func sync_database_from_repository() -> Util.Stats:
	var patcher_result := _load_remote_database_json("Patcher.json")
	if(!patcher_result.ok):
		return patcher_result
	return Util.Stats.new(true, tr("status.database_synced"))

func ensure_patchers_from_database() -> Util.Stats:
	var config_result := _load_remote_database_json("Patcher.json")
	if(!config_result.ok):
		return config_result

	for patcher_name in config_result.data.keys():
		var normalized_name := str(patcher_name).to_lower()
		if(normalized_name == "xdelta" || normalized_name == "xdelta3"):
			continue
		var url := str(config_result.data.get(patcher_name, ""))
		if(url.is_empty()):
			continue
		if(_is_patcher_installed(str(patcher_name))):
			continue
		var install_result := _install_patcher_archive(str(patcher_name), url)
		if(!install_result.ok):
			return install_result

	return Util.Stats.new(true, tr("status.patchers_ready"))

func download_database_manifest(app_id: String, manifest_id: String, destination_dir: String, username: String = "", password: String = "") -> Util.Stats:
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		var patcher_result := ensure_patchers_from_database()
		if(!patcher_result.ok):
			return patcher_result
		depot_downloader_path = _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		return Util.Stats.new(false, tr("error.depotdownloader_executable_not_found"))

	var game_result := load_database_game(app_id)
	if(!game_result.ok):
		return game_result
	if(!_database_game_has_manifest(game_result.data, manifest_id)):
		return Util.Stats.new(false, tr("error.database_manifest_not_listed"))

	var manifest_result := load_database_manifest(app_id, manifest_id)
	if(!manifest_result.ok):
		return manifest_result

	_ensure_directory(destination_dir)
	for depot_entry in manifest_result.data.get("depots", []):
		if(typeof(depot_entry) != TYPE_DICTIONARY):
			continue
		var depot_id := _json_number_to_string(depot_entry.get("depot_id", ""))
		var depot_manifest_id := _json_number_to_string(depot_entry.get("manifest_id", ""))
		if(depot_id.is_empty() || depot_manifest_id.is_empty()):
			continue
		var args := [
			"-app", app_id,
			"-depot", depot_id,
			"-manifest", depot_manifest_id,
			"-dir", destination_dir,
		];
		if(!username.is_empty()):
			args.append_array(["-username", "\"%s\"" % username])
		if(!password.is_empty()):
			args.append_array(["-password", "\"%s\"" % password])
		var output: Array = []
		var exit_code := OS.execute(depot_downloader_path, args, output, true, false)
		if(exit_code != 0):
			return Util.Stats.new(false, tr("error.depot_download_failed") % ["\n".join(output)])

	return Util.Stats.new(true, tr("status.depot_download_complete"))

func load_database_game(app_id: String) -> Util.Stats:
	return _load_remote_database_json("%s/game.json" % app_id)

func load_database_manifest(app_id: String, manifest_id: String) -> Util.Stats:
	return _load_remote_database_json("%s/manifests/%s.json" % [app_id, manifest_id])

func get_manifest_cache_dir(app_id: String, manifest_id: String) -> String:
	return VersionPath.path_join(app_id).path_join(manifest_id)

func resolve_game_base_dir(game_name: String, mod_name: String = "") -> Util.Stats:
	var base_dir := _game_dir(game_name)
	if(mod_name.strip_edges().is_empty()):
		return Util.Stats.new(true, tr("status.ok"), {"base_dir": base_dir})
	var mod_config_result := load_mod_config(game_name, mod_name)
	if(!mod_config_result.ok):
		return mod_config_result
	return _resolve_metadata_base_dir(game_name, mod_config_result.data, base_dir)

func save_mod_config(g_name: String, m_name: String, config: Dictionary) -> Util.Stats:
	var mod_dir := _mod_dir(g_name, m_name)
	if(!DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, tr("error.mod_does_not_exist"))
	return _write_json(mod_dir.path_join(CONFIG_NAME), config)

func save_thumbnail(target_path: String, image_path: String) -> Util.Stats:
	if(image_path.strip_edges().is_empty()):
		return Util.Stats.new(true, tr("status.ok"))
	if(!FileAccess.file_exists(image_path)):
		return Util.Stats.new(false, tr("error.thumbnail_file_not_found"))
	var target_dir := target_path.get_base_dir()
	if(!DirAccess.dir_exists_absolute(target_dir)):
		return Util.Stats.new(false, tr("error.source_directory_not_found"))
	if(FileAccess.file_exists(target_path)):
		DirAccess.remove_absolute(target_path)
	var copy_error := DirAccess.copy_absolute(image_path, target_path)
	if(copy_error != OK):
		return Util.Stats.new(false, tr("error.failed_to_copy_thumbnail"))
	return Util.Stats.new(true, tr("status.ok"))

func save_runtime_state(data: Dictionary) -> Util.Stats:
	return _write_json(RuntimeStatePath, data)

func load_runtime_state() -> Util.Stats:
	return _read_json(RuntimeStatePath)

func clear_runtime_state() -> void:
	if(FileAccess.file_exists(RuntimeStatePath)):
		DirAccess.remove_absolute(RuntimeStatePath)

func has_pending_runtime_state() -> bool:
	return FileAccess.file_exists(RuntimeStatePath)

func is_pending_runtime_game_running() -> bool:
	if(!has_pending_runtime_state()):
		return false
	var state_result := load_runtime_state()
	if(!state_result.ok):
		return false
	if(str(state_result.data.get("phase", "")) != "launched"):
		return false
	var executable_name := str(state_result.data.get("executable_name", ""))
	if(executable_name.is_empty()):
		return false
	return _is_process_running_by_name(executable_name)

func restore_pending_runtime_if_needed(force_kill_running: bool = false) -> Util.Stats:
	if(!FileAccess.file_exists(RuntimeStatePath)):
		return Util.Stats.new(true, tr("status.ok"))

	var state_result := load_runtime_state()
	if(!state_result.ok):
		return state_result

	var steam_game_path := str(state_result.data.get("steam_game_path", ""))
	var backup_dir := str(state_result.data.get("backup_dir", ""))
	var phase := str(state_result.data.get("phase", ""))
	var executable_name := str(state_result.data.get("executable_name", ""))
	if(steam_game_path.is_empty() || backup_dir.is_empty()):
		clear_runtime_state()
		return Util.Stats.new(false, tr("error.runtime_state_invalid"))
	if(!DirAccess.dir_exists_absolute(backup_dir)):
		clear_runtime_state()
		return Util.Stats.new(false, tr("error.runtime_backup_not_found"))
	if(force_kill_running && phase == "launched" && !executable_name.is_empty()):
		var kill_result := _kill_process_by_name(executable_name)
		if(!kill_result.ok):
			return kill_result
		OS.delay_msec(RESTORE_DELAY_AFTER_KILL_MS)

	_delete_directory_contents(steam_game_path)
	var restore_result := copy_directory(backup_dir, steam_game_path)
	if(!restore_result.ok):
		return Util.Stats.new(false, tr("error.failed_to_restore_steam_backup"))
	_delete_directory_if_exists(backup_dir)
	clear_runtime_state()
	return Util.Stats.new(true, tr("status.ok"))

func copy_directory(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, false)

func merge_directory(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, true)


func merge_directory_without_configs(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, true, [CONFIG_NAME])

func extract_zip(zip_path: String, destination_dir: String) -> Util.Stats:
	_ensure_directory(destination_dir)
	var zip_reader := ZIPReader.new()
	var open_error := zip_reader.open(zip_path)
	if(open_error != OK):
		return Util.Stats.new(false, tr("error.failed_to_open_zip"))

	for entry_path in zip_reader.get_files():
		var normalized := entry_path.trim_prefix("/")
		if(normalized.ends_with("/")):
			_ensure_directory(destination_dir.path_join(normalized))
			continue
		var output_path := destination_dir.path_join(normalized)
		_ensure_directory(output_path.get_base_dir())
		var bytes := zip_reader.read_file(entry_path)
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if(file == null):
			zip_reader.close()
			return Util.Stats.new(false, tr("error.failed_to_write_extracted_file"))
		file.store_buffer(bytes)

	zip_reader.close()
	return Util.Stats.new(true, "ok")

func collect_files_with_extension(root_dir: String, extension: String, relative_path: String = "") -> Array[String]:
	var files: Array[String] = []
	var current_dir := root_dir if relative_path.is_empty() else root_dir.path_join(relative_path)

	for directory_name in DirAccess.get_directories_at(current_dir):
		var nested_relative := directory_name if relative_path.is_empty() else relative_path.path_join(directory_name)
		files.append_array(collect_files_with_extension(root_dir, extension, nested_relative))

	for file_name in DirAccess.get_files_at(current_dir):
		var relative_file := file_name if relative_path.is_empty() else relative_path.path_join(file_name)
		if(relative_file.to_lower().ends_with(extension)):
			files.append(relative_file)

	return files

func delete_game(g_name: String) -> Util.Stats:
	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, tr("error.game_does_not_exist"))
	_delete_directory_if_exists(ModPath.path_join(g_name))
	_delete_directory_if_exists(game_dir)
	return Util.Stats.new(true, tr("status.game_deleted"))

func delete_mod(g_name: String, m_name: String) -> Util.Stats:
	var mod_dir := _mod_dir(g_name, m_name)
	if(!DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, tr("error.mod_does_not_exist"))
	_delete_directory_if_exists(mod_dir)
	return Util.Stats.new(true, tr("status.mod_deleted"))

func rename_game(old_name: String, new_name: String) -> Util.Stats:
	if(old_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.game_name_empty"))
	if(new_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.rename_name_empty"))
	if(old_name == new_name):
		return Util.Stats.new(true, tr("status.ok"), {"name": new_name})

	var old_game_dir := _game_dir(old_name)
	var new_game_dir := _game_dir(new_name)
	if(!DirAccess.dir_exists_absolute(old_game_dir)):
		return Util.Stats.new(false, tr("error.game_does_not_exist"))
	if(DirAccess.dir_exists_absolute(new_game_dir)):
		return Util.Stats.new(false, tr("error.game_already_exists"))

	var old_mod_root := ModPath.path_join(old_name)
	var new_mod_root := ModPath.path_join(new_name)
	if(DirAccess.dir_exists_absolute(new_mod_root)):
		return Util.Stats.new(false, tr("error.game_already_exists"))

	var moved_mod_root := false
	if(DirAccess.dir_exists_absolute(old_mod_root)):
		var move_mod_error := DirAccess.rename_absolute(old_mod_root, new_mod_root)
		if(move_mod_error != OK):
			return Util.Stats.new(false, tr("error.failed_to_rename_directory"))
		moved_mod_root = true

	var move_game_error := DirAccess.rename_absolute(old_game_dir, new_game_dir)
	if(move_game_error != OK):
		if(moved_mod_root):
			DirAccess.rename_absolute(new_mod_root, old_mod_root)
		return Util.Stats.new(false, tr("error.failed_to_rename_directory"))

	var game_config_result := load_game_config(new_name)
	if(!game_config_result.ok):
		return game_config_result
	var game_config := game_config_result.data
	game_config["name"] = new_name
	var save_game_result := save_game_config(new_name, game_config)
	if(!save_game_result.ok):
		return save_game_result

	if(DirAccess.dir_exists_absolute(new_mod_root)):
		for mod_name in DirAccess.get_directories_at(new_mod_root):
			var mod_config_result := load_mod_config(new_name, mod_name)
			if(!mod_config_result.ok):
				return mod_config_result
			var mod_config := mod_config_result.data
			mod_config["game_name"] = new_name
			var save_mod_result := _write_json(_mod_dir(new_name, mod_name).path_join(CONFIG_NAME), mod_config)
			if(!save_mod_result.ok):
				return save_mod_result

	return Util.Stats.new(true, tr("status.game_renamed"), {"name": new_name})

func rename_mod(g_name: String, old_name: String, new_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.game_name_empty"))
	if(old_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.mod_name_empty"))
	if(new_name.strip_edges().is_empty()):
		return Util.Stats.new(false, tr("error.rename_name_empty"))
	if(old_name == new_name):
		return Util.Stats.new(true, tr("status.ok"), {"name": new_name})

	var old_mod_dir := _mod_dir(g_name, old_name)
	var new_mod_dir := _mod_dir(g_name, new_name)
	if(!DirAccess.dir_exists_absolute(old_mod_dir)):
		return Util.Stats.new(false, tr("error.mod_does_not_exist"))
	if(DirAccess.dir_exists_absolute(new_mod_dir)):
		return Util.Stats.new(false, tr("error.mod_already_exists"))

	var move_error := DirAccess.rename_absolute(old_mod_dir, new_mod_dir)
	if(move_error != OK):
		return Util.Stats.new(false, tr("error.failed_to_rename_directory"))

	var mod_config_result := load_mod_config(g_name, new_name)
	if(!mod_config_result.ok):
		return mod_config_result
	var mod_config := mod_config_result.data
	mod_config["name"] = new_name
	var save_result := _write_json(new_mod_dir.path_join(CONFIG_NAME), mod_config)
	if(!save_result.ok):
		return save_result

	return Util.Stats.new(true, tr("status.mod_renamed"), {"name": new_name})

func clear_run_directory() -> void:
	_delete_directory_contents(RunPath)

func _build_xdelta_mod(base_dir: String, extract_dir: String, patch_files: Array[String], mod_dir: String) -> Util.Stats:
	_ensure_directory(mod_dir)
	var override_result := _copy_override_files(extract_dir, mod_dir, [".xdelta", ".pck"])
	if(!override_result.ok):
		return override_result

	for relative_path in patch_files:
		var patch_file := extract_dir.path_join(relative_path)
		var target_relative := _resolve_xdelta_target_relative(base_dir, relative_path)
		if(target_relative.is_empty()):
			return Util.Stats.new(false, tr("error.xdelta_base_file_not_found"))
		var source_target_file := base_dir.path_join(target_relative)
		var output_target_file := mod_dir.path_join(target_relative)
		_ensure_directory(output_target_file.get_base_dir())
		var patch_result := _apply_single_xdelta(patch_file, source_target_file, output_target_file)
		if(!patch_result.ok):
			return patch_result

	return Util.Stats.new(true, tr("status.ok"))

func _resolve_xdelta_target_relative(root_dir: String, relative_patch_path: String) -> String:
	var relative_without_xdelta := relative_patch_path.substr(0, relative_patch_path.length() - ".xdelta".length())
	var direct_target := root_dir.path_join(relative_without_xdelta)
	if(FileAccess.file_exists(direct_target)):
		return relative_without_xdelta

	var parent_relative := relative_without_xdelta.get_base_dir()
	var parent_dir := root_dir if parent_relative == "." else root_dir.path_join(parent_relative)
	if(!DirAccess.dir_exists_absolute(parent_dir)):
		return ""

	var basename := relative_without_xdelta.get_file()
	var matched_file := _find_file_name_by_basename(parent_dir, basename)
	if(matched_file.is_empty()):
		return ""
	return matched_file if parent_relative == "." else parent_relative.path_join(matched_file)

func _build_gddelta_mod(g_name: String, base_dir: String, extract_dir: String, patch_files: Array[String], mod_dir: String, m_name: String) -> Util.Stats:
	var game_config := load_game_config(g_name)
	if(!game_config.ok):
		return game_config

	var run_path := str(game_config.data.get("run_path", "")).trim_prefix("/").trim_prefix("\\")
	if(run_path.is_empty()):
		return Util.Stats.new(false, tr("error.game_run_path_empty"))

	var current_executable := base_dir.path_join(run_path)
	if(!FileAccess.file_exists(current_executable)):
		return Util.Stats.new(false, tr("error.base_executable_not_found"))

	var gddelta_path := _resolve_gddelta_path()
	if(gddelta_path.is_empty()):
		return Util.Stats.new(false, tr("error.gddelta_executable_not_found"))

	var stage_paths: Array[String] = []
	var patch_count := patch_files.size()

	for index in range(patch_count):
		var patch_file := extract_dir.path_join(patch_files[index])
		var patch_basename := patch_files[index].get_basename().get_file()
		var executable_root := base_dir if index == 0 else current_executable.get_base_dir()
		var matched_executable := _find_file_path_by_basename_recursive(executable_root, patch_basename, ".exe")
		if(!matched_executable.is_empty()):
			current_executable = matched_executable

		var output_dir := mod_dir
		if(index < patch_count - 1):
			output_dir = _temp_dir("gddelta_stage_%s_%s_%d" % [g_name, m_name, index])
			_delete_directory_if_exists(output_dir)
			stage_paths.append(output_dir)
		else:
			_delete_directory_if_exists(mod_dir)

		var output: Array = []
		var exit_code := OS.execute(gddelta_path, ["apply", current_executable, patch_file, output_dir], output, true, false)
		if(exit_code != 0):
			for stage_path in stage_paths:
				_delete_directory_if_exists(stage_path)
			return Util.Stats.new(false, tr("error.gddelta_apply_failed") % ["\n".join(output)])

		current_executable = output_dir.path_join(run_path)
		if(!FileAccess.file_exists(current_executable)):
			for stage_path in stage_paths:
				_delete_directory_if_exists(stage_path)
			return Util.Stats.new(false, tr("error.patched_executable_not_found"))

	for stage_path in stage_paths:
		_delete_directory_if_exists(stage_path)
	return Util.Stats.new(true, tr("status.ok"))

func _apply_single_xdelta(patch_file: String, source_file: String, output_file: String) -> Util.Stats:
	if(!FileAccess.file_exists(source_file)):
		return Util.Stats.new(false, tr("error.xdelta_base_file_not_found"))

	var xdelta_path := _resolve_xdelta_path()
	if(xdelta_path.is_empty()):
		return Util.Stats.new(false, tr("error.xdelta_executable_not_found"))

	var output: Array = []
	var exit_code := OS.execute(xdelta_path, ["-d", "-s", source_file, patch_file, output_file], output, true, false)
	if(exit_code != 0):
		return Util.Stats.new(false, tr("error.xdelta_apply_failed") % ["\n".join(output)])
	return Util.Stats.new(true, tr("status.ok"))

func _copy_directory_internal(source_dir: String, destination_dir: String, overwrite: bool, excluded_files: Array[String] = []) -> Util.Stats:
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, tr("error.source_directory_not_found"))
	_ensure_directory(destination_dir)

	for directory_name in DirAccess.get_directories_at(source_dir):
		var nested_result := _copy_directory_internal(source_dir.path_join(directory_name), destination_dir.path_join(directory_name), overwrite, excluded_files)
		if(!nested_result.ok):
			return nested_result

	for file_name in DirAccess.get_files_at(source_dir):
		if(file_name in excluded_files): continue;
		var source_file := source_dir.path_join(file_name)
		var destination_file := destination_dir.path_join(file_name)
		if(overwrite && FileAccess.file_exists(destination_file)):
			DirAccess.remove_absolute(destination_file)
		var copy_error := DirAccess.copy_absolute(source_file, destination_file)
		if(copy_error != OK):
			return Util.Stats.new(false, tr("error.failed_to_copy_file") + ": " + source_file)

	return Util.Stats.new(true, tr("status.ok"))


func _copy_override_files(source_dir: String, destination_dir: String, excluded_extensions: Array[String], relative_path: String = "") -> Util.Stats:
	var current_source_dir := source_dir if relative_path.is_empty() else source_dir.path_join(relative_path)
	for directory_name in DirAccess.get_directories_at(current_source_dir):
		var nested_relative := directory_name if relative_path.is_empty() else relative_path.path_join(directory_name)
		var nested_result := _copy_override_files(source_dir, destination_dir, excluded_extensions, nested_relative)
		if(!nested_result.ok):
			return nested_result

	for file_name in DirAccess.get_files_at(current_source_dir):
		if(file_name == CONFIG_NAME): continue;
		var skip := false
		for extension in excluded_extensions:
			if(file_name.to_lower().ends_with(extension)):
				skip = true
				break
		if(skip): continue;
		var file_relative := file_name if relative_path.is_empty() else relative_path.path_join(file_name)
		var destination_file := destination_dir.path_join(file_relative)
		_ensure_directory(destination_file.get_base_dir())
		var copy_error := DirAccess.copy_absolute(current_source_dir.path_join(file_name), destination_file)
		if(copy_error != OK):
			return Util.Stats.new(false, tr("error.failed_to_copy_override_file") + ": " + file_relative)

	return Util.Stats.new(true, tr("status.ok"))

func _read_json(path: String) -> Util.Stats:
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, tr("error.config_file_not_found"))
	var file := FileAccess.open(path, FileAccess.READ)
	if(file == null):
		return Util.Stats.new(false, tr("error.failed_to_open_config_file"))
	var parsed = JSON.parse_string(file.get_as_text())
	if(typeof(parsed) != TYPE_DICTIONARY):
		return Util.Stats.new(false, tr("error.config_file_invalid"))
	return Util.Stats.new(true, tr("status.ok"), parsed)

func _write_json(path: String, data: Dictionary) -> Util.Stats:
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if(file == null):
		return Util.Stats.new(false, tr("error.failed_to_write_config_file"))
	file.store_string(JSON.stringify(data, "\t"))
	return Util.Stats.new(true, tr("status.ok"))


func _mod_config_data(g_name: String, m_name: String, metadata: Dictionary = {}) -> Dictionary:
	var config := {
		"name": m_name,
		"game_name": g_name,
	}
	for key in ["app_id", "manifest_id", "branch"]:
		if(metadata.has(key)):
			config[key] = metadata[key]
	return config

func _ensure_directory(path: String) -> void:
	if(!DirAccess.dir_exists_absolute(path)):
		DirAccess.make_dir_recursive_absolute(path)

func _delete_directory_if_exists(path: String) -> void:
	if(!_is_safe_directory_target(path)):
		return
	if(!DirAccess.dir_exists_absolute(path)): return;
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		_delete_directory_if_exists(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _delete_directory_contents(path: String) -> void:
	if(!_is_safe_directory_target(path)):
		return
	if(!DirAccess.dir_exists_absolute(path)): return;
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		_delete_directory_if_exists(path.path_join(directory_name))


func _relative_path(root: String, path: String) -> String:
	var normalized_root := root.replace("\\", "/")
	var normalized_path := path.replace("\\", "/")
	return normalized_path.trim_prefix(normalized_root)


func _game_dir(g_name: String) -> String:
	return GamePath.path_join(g_name)


func _mod_dir(g_name: String, m_name: String) -> String:
	return ModPath.path_join(g_name).path_join(m_name)


func _temp_dir(name: String) -> String:
	return ModPath.path_join(TEMP_PREFIX + name)

func _read_package_metadata(extract_dir: String) -> Dictionary:
	var metadata_path := extract_dir.path_join(MOD_METADATA_NAME)
	if(!FileAccess.file_exists(metadata_path)):
		return {}
	var metadata_result := _read_json(metadata_path)
	if(!metadata_result.ok):
		return {}
	return metadata_result.data

func _resolve_depot_downloader_path() -> String:
	var path := PatcherPath.path_join("DepotDownloader").path_join("DepotDownloader.exe");
	if(FileAccess.file_exists(path)): return path;
	return "";

func _resolve_xdelta_path() -> String:
	var path := PatcherPath.path_join("xdelta.exe");
	if(FileAccess.file_exists(path)): return path;
	return "";

func _resolve_gddelta_path() -> String:
	var path := PatcherPath.path_join("GodotDelta").path_join("gddelta.exe");
	if(FileAccess.file_exists(path)): return path;
	return "";

func _is_patcher_installed(patcher_name: String) -> bool:
	match patcher_name.to_lower():
		"godotdelta":
			return !_resolve_gddelta_path().is_empty()
		"depotdownloader":
			return !_resolve_depot_downloader_path().is_empty()
		_:
			return false

func _install_patcher_archive(patcher_name: String, url: String) -> Util.Stats:
	var archive_path := _temp_dir("patcher_" + patcher_name.to_lower() + ".zip")
	var extract_dir := _temp_dir("patcher_" + patcher_name.to_lower())
	var install_dir := _patcher_install_dir(patcher_name)
	_delete_directory_if_exists(extract_dir)
	_delete_directory_if_exists(install_dir)
	if(FileAccess.file_exists(archive_path)):
		DirAccess.remove_absolute(archive_path)

	var download_result := _download_url_to_file(url, archive_path)
	if(!download_result.ok):
		return download_result

	var extract_result := extract_zip(archive_path, extract_dir)
	if(!extract_result.ok):
		DirAccess.remove_absolute(archive_path)
		return extract_result

	var source_dir := _resolve_extracted_root(extract_dir)
	var merge_result := merge_directory(source_dir, install_dir)
	DirAccess.remove_absolute(archive_path)
	_delete_directory_if_exists(extract_dir)
	if(!merge_result.ok):
		return merge_result

	return Util.Stats.new(true, tr("status.patchers_ready"))

func _resolve_metadata_base_dir(game_name: String, metadata: Dictionary, fallback_dir: String = "") -> Util.Stats:
	var app_id := str(metadata.get("app_id", "")).strip_edges()
	var manifest_id := str(metadata.get("manifest_id", "")).strip_edges()
	if(app_id.is_empty() || manifest_id.is_empty()):
		return Util.Stats.new(true, tr("status.ok"), {"base_dir": fallback_dir if !fallback_dir.is_empty() else _game_dir(game_name)})

	var cache_dir := get_manifest_cache_dir(app_id, manifest_id)
	if(!_directory_has_entries(cache_dir)):
		var app_config_result := load_app_config()
		if(!app_config_result.ok):
			return app_config_result
		var steam_username := str(app_config_result.data.get("steam_username", "")).strip_edges()
		var steam_password := str(app_config_result.data.get("steam_password", ""))
		var download_result := download_database_manifest(app_id, manifest_id, cache_dir, steam_username, steam_password)
		if(!download_result.ok):
			return download_result
	if(!_directory_has_entries(cache_dir)):
		return Util.Stats.new(false, tr("error.manifest_cache_not_found"))
	return Util.Stats.new(true, tr("status.ok"), {"base_dir": cache_dir})

func _download_url_to_file(url: String, output_path: String) -> Util.Stats:
	var request_result := _request_url(url, ["User-Agent: DTManager"])
	if(!bool(request_result.get("ok", false))):
		return Util.Stats.new(false, str(request_result.get("message", tr("error.failed_to_download_file"))))
	_ensure_directory(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if(file == null):
		return Util.Stats.new(false, tr("error.failed_to_write_extracted_file"))
	file.store_buffer(request_result.get("body", PackedByteArray()))
	return Util.Stats.new(true, tr("status.ok"))

func _request_json_from_url(url: String, headers: PackedStringArray = []) -> Dictionary:
	var request_result := _request_url(url, headers)
	if(!bool(request_result.get("ok", false))):
		return request_result
	var parsed = JSON.parse_string(PackedByteArray(request_result.get("body", [])).get_string_from_utf8());
	if(parsed == null):
		return {"ok": false, "message": tr("error.failed_to_parse_remote_json")}
	return {"ok": true, "data": parsed}

func _load_remote_database_json(relative_path: String) -> Util.Stats:
	var url := "https://raw.githubusercontent.com/%s/%s/%s/database/%s" % [
		DATABASE_REPO_OWNER,
		DATABASE_REPO_NAME,
		DATABASE_REPO_BRANCH,
		relative_path,
	]
	var result := _request_json_from_url(url, ["User-Agent: DTManager"])
	if(!bool(result.get("ok", false))):
		return Util.Stats.new(false, str(result.get("message", tr("error.database_sync_failed"))))
	if(typeof(result.get("data", null)) != TYPE_DICTIONARY):
		return Util.Stats.new(false, tr("error.database_tree_invalid"))
	return Util.Stats.new(true, tr("status.ok"), result.get("data", {}))

func _request_url(url: String, headers: PackedStringArray = [], redirect_count: int = 0) -> Dictionary:
	if(redirect_count > 5):
		return {"ok": false, "message": tr("error.http_request_failed")}

	var url_info := _parse_url(url)
	if(url_info.is_empty()):
		return {"ok": false, "message": tr("error.http_request_failed")}

	var client := HTTPClient.new()
	var tls_options = TLSOptions.client() if bool(url_info.get("https", false)) else null
	var connect_error := client.connect_to_host(str(url_info.get("host", "")), int(url_info.get("port", 0)), tls_options)
	if(connect_error != OK):
		return {"ok": false, "message": tr("error.http_request_failed")}

	while client.get_status() == HTTPClient.STATUS_RESOLVING || client.get_status() == HTTPClient.STATUS_CONNECTING:
		client.poll()
	if(client.get_status() != HTTPClient.STATUS_CONNECTED):
		return {"ok": false, "message": tr("error.http_request_failed")}

	var request_error := client.request(HTTPClient.METHOD_GET, str(url_info.get("path", "/")), headers)
	if(request_error != OK):
		return {"ok": false, "message": tr("error.http_request_failed")}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()

	if(client.get_status() != HTTPClient.STATUS_BODY && !client.has_response()):
		return {"ok": false, "message": tr("error.http_request_failed")}

	var response_code := client.get_response_code()
	var response_headers := client.get_response_headers_as_dictionary()
	if(response_code >= 300 && response_code < 400):
		var location := str(response_headers.get("Location", response_headers.get("location", "")))
		if(location.is_empty()):
			return {"ok": false, "message": tr("error.http_request_failed")}
		return _request_url(location, headers, redirect_count + 1)
	if(response_code < 200 || response_code >= 300):
		return {"ok": false, "message": tr("error.http_request_failed")}

	var body := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if(chunk.is_empty()):
			continue
		body.append_array(chunk)

	return {"ok": true, "body": body}

func _directory_has_entries(path: String) -> bool:
	if(!DirAccess.dir_exists_absolute(path)):
		return false
	return !DirAccess.get_files_at(path).is_empty() || !DirAccess.get_directories_at(path).is_empty()

func _is_safe_directory_target(path: String) -> bool:
	var normalized := path.replace("\\", "/").trim_suffix("/")
	if(normalized.is_empty() || normalized == "." || normalized == "/"):
		return false
	var drive_root_regex := RegEx.new()
	if(drive_root_regex.compile("^[A-Za-z]:$") == OK && drive_root_regex.search(normalized) != null):
		return false
	return true

func _database_game_has_manifest(game_data: Dictionary, manifest_id: String) -> bool:
	var manifests = game_data.get("manifests", [])
	if(typeof(manifests) != TYPE_ARRAY):
		return false
	for entry in manifests:
		if(typeof(entry) != TYPE_DICTIONARY):
			continue
		if(str(entry.get("manifest_id", "")) == manifest_id):
			return true
	return false

func _json_number_to_string(value) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return str(int(value))
		TYPE_INT:
			return str(value)
		_:
			return str(value).strip_edges()

func _patcher_install_dir(patcher_name: String) -> String:
	match patcher_name.to_lower():
		"godotdelta":
			return PatcherPath.path_join("GodotDelta")
		"depotdownloader":
			return PatcherPath.path_join("DepotDownloader")
		_:
			return PatcherPath.path_join(patcher_name)

func _resolve_extracted_root(extract_dir: String) -> String:
	var directories := DirAccess.get_directories_at(extract_dir)
	var files := DirAccess.get_files_at(extract_dir)
	if(files.is_empty() && directories.size() == 1):
		return extract_dir.path_join(directories[0])
	return extract_dir

func _parse_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	if(regex.compile("^https?://([^/:]+)(?::(\\d+))?(/.*)?$") != OK):
		return {}
	var match := regex.search(url)
	if(match == null):
		return {}
	var https := url.begins_with("https://")
	return {
		"https": https,
		"host": match.get_string(1),
		"port": int(match.get_string(2)) if !match.get_string(2).is_empty() else (443 if https else 80),
		"path": "/" if match.get_string(3).is_empty() else match.get_string(3),
	}


func _find_file_name_by_basename(parent_dir: String, basename: String) -> String:
	for file_name in DirAccess.get_files_at(parent_dir):
		if(file_name.get_basename() == basename):
			return file_name
	return ""


func _find_file_path_by_basename_recursive(root_dir: String, basename: String, extension: String = "") -> String:
	for file_name in DirAccess.get_files_at(root_dir):
		if(file_name.get_basename() != basename):
			continue
		if(!extension.is_empty() && !file_name.to_lower().ends_with(extension)):
			continue
		return root_dir.path_join(file_name)

	for directory_name in DirAccess.get_directories_at(root_dir):
		var nested_result := _find_file_path_by_basename_recursive(root_dir.path_join(directory_name), basename, extension)
		if(!nested_result.is_empty()):
			return nested_result

	return ""

func _kill_process_by_name(executable_name: String) -> Util.Stats:
	if(!OS.has_feature("windows")):
		return Util.Stats.new(true, tr("status.ok"))
	var output: Array = []
	var exit_code := OS.execute("cmd", ["/c", "taskkill", "/IM", executable_name, "/F"], output, true, false)
	if(exit_code != 0):
		var joined_output := "\n".join(output).to_lower()
		if(joined_output.contains("not found") || joined_output.contains("no running instance")):
			return Util.Stats.new(true, tr("status.ok"))
		return Util.Stats.new(false, tr("error.failed_to_kill_running_game"))
	return Util.Stats.new(true, tr("status.ok"))

func _is_process_running_by_name(executable_name: String) -> bool:
	if(!OS.has_feature("windows")):
		return false
	var output: Array = []
	var exit_code := OS.execute("cmd", ["/c", "tasklist", "/FI", "IMAGENAME eq " + executable_name], output, true, false)
	if(exit_code != 0):
		return false
	return "\n".join(output).to_lower().contains(executable_name.to_lower())

func _detect_steam_install(source_dir: String) -> Dictionary:
	var normalized_source := source_dir.replace("\\", "/").trim_suffix("/")
	var source_parts := normalized_source.split("/")
	var steamapps_index := source_parts.find("steamapps")
	if(steamapps_index == -1):
		return {}
	if(steamapps_index + 1 >= source_parts.size() || source_parts[steamapps_index + 1] != "common"):
		return {}

	var steamapps_dir := "/".join(source_parts.slice(0, steamapps_index + 1))
	var install_dir_name := source_dir.get_file()
	for file_name in DirAccess.get_files_at(steamapps_dir):
		if(!file_name.begins_with("appmanifest_") || !file_name.ends_with(".acf")):
			continue
		var app_id := file_name.trim_prefix("appmanifest_").trim_suffix(".acf")
		if(app_id.is_empty()):
			continue
		var manifest_info := _read_steam_manifest(steamapps_dir.path_join(file_name))
		if(manifest_info.is_empty()):
			continue
		if(str(manifest_info.get("installdir", "")) != install_dir_name):
			continue
		return {
			"steam_uri": "steam://run/" + app_id,
			"steam_game_path": source_dir,
		}
	return {}

func _read_steam_manifest(path: String) -> Dictionary:
	if(!FileAccess.file_exists(path)):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if(file == null):
		return {}
	var result := {}
	var regex := RegEx.new()
	var compile_error := regex.compile('^\\s*"([^"]+)"\\s*"([^"]*)"\\s*$')
	if(compile_error != OK):
		return {}
	while !file.eof_reached():
		var line := file.get_line()
		var match := regex.search(line)
		if(match == null):
			continue
		result[match.get_string(1)] = match.get_string(2)
	return result
