extends Node

const CONFIG_NAME := "config.dm";
const APP_CONFIG_NAME := "app_config.dm";
const MOD_METADATA_NAME := "DTManager.mod.json";
const THUMBNAIL_NAME := "thumbnail.dm.png";
const RUNTIME_STATE_NAME := "runtime_state.dm";
const TEMP_PREFIX := "__tmp__";
const RESTORE_DELAY_AFTER_KILL_MS := 1500;

var GamePath: String
var ModPath: String
var RunPath: String
var PatcherPath: String
var FilesPath: String
var SavePath: String
var VersionPath: String
var RuntimeStatePath: String
var AppConfigPath: String

func _init() -> void:
	var base_dir := get_root_path()
	FilesPath = base_dir.path_join("Files")
	GamePath = base_dir.path_join("Game")
	ModPath = base_dir.path_join("Mod")
	RunPath = base_dir.path_join("Run")
	PatcherPath = base_dir.path_join("Patcher")
	SavePath = FilesPath.path_join("GameSave")
	VersionPath = FilesPath.path_join("GameVersions")
	RuntimeStatePath = base_dir.path_join(RUNTIME_STATE_NAME)
	AppConfigPath = base_dir.path_join(APP_CONFIG_NAME)
	ensure_directory(FilesPath)
	ensure_directory(GamePath)
	ensure_directory(ModPath)
	ensure_directory(RunPath)
	ensure_directory(SavePath)
	ensure_directory(VersionPath)

func get_game_thumbnail_path(g_name: String) -> String:
	return GamePath.path_join(g_name).path_join(THUMBNAIL_NAME);

func get_mod_thumbnail_path(g_name: String, m_name) -> String:
	return ModPath.path_join(g_name).path_join(m_name).path_join(THUMBNAIL_NAME);

func get_root_path() -> String:
	if(OS.has_feature("editor")):
		return ProjectSettings.globalize_path("res://../output")
	return OS.get_executable_path().get_base_dir()

func _apply_default_game_config(config: Dictionary, app_id: String) -> void:
	if(app_id.is_empty()): return;
	var defaults_result := _load_default_game_database()
	if(!defaults_result.ok): return;
	if(typeof(defaults_result.data.get(app_id, null)) != TYPE_DICTIONARY): return;
	var defaults: Dictionary = defaults_result.data.get(app_id, {})
	for key in defaults.keys():
		if(key in ["name", "run_path", "steam_uri", "steam_game_path"]): continue;
		config[str(key)] = _expand_env_vars(defaults[key]);

func _expand_env_vars(value):
	if(typeof(value) != TYPE_STRING): return value;
	var text := str(value)
	var regex := RegEx.new()
	if(regex.compile("%([^%]+)%") != OK): return text;
	var result := text
	var matches := regex.search_all(text)
	for match in matches:
		var env_name := match.get_string(1)
		var env_value := OS.get_environment(env_name)
		if(env_value.is_empty()):
			env_value = OS.get_environment(env_name.to_upper())
		if(env_value.is_empty()):
			env_value = OS.get_environment(env_name.to_lower())
		if(env_value.is_empty()): continue;
		result = result.replace(match.get_string(0), env_value)
	return result

func addGame(path: String, g_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, "error.executable_file_not_found")

	var source_dir := path.get_base_dir()
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, "error.game_directory_not_found")

	var game_dir := _game_dir(g_name)
	if(DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, "error.game_already_exists")

	var copy_result := copy_directory(source_dir, game_dir)
	if(!copy_result.ok): return copy_result;

	var run_path := _relative_path(source_dir, path)
	var config := {
		"name": g_name,
		"run_path": run_path,
		"save_path": "",
		"use_steam_launch": false,
	}
	var steam_info := Steam.detect_install(source_dir)
	if(!steam_info.is_empty()):
		_apply_detected_steam_config(config, steam_info)
		config["use_steam_launch"] = true
		var app_id := str(config["app_id"]).strip_edges()
		_apply_default_game_config(config, app_id)

	var config_result := _write_json(game_dir.path_join(CONFIG_NAME), config)
	if(!config_result.ok): return config_result;

	return Util.Stats.new(true, "status.game_added_successfully", config)

func addMod(g_name: String, path: String, m_name: String, base_mod_name: String = "") -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(m_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.mod_name_empty")
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, "error.mod_zip_file_not_found")

	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, "error.game_directory_not_found")

	var mod_dir := _mod_dir(g_name, m_name)
	if(DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, "error.mod_already_exists")

	var patch_base_dir := game_dir
	var patch_base_temp_dir := ""
	var reference_base_dir := game_dir
	var inherited_metadata := {}
	if(!base_mod_name.strip_edges().is_empty()):
		Util.set_loading_status("Preparing base mod files...")
		var base_mod_dir := _mod_dir(g_name, base_mod_name)
		if(!DirAccess.dir_exists_absolute(base_mod_dir)):
			return Util.Stats.new(false, "error.mod_does_not_exist")
		var base_mod_config_result := load_mod_config(g_name, base_mod_name)
		if(!base_mod_config_result.ok):
			return base_mod_config_result
		inherited_metadata = base_mod_config_result.data.duplicate()
		var reference_base_result := _resolve_metadata_base_dir(g_name, inherited_metadata, game_dir)
		if(!reference_base_result.ok):
			return reference_base_result
		reference_base_dir = str(reference_base_result.data.get("base_dir", game_dir))
		patch_base_temp_dir = temp_dir("mod_base_" + g_name + "_" + m_name)
		delete_directory_if_exists(patch_base_temp_dir)
		var base_copy_result := copy_directory(reference_base_dir, patch_base_temp_dir)
		if(!base_copy_result.ok):
			return base_copy_result
		var base_merge_result := merge_directory_without_configs(base_mod_dir, patch_base_temp_dir)
		if(!base_merge_result.ok):
			delete_directory_if_exists(patch_base_temp_dir)
			return base_merge_result
		patch_base_dir = patch_base_temp_dir

	var extract_dir := temp_dir("mod_extract_" + g_name + "_" + m_name)
	delete_directory_if_exists(extract_dir)
	Util.set_loading_status("Extracting mod archive...")
	var extract_result := extract_zip(path, extract_dir)
	if(!extract_result.ok):
		delete_directory_if_exists(patch_base_temp_dir)
		return extract_result

	var package_metadata := _read_package_metadata(extract_dir)
	var effective_metadata := inherited_metadata.duplicate()
	for key in ["app_id", "manifest_id", "branch"]:
		if(package_metadata.has(key)):
			effective_metadata[key] = package_metadata[key]
	if(base_mod_name.strip_edges().is_empty()):
		var metadata_base_dir := _resolve_metadata_base_dir(g_name, package_metadata)
		if(!metadata_base_dir.ok):
			delete_directory_if_exists(extract_dir)
			delete_directory_if_exists(patch_base_temp_dir)
			return metadata_base_dir
		if(!str(metadata_base_dir.data.get("base_dir", "")).is_empty()):
			patch_base_dir = str(metadata_base_dir.data.get("base_dir", ""))
			reference_base_dir = patch_base_dir

	var xdelta_files := collect_files_with_extension(extract_dir, ".xdelta")
	var pck_files := collect_files_with_extension(extract_dir, ".pck")
	var build_result := Util.Stats.new(false, "error.unknown")
	var patch_output_dir := mod_dir if base_mod_name.strip_edges().is_empty() else temp_dir("mod_build_" + g_name + "_" + m_name)
	if(base_mod_name.strip_edges().is_empty() == false):
		delete_directory_if_exists(patch_output_dir)

	if(!xdelta_files.is_empty()):
		Util.set_loading_status("Applying xdelta patches...")
		build_result = _build_xdelta_mod(patch_base_dir, extract_dir, xdelta_files, patch_output_dir)
	elif(!pck_files.is_empty()):
		var patcher_result := Steam.ensure_patchers()
		if(!patcher_result.ok):
			delete_directory_if_exists(extract_dir)
			delete_directory_if_exists(patch_base_temp_dir)
			return patcher_result
		build_result = _build_gddelta_mod(g_name, patch_base_dir, extract_dir, pck_files, patch_output_dir, m_name)
	else:
		Util.set_loading_status("Copying mod files...")
		build_result = copy_directory(extract_dir, patch_output_dir)

	if(build_result.ok && !base_mod_name.strip_edges().is_empty()):
		if(!xdelta_files.is_empty() || pck_files.is_empty()):
			var merge_patch_result := merge_directory_without_configs(patch_output_dir, patch_base_temp_dir)
			if(!merge_patch_result.ok):
				build_result = merge_patch_result
			else:
				delete_directory_if_exists(patch_output_dir)
				build_result = _copy_changed_files(reference_base_dir, patch_base_temp_dir, mod_dir)
		else:
			build_result = _copy_changed_files(reference_base_dir, patch_output_dir, mod_dir)

	delete_directory_if_exists(extract_dir)
	delete_directory_if_exists(patch_base_temp_dir)
	if(!base_mod_name.strip_edges().is_empty()):
		delete_directory_if_exists(patch_output_dir)
	if(!build_result.ok):
		delete_directory_if_exists(mod_dir)
		return build_result

	var config_result := _write_json(mod_dir.path_join(CONFIG_NAME), _mod_config_data(g_name, m_name, effective_metadata))
	if(!config_result.ok):
		delete_directory_if_exists(mod_dir)
		return config_result

	return Util.Stats.new(true, "status.mod_added_successfully", {
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
	if(!DirAccess.dir_exists_absolute(game_mod_root)): return mods;

	for mod_name in DirAccess.get_directories_at(game_mod_root):
		var config_result := load_mod_config(g_name, mod_name)
		if(config_result.ok): mods.append(config_result.data);
	return mods

func load_game_config(g_name: String) -> Util.Stats:
	return _read_json(_game_dir(g_name).path_join(CONFIG_NAME))

func save_game_config(g_name: String, config: Dictionary) -> Util.Stats:
	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, "error.game_does_not_exist")
	return _write_json(game_dir.path_join(CONFIG_NAME), config)

func load_app_config() -> Util.Stats:
	if(!FileAccess.file_exists(AppConfigPath)):
		return Util.Stats.new(true, "status.ok", {})
	return _read_json(AppConfigPath)

func save_app_config(config: Dictionary) -> Util.Stats:
	return _write_json(AppConfigPath, config)

func load_mod_config(g_name: String, m_name: String) -> Util.Stats:
	return _read_json(_mod_dir(g_name, m_name).path_join(CONFIG_NAME))

func get_manifest_cache_dir(app_id: String, manifest_id: String) -> String:
	return VersionPath.path_join(app_id).path_join(manifest_id)

func resolve_game_base_dir(game_name: String, mod_name: String = "") -> Util.Stats:
	var base_dir := _game_dir(game_name)
	if(mod_name.strip_edges().is_empty()):
		return Util.Stats.new(true, "status.ok", {"base_dir": base_dir})
	var mod_config_result := load_mod_config(game_name, mod_name)
	if(!mod_config_result.ok):
		return mod_config_result
	return _resolve_metadata_base_dir(game_name, mod_config_result.data, base_dir)

func save_mod_config(g_name: String, m_name: String, config: Dictionary) -> Util.Stats:
	var mod_dir := _mod_dir(g_name, m_name)
	if(!DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, "error.mod_does_not_exist")
	return _write_json(mod_dir.path_join(CONFIG_NAME), config)

func get_game_save_root(g_name: String) -> String:
	return SavePath.path_join(g_name)

func get_game_save_slot_dir(g_name: String, slot_name: String) -> String:
	return get_game_save_root(g_name).path_join(slot_name)

func list_save_slots(g_name: String) -> Array[String]:
	var slots_root := get_game_save_root(g_name)
	if(!DirAccess.dir_exists_absolute(slots_root)): return [];
	var result: Array[String] = []
	for slot_name in DirAccess.get_directories_at(slots_root):
		result.append(slot_name)
	result.sort()
	return result

func backup_save_slot(g_name: String, slot_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	var game_config_result := load_game_config(g_name)
	if(!game_config_result.ok):
		return game_config_result
	var save_source_dir := str(game_config_result.data.get("save_path", "")).strip_edges()
	if(save_source_dir.is_empty()):
		return Util.Stats.new(false, "error.save_path_empty")
	if(!DirAccess.dir_exists_absolute(save_source_dir)):
		return Util.Stats.new(false, "error.save_directory_not_found")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	delete_directory_if_exists(slot_dir)
	return copy_directory(save_source_dir, slot_dir)

func restore_save_slot(g_name: String, slot_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	var game_config_result := load_game_config(g_name)
	if(!game_config_result.ok):
		return game_config_result
	var save_target_dir := str(game_config_result.data.get("save_path", "")).strip_edges()
	if(save_target_dir.is_empty()):
		return Util.Stats.new(false, "error.save_path_empty")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	if(!DirAccess.dir_exists_absolute(slot_dir)):
		return Util.Stats.new(false, "error.save_slot_not_found")
	ensure_directory(save_target_dir)
	delete_directory_contents(save_target_dir)
	return copy_directory(slot_dir, save_target_dir)

func rename_save_slot(g_name: String, old_name: String, new_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(old_name.strip_edges().is_empty() || new_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	if(old_name == new_name):
		return Util.Stats.new(true, "status.ok")
	var slot_dir := get_game_save_slot_dir(g_name, old_name)
	if(!DirAccess.dir_exists_absolute(slot_dir)):
		return Util.Stats.new(false, "error.save_slot_not_found")
	var target_dir := get_game_save_slot_dir(g_name, new_name)
	if(DirAccess.dir_exists_absolute(target_dir)):
		return Util.Stats.new(false, "error.save_slot_already_exists")
	var rename_error := DirAccess.rename_absolute(slot_dir, target_dir)
	if(rename_error != OK):
		return Util.Stats.new(false, "error.failed_to_rename_directory")
	return Util.Stats.new(true, "status.ok")

func delete_save_slot(g_name: String, slot_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	if(!DirAccess.dir_exists_absolute(slot_dir)):
		return Util.Stats.new(false, "error.save_slot_not_found")
	delete_directory_if_exists(slot_dir)
	return Util.Stats.new(true, "status.ok")

func export_save_slot(g_name: String, slot_name: String, destination_dir: String) -> Util.Stats:
	if(destination_dir.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.export_directory_empty")
	if(!DirAccess.dir_exists_absolute(destination_dir)):
		return Util.Stats.new(false, "error.export_directory_not_found")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	if(!DirAccess.dir_exists_absolute(slot_dir)):
		return Util.Stats.new(false, "error.save_slot_not_found")
	var export_dir := destination_dir.path_join("%s_%s" % [g_name, slot_name])
	delete_directory_if_exists(export_dir)
	return copy_directory(slot_dir, export_dir)

func import_save_slot(g_name: String, slot_name: String, source_dir: String) -> Util.Stats:
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	if(source_dir.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.import_directory_empty")
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, "error.import_directory_not_found")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	delete_directory_if_exists(slot_dir)
	return copy_directory(source_dir, slot_dir)

func export_save_slot_zip(g_name: String, slot_name: String, zip_path: String) -> Util.Stats:
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	if(zip_path.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_zip_path_empty")
	var slot_dir := get_game_save_slot_dir(g_name, slot_name)
	if(!DirAccess.dir_exists_absolute(slot_dir)):
		return Util.Stats.new(false, "error.save_slot_not_found")
	ensure_directory(zip_path.get_base_dir())
	if(FileAccess.file_exists(zip_path)):
		DirAccess.remove_absolute(zip_path)
	return _create_zip_from_directory(slot_dir, zip_path)

func import_save_slot_zip(g_name: String, slot_name: String, zip_path: String) -> Util.Stats:
	if(slot_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_slot_name_empty")
	if(zip_path.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.save_zip_path_empty")
	if(!FileAccess.file_exists(zip_path)):
		return Util.Stats.new(false, "error.save_zip_file_not_found")
	var temp_extract_dir := temp_dir("save_zip_" + g_name + "_" + slot_name)
	delete_directory_if_exists(temp_extract_dir)
	var extract_result := extract_zip(zip_path, temp_extract_dir)
	if(!extract_result.ok): return extract_result;
	var import_source_dir := _resolve_import_root_dir(temp_extract_dir)
	var import_result := import_save_slot(g_name, slot_name, import_source_dir)
	delete_directory_if_exists(temp_extract_dir)
	return import_result

func save_thumbnail(target_path: String, image_path: String) -> Util.Stats:
	if(image_path.strip_edges().is_empty()):
		return Util.Stats.new(true, "status.ok")
	if(!FileAccess.file_exists(image_path)):
		return Util.Stats.new(false, "error.thumbnail_file_not_found")
	var target_dir := target_path.get_base_dir()
	if(!DirAccess.dir_exists_absolute(target_dir)):
		return Util.Stats.new(false, "error.source_directory_not_found")
	if(FileAccess.file_exists(target_path)):
		DirAccess.remove_absolute(target_path)
	var copy_error := DirAccess.copy_absolute(image_path, target_path)
	if(copy_error != OK):
		return Util.Stats.new(false, "error.failed_to_copy_thumbnail")
	return Util.Stats.new(true, "status.ok")

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
		return Util.Stats.new(true, "status.ok")

	var state_result := load_runtime_state()
	if(!state_result.ok): return state_result;

	var steam_game_path := str(state_result.data.get("steam_game_path", ""))
	var backup_dir := str(state_result.data.get("backup_dir", ""))
	var phase := str(state_result.data.get("phase", ""))
	var executable_name := str(state_result.data.get("executable_name", ""))
	if(steam_game_path.is_empty() || backup_dir.is_empty()):
		clear_runtime_state()
		return Util.Stats.new(false, "error.runtime_state_invalid")
	if(!DirAccess.dir_exists_absolute(backup_dir)):
		clear_runtime_state()
		return Util.Stats.new(false, "error.runtime_backup_not_found")
	if(force_kill_running && phase == "launched" && !executable_name.is_empty()):
		var kill_result := _kill_process_by_name(executable_name)
		if(!kill_result.ok): return kill_result;
		OS.delay_msec(RESTORE_DELAY_AFTER_KILL_MS)

	delete_directory_contents(steam_game_path)
	var restore_result := copy_directory(backup_dir, steam_game_path)
	if(!restore_result.ok):
		return Util.Stats.new(false, "error.failed_to_restore_steam_backup")
	delete_directory_if_exists(backup_dir)
	clear_runtime_state()
	return Util.Stats.new(true, "status.ok")

func copy_directory(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, false)

func merge_directory(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, true)

func merge_directory_without_configs(source_dir: String, destination_dir: String) -> Util.Stats:
	return _copy_directory_internal(source_dir, destination_dir, true, [CONFIG_NAME])

func extract_zip(zip_path: String, destination_dir: String) -> Util.Stats:
	ensure_directory(destination_dir)
	var zip_reader := ZIPReader.new()
	var open_error := zip_reader.open(zip_path)
	if(open_error != OK):
		return Util.Stats.new(false, "error.failed_to_open_zip")

	for entry_path in zip_reader.get_files():
		var normalized := entry_path.trim_prefix("/")
		if(normalized.ends_with("/")):
			ensure_directory(destination_dir.path_join(normalized))
			continue;
		var output_path := destination_dir.path_join(normalized)
		ensure_directory(output_path.get_base_dir())
		var bytes := zip_reader.read_file(entry_path)
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if(file == null):
			zip_reader.close()
			return Util.Stats.new(false, "error.failed_to_write_extracted_file")
		file.store_buffer(bytes)

	zip_reader.close()
	return Util.Stats.new(true, "ok")

func _create_zip_from_directory(source_dir: String, zip_path: String) -> Util.Stats:
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, "error.source_directory_not_found")
	var zip_packer := ZIPPacker.new()
	var open_error := zip_packer.open(zip_path)
	if(open_error != OK):
		return Util.Stats.new(false, "error.failed_to_create_zip")
	var pack_result := _pack_directory_into_zip(zip_packer, source_dir, source_dir)
	zip_packer.close()
	return pack_result

func _pack_directory_into_zip(zip_packer: ZIPPacker, root_dir: String, current_dir: String) -> Util.Stats:
	for directory_name in DirAccess.get_directories_at(current_dir):
		var nested_dir := current_dir.path_join(directory_name)
		var nested_result := _pack_directory_into_zip(zip_packer, root_dir, nested_dir)
		if(!nested_result.ok):
			return nested_result
	for file_name in DirAccess.get_files_at(current_dir):
		var source_file := current_dir.path_join(file_name)
		var relative_path := _relative_path(root_dir, source_file).trim_prefix("/").trim_prefix("\\")
		var start_error := zip_packer.start_file(relative_path)
		if(start_error != OK):
			return Util.Stats.new(false, "error.failed_to_create_zip")
		zip_packer.write_file(FileAccess.get_file_as_bytes(source_file))
		zip_packer.close_file()
	return Util.Stats.new(true, "status.ok")

func _resolve_import_root_dir(path: String) -> String:
	var files := DirAccess.get_files_at(path)
	var directories := DirAccess.get_directories_at(path)
	if(files.is_empty() && directories.size() == 1): return path.path_join(directories[0]);
	return path

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
		return Util.Stats.new(false, "error.game_does_not_exist")
	delete_directory_if_exists(ModPath.path_join(g_name))
	delete_directory_if_exists(game_dir)
	return Util.Stats.new(true, "status.game_deleted")

func reimport_game(g_name: String, executable_path: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(!FileAccess.file_exists(executable_path)):
		return Util.Stats.new(false, "error.executable_file_not_found")

	var game_dir := _game_dir(g_name)
	if(!DirAccess.dir_exists_absolute(game_dir)):
		return Util.Stats.new(false, "error.game_does_not_exist")
	var source_dir := executable_path.get_base_dir()
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, "error.game_directory_not_found")

	var config_result := load_game_config(g_name)
	if(!config_result.ok): return config_result;
	var config: Dictionary = config_result.data.duplicate(true)

	var thumbnail_path := get_game_thumbnail_path(g_name)
	var thumbnail_backup_path := ""
	if(FileAccess.file_exists(thumbnail_path)):
		thumbnail_backup_path = temp_dir("reimport_thumbnail_" + g_name + "_" + THUMBNAIL_NAME)
		if(FileAccess.file_exists(thumbnail_backup_path)):
			DirAccess.remove_absolute(thumbnail_backup_path)
		var thumbnail_copy_error := DirAccess.copy_absolute(thumbnail_path, thumbnail_backup_path)
		if(thumbnail_copy_error != OK):
			return Util.Stats.new(false, "error.failed_to_copy_thumbnail")

	var import_dir := temp_dir("reimport_game_" + g_name)
	delete_directory_if_exists(import_dir)
	var copy_result := copy_directory(source_dir, import_dir)
	if(!copy_result.ok):
		_cleanup_reimport_temp_paths(import_dir, thumbnail_backup_path)
		return copy_result

	delete_directory_contents(game_dir)
	var merge_result := merge_directory(import_dir, game_dir)
	if(!merge_result.ok):
		_cleanup_reimport_temp_paths(import_dir, thumbnail_backup_path)
		return merge_result
	delete_directory_if_exists(import_dir)

	config["name"] = g_name
	config["run_path"] = _relative_path(source_dir, executable_path)
	config.erase("app_id")
	config.erase("steam_uri")
	config.erase("steam_game_path")
	config.erase("installed_manifest_id")
	var steam_info := Steam.detect_install(source_dir)
	if(!steam_info.is_empty()):
		_apply_detected_steam_config(config, steam_info)

	var save_result := save_game_config(g_name, config)
	if(!save_result.ok):
		_cleanup_reimport_temp_paths("", thumbnail_backup_path)
		return save_result
	if(FileAccess.file_exists(thumbnail_backup_path)):
		var restore_error := DirAccess.copy_absolute(thumbnail_backup_path, thumbnail_path)
		DirAccess.remove_absolute(thumbnail_backup_path)
		if(restore_error != OK):
			return Util.Stats.new(false, "error.failed_to_copy_thumbnail")
	return Util.Stats.new(true, "status.game_added_successfully", config)

func _cleanup_reimport_temp_paths(import_dir: String, thumbnail_backup_path: String) -> void:
	if(!import_dir.is_empty()):
		delete_directory_if_exists(import_dir)
	if(FileAccess.file_exists(thumbnail_backup_path)):
		DirAccess.remove_absolute(thumbnail_backup_path)

func _apply_detected_steam_config(config: Dictionary, steam_info: Dictionary) -> void:
	config["app_id"] = str(steam_info.get("app_id", ""))
	config["steam_uri"] = str(steam_info.get("steam_uri", ""))
	config["steam_game_path"] = str(steam_info.get("steam_game_path", ""))
	config["installed_manifest_id"] = str(steam_info.get("installed_manifest_id", "")).strip_edges()

func delete_mod(g_name: String, m_name: String) -> Util.Stats:
	var mod_dir := _mod_dir(g_name, m_name)
	if(!DirAccess.dir_exists_absolute(mod_dir)):
		return Util.Stats.new(false, "error.mod_does_not_exist")
	delete_directory_if_exists(mod_dir)
	return Util.Stats.new(true, "status.mod_deleted")

func rename_game(old_name: String, new_name: String) -> Util.Stats:
	if(old_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(new_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.rename_name_empty")
	if(old_name == new_name):
		return Util.Stats.new(true, "status.ok", {"name": new_name})

	var old_game_dir := _game_dir(old_name)
	var new_game_dir := _game_dir(new_name)
	if(!DirAccess.dir_exists_absolute(old_game_dir)):
		return Util.Stats.new(false, "error.game_does_not_exist")
	if(DirAccess.dir_exists_absolute(new_game_dir)):
		return Util.Stats.new(false, "error.game_already_exists")

	var old_mod_root := ModPath.path_join(old_name)
	var new_mod_root := ModPath.path_join(new_name)
	if(DirAccess.dir_exists_absolute(new_mod_root)):
		return Util.Stats.new(false, "error.game_already_exists")

	var moved_mod_root := false
	if(DirAccess.dir_exists_absolute(old_mod_root)):
		var move_mod_error := DirAccess.rename_absolute(old_mod_root, new_mod_root)
		if(move_mod_error != OK):
			return Util.Stats.new(false, "error.failed_to_rename_directory")
		moved_mod_root = true

	var move_game_error := DirAccess.rename_absolute(old_game_dir, new_game_dir)
	if(move_game_error != OK):
		if(moved_mod_root):
			DirAccess.rename_absolute(new_mod_root, old_mod_root)
		return Util.Stats.new(false, "error.failed_to_rename_directory")

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

	return Util.Stats.new(true, "status.game_renamed", {"name": new_name})

func rename_mod(g_name: String, old_name: String, new_name: String) -> Util.Stats:
	if(g_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.game_name_empty")
	if(old_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.mod_name_empty")
	if(new_name.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.rename_name_empty")
	if(old_name == new_name):
		return Util.Stats.new(true, "status.ok", {"name": new_name})

	var old_mod_dir := _mod_dir(g_name, old_name)
	var new_mod_dir := _mod_dir(g_name, new_name)
	if(!DirAccess.dir_exists_absolute(old_mod_dir)):
		return Util.Stats.new(false, "error.mod_does_not_exist")
	if(DirAccess.dir_exists_absolute(new_mod_dir)):
		return Util.Stats.new(false, "error.mod_already_exists")

	var move_error := DirAccess.rename_absolute(old_mod_dir, new_mod_dir)
	if(move_error != OK):
		return Util.Stats.new(false, "error.failed_to_rename_directory")

	var mod_config_result := load_mod_config(g_name, new_name)
	if(!mod_config_result.ok):
		return mod_config_result
	var mod_config := mod_config_result.data
	mod_config["name"] = new_name
	var save_result := _write_json(new_mod_dir.path_join(CONFIG_NAME), mod_config)
	if(!save_result.ok): return save_result;
	return Util.Stats.new(true, "status.mod_renamed", {"name": new_name})

func clear_run_directory() -> void:
	delete_directory_contents(RunPath)

func _build_xdelta_mod(base_dir: String, extract_dir: String, patch_files: Array[String], mod_dir: String) -> Util.Stats:
	ensure_directory(mod_dir)
	var override_result := _copy_override_files(extract_dir, mod_dir, [".xdelta", ".pck"])
	if(!override_result.ok): return override_result;

	for index in range(patch_files.size()):
		var relative_path := patch_files[index]
		Util.set_loading_status("Applying xdelta patch %d/%d..." % [index + 1, patch_files.size()])
		var patch_file := extract_dir.path_join(relative_path)
		var target_relative := _resolve_xdelta_target_relative(base_dir, relative_path)
		if(target_relative.is_empty()):
			return Util.Stats.new(false, "error.xdelta_base_file_not_found")
		var source_target_file := base_dir.path_join(target_relative)
		var output_target_file := mod_dir.path_join(target_relative)
		ensure_directory(output_target_file.get_base_dir())
		var patch_result := _apply_single_xdelta(patch_file, source_target_file, output_target_file)
		if(!patch_result.ok):
			return patch_result

	return Util.Stats.new(true, "status.ok")

func _resolve_xdelta_target_relative(root_dir: String, relative_patch_path: String) -> String:
	var relative_without_xdelta := relative_patch_path.substr(0, relative_patch_path.length() - ".xdelta".length())
	var direct_target := root_dir.path_join(relative_without_xdelta)
	if(FileAccess.file_exists(direct_target)): return relative_without_xdelta;

	var parent_relative := relative_without_xdelta.get_base_dir()
	var parent_dir := root_dir if parent_relative == "." else root_dir.path_join(parent_relative)
	if(!DirAccess.dir_exists_absolute(parent_dir)): return "";

	var basename := relative_without_xdelta.get_file()
	var matched_file := _find_file_name_by_basename(parent_dir, basename)
	if(matched_file.is_empty()): return "";
	return matched_file if parent_relative == "." else parent_relative.path_join(matched_file)

func _build_gddelta_mod(g_name: String, base_dir: String, extract_dir: String, patch_files: Array[String], mod_dir: String, m_name: String) -> Util.Stats:
	var game_config := load_game_config(g_name)
	if(!game_config.ok): return game_config;

	var run_path := str(game_config.data.get("run_path", "")).trim_prefix("/").trim_prefix("\\")
	if(run_path.is_empty()):
		return Util.Stats.new(false, "error.game_run_path_empty")

	var current_executable := base_dir.path_join(run_path)
	if(!FileAccess.file_exists(current_executable)):
		return Util.Stats.new(false, "error.base_executable_not_found")

	var gddelta_path := resolve_gddelta_path()
	if(gddelta_path.is_empty()):
		return Util.Stats.new(false, "error.gddelta_executable_not_found")

	var stage_paths: Array[String] = []
	var patch_count := patch_files.size()

	for index in range(patch_count):
		Util.set_loading_status("Applying GodotDelta patch %d/%d..." % [index + 1, patch_count])
		var patch_file := extract_dir.path_join(patch_files[index])
		var patch_basename := patch_files[index].get_basename().get_file()
		var executable_root := base_dir if index == 0 else current_executable.get_base_dir()
		var matched_executable := _find_file_path_by_basename_recursive(executable_root, patch_basename, ".exe")
		if(!matched_executable.is_empty()):
			current_executable = matched_executable

		var output_dir := mod_dir
		if(index < patch_count - 1):
			output_dir = temp_dir("gddelta_stage_%s_%s_%d" % [g_name, m_name, index])
			delete_directory_if_exists(output_dir)
			stage_paths.append(output_dir)
		else:
			delete_directory_if_exists(mod_dir)

		var output: Array = []
		var exit_code := OS.execute(gddelta_path, ["apply", current_executable, patch_file, output_dir], output, true, false)
		if(exit_code != 0):
			for stage_path in stage_paths:
				delete_directory_if_exists(stage_path)
			return Util.Stats.new(false, Util.trans("error.gddelta_apply_failed") % ["\n".join(output)])

		current_executable = output_dir.path_join(run_path)
		if(!FileAccess.file_exists(current_executable)):
			for stage_path in stage_paths:
				delete_directory_if_exists(stage_path)
			return Util.Stats.new(false, "error.patched_executable_not_found")

	for stage_path in stage_paths:
		delete_directory_if_exists(stage_path)
	return Util.Stats.new(true, "status.ok")

func _apply_single_xdelta(patch_file: String, source_file: String, output_file: String) -> Util.Stats:
	if(!FileAccess.file_exists(source_file)):
		return Util.Stats.new(false, "error.xdelta_base_file_not_found")

	var xdelta_path := _resolve_xdelta_path()
	if(xdelta_path.is_empty()):
		return Util.Stats.new(false, "error.xdelta_executable_not_found")

	var output: Array = []
	var exit_code := OS.execute(xdelta_path, ["-d", "-s", source_file, patch_file, output_file], output, true, false)
	if(exit_code != 0):
		return Util.Stats.new(false, Util.trans("error.xdelta_apply_failed") % ["\n".join(output)])
	return Util.Stats.new(true, "status.ok")

func _copy_directory_internal(source_dir: String, destination_dir: String, overwrite: bool, excluded_files: Array[String] = []) -> Util.Stats:
	if(!DirAccess.dir_exists_absolute(source_dir)):
		return Util.Stats.new(false, "error.source_directory_not_found")
	ensure_directory(destination_dir)

	for directory_name in DirAccess.get_directories_at(source_dir):
		var nested_result := _copy_directory_internal(source_dir.path_join(directory_name), destination_dir.path_join(directory_name), overwrite, excluded_files)
		if(!nested_result.ok): return nested_result;

	for file_name in DirAccess.get_files_at(source_dir):
		if(file_name in excluded_files): continue;
		var source_file := source_dir.path_join(file_name)
		var destination_file := destination_dir.path_join(file_name)
		if(overwrite && FileAccess.file_exists(destination_file)):
			DirAccess.remove_absolute(destination_file)
		var copy_error := DirAccess.copy_absolute(source_file, destination_file)
		if(copy_error != OK):
			return Util.Stats.new(false, Util.trans("error.failed_to_copy_file") + ": " + source_file)

	return Util.Stats.new(true, "status.ok")

func _copy_override_files(source_dir: String, destination_dir: String, excluded_extensions: Array[String], relative_path: String = "") -> Util.Stats:
	var current_source_dir := source_dir if relative_path.is_empty() else source_dir.path_join(relative_path)
	for directory_name in DirAccess.get_directories_at(current_source_dir):
		var nested_relative := directory_name if relative_path.is_empty() else relative_path.path_join(directory_name)
		var nested_result := _copy_override_files(source_dir, destination_dir, excluded_extensions, nested_relative)
		if(!nested_result.ok): return nested_result;

	for file_name in DirAccess.get_files_at(current_source_dir):
		if(file_name == CONFIG_NAME || file_name == MOD_METADATA_NAME): continue;
		var skip := false
		for extension in excluded_extensions:
			if(file_name.to_lower().ends_with(extension)):
				skip = true
				break
		if(skip): continue;
		var file_relative := file_name if relative_path.is_empty() else relative_path.path_join(file_name)
		var destination_file := destination_dir.path_join(file_relative)
		ensure_directory(destination_file.get_base_dir())
		var copy_error := DirAccess.copy_absolute(current_source_dir.path_join(file_name), destination_file)
		if(copy_error != OK):
			return Util.Stats.new(false, Util.trans("error.failed_to_copy_override_file") + ": " + file_relative)

	return Util.Stats.new(true, "status.ok")

func _copy_changed_files(base_dir: String, result_dir: String, destination_dir: String, relative_path: String = "") -> Util.Stats:
	var current_result_dir := result_dir if relative_path.is_empty() else result_dir.path_join(relative_path)
	for directory_name in DirAccess.get_directories_at(current_result_dir):
		var nested_relative := directory_name if relative_path.is_empty() else relative_path.path_join(directory_name)
		var nested_result := _copy_changed_files(base_dir, result_dir, destination_dir, nested_relative)
		if(!nested_result.ok):
			return nested_result

	for file_name in DirAccess.get_files_at(current_result_dir):
		if(file_name == CONFIG_NAME || file_name == MOD_METADATA_NAME): continue;
		var file_relative := file_name if relative_path.is_empty() else relative_path.path_join(file_name)
		var result_file := result_dir.path_join(file_relative)
		var base_file := base_dir.path_join(file_relative)
		if(FileAccess.file_exists(base_file) && _files_match(base_file, result_file)): continue;
		var destination_file := destination_dir.path_join(file_relative)
		ensure_directory(destination_file.get_base_dir())
		if(FileAccess.file_exists(destination_file)):
			DirAccess.remove_absolute(destination_file)
		var copy_error := DirAccess.copy_absolute(result_file, destination_file)
		if(copy_error != OK):
			return Util.Stats.new(false, Util.trans("error.failed_to_copy_file") + ": " + file_relative)

	return Util.Stats.new(true, "status.ok")

func _files_match(left_path: String, right_path: String) -> bool:
	if(!FileAccess.file_exists(left_path) || !FileAccess.file_exists(right_path)):
		return false
	var left_file := FileAccess.open(left_path, FileAccess.READ)
	if(left_file == null): return false;
	var right_file := FileAccess.open(right_path, FileAccess.READ)
	if(right_file == null): return false;
	if(left_file.get_length() != right_file.get_length()): return false;
	return left_file.get_buffer(left_file.get_length()) == right_file.get_buffer(right_file.get_length())

func _read_json(path: String) -> Util.Stats:
	if(!FileAccess.file_exists(path)):
		return Util.Stats.new(false, "error.config_file_not_found")
	var file := FileAccess.open(path, FileAccess.READ)
	if(file == null):
		return Util.Stats.new(false, "error.failed_to_open_config_file")
	var parsed = JSON.parse_string(file.get_as_text())
	if(typeof(parsed) != TYPE_DICTIONARY):
		return Util.Stats.new(false, "error.config_file_invalid")
	return Util.Stats.new(true, "status.ok", parsed)

func _write_json(path: String, data: Dictionary) -> Util.Stats:
	ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if(file == null):
		return Util.Stats.new(false, "error.failed_to_write_config_file")
	file.store_string(JSON.stringify(data, "\t"))
	return Util.Stats.new(true, "status.ok")

func _mod_config_data(g_name: String, m_name: String, metadata: Dictionary = {}) -> Dictionary:
	var config := {
		"name": m_name,
		"game_name": g_name,
	}
	for key in ["app_id", "manifest_id", "branch"]:
		if(metadata.has(key)): config[key] = metadata[key];
	return config

func ensure_directory(path: String) -> void:
	if(!DirAccess.dir_exists_absolute(path)):
		DirAccess.make_dir_recursive_absolute(path)

func delete_directory_if_exists(path: String) -> void:
	if(!_is_safe_directory_target(path)):
		return
	if(!DirAccess.dir_exists_absolute(path)): return;
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		delete_directory_if_exists(path.path_join(directory_name))
	DirAccess.remove_absolute(path)

func delete_directory_contents(path: String) -> void:
	if(!_is_safe_directory_target(path)):
		return
	if(!DirAccess.dir_exists_absolute(path)): return;
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		delete_directory_if_exists(path.path_join(directory_name))

func _relative_path(root: String, path: String) -> String:
	var normalized_root := root.replace("\\", "/")
	var normalized_path := path.replace("\\", "/")
	return normalized_path.trim_prefix(normalized_root)

func _game_dir(g_name: String) -> String:
	return GamePath.path_join(g_name)

func _mod_dir(g_name: String, m_name: String) -> String:
	return ModPath.path_join(g_name).path_join(m_name)

func temp_dir(name: String) -> String:
	return ModPath.path_join(TEMP_PREFIX + name)

func _read_package_metadata(extract_dir: String) -> Dictionary:
	var metadata_path := extract_dir.path_join(MOD_METADATA_NAME)
	if(!FileAccess.file_exists(metadata_path)): return {};
	var metadata_result := _read_json(metadata_path)
	if(!metadata_result.ok): return {};
	return metadata_result.data

func _load_default_game_database() -> Util.Stats:
	return Net.load_remote_database_json("DefaultGame.json")

func _resolve_xdelta_path() -> String:
	var path := PatcherPath.path_join("xdelta.exe");
	if(FileAccess.file_exists(path)): return path;
	return "";

func resolve_gddelta_path() -> String:
	var path := PatcherPath.path_join("GodotDelta").path_join("gddelta.exe");
	if(FileAccess.file_exists(path)): return path;
	return "";

func _resolve_metadata_base_dir(game_name: String, metadata: Dictionary, fallback_dir: String = "") -> Util.Stats:
	var app_id := str(metadata.get("app_id", "")).strip_edges()
	var manifest_id := str(metadata.get("manifest_id", "")).strip_edges()
	if(app_id.is_empty() || manifest_id.is_empty()):
		return Util.Stats.new(true, "status.ok", {"base_dir": fallback_dir if !fallback_dir.is_empty() else _game_dir(game_name)})
	var game_config_result := load_game_config(game_name)
	if(game_config_result.ok):
		var game_config: Dictionary = game_config_result.data
		if(
			str(game_config.get("app_id", "")).strip_edges() == app_id
			&& str(game_config.get("installed_manifest_id", "")).strip_edges() == manifest_id
		):
			return Util.Stats.new(true, "status.ok", {"base_dir": fallback_dir if !fallback_dir.is_empty() else _game_dir(game_name)})

	var cache_dir := get_manifest_cache_dir(app_id, manifest_id)
	if(!_directory_has_entries(cache_dir)):
		var app_config_result := load_app_config()
		if(!app_config_result.ok):
			return app_config_result
		var steam_username := str(app_config_result.data.get("steam_username", "")).strip_edges()
		var steam_password := str(app_config_result.data.get("steam_password", ""))
		if(steam_username.is_empty() || steam_password.is_empty()):
			return Util.Stats.new(false, "error.steam_login_required")
		var download_result := Steam.download_database_manifest(app_id, manifest_id, cache_dir, steam_username, steam_password)
		if(!download_result.ok):
			return download_result
	if(!_directory_has_entries(cache_dir)):
		return Util.Stats.new(false, "error.manifest_cache_not_found")
	return Util.Stats.new(true, "status.ok", {"base_dir": cache_dir})

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

func parse_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	if(regex.compile("^https?://([^/:]+)(?::(\\d+))?(/.*)?$") != OK):
		return {}
	var match := regex.search(url)
	if(match == null): return {};
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
	return "";

func _find_file_path_by_basename_recursive(root_dir: String, basename: String, extension: String = "") -> String:
	for file_name in DirAccess.get_files_at(root_dir):
		if(file_name.get_basename() != basename): continue;
		if(!extension.is_empty() && !file_name.to_lower().ends_with(extension)): continue;
		return root_dir.path_join(file_name)

	for directory_name in DirAccess.get_directories_at(root_dir):
		var nested_result := _find_file_path_by_basename_recursive(root_dir.path_join(directory_name), basename, extension)
		if(!nested_result.is_empty()):
			return nested_result

	return "";

func _kill_process_by_name(executable_name: String) -> Util.Stats:
	var output: Array = []
	var exit_code := OS.execute("cmd", ["/c", "taskkill", "/IM", executable_name, "/F"], output, true, false)
	if(exit_code != 0):
		var joined_output := "\n".join(output).to_lower()
		if(joined_output.contains("not found") || joined_output.contains("no running instance")):
			return Util.Stats.new(true, "status.ok")
		return Util.Stats.new(false, "error.failed_to_kill_running_game")
	return Util.Stats.new(true, "status.ok")

func _is_process_running_by_name(executable_name: String) -> bool:
	var output: Array = [];
	var exit_code := OS.execute("cmd", ["/c", "tasklist", "/FI", "IMAGENAME eq " + executable_name], output, true, false)
	if(exit_code != 0): return false;
	return "\n".join(output).to_lower().contains(executable_name.to_lower())
