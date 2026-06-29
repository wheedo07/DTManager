extends Node

func detect_install(source_dir: String) -> Dictionary:
	var normalized_source := source_dir.replace("\\", "/").trim_suffix("/")
	var source_parts := normalized_source.split("/")
	var steamapps_index := source_parts.find("steamapps")
	if(steamapps_index == -1): return {};
	if(steamapps_index + 1 >= source_parts.size() || source_parts[steamapps_index + 1] != "common"):
		return {}

	var steamapps_dir := "/".join(source_parts.slice(0, steamapps_index + 1))
	var install_dir_name := source_dir.get_file()
	for file_name in DirAccess.get_files_at(steamapps_dir):
		if(!file_name.begins_with("appmanifest_") || !file_name.ends_with(".acf")): continue;
		var app_id := file_name.trim_prefix("appmanifest_").trim_suffix(".acf")
		if(app_id.is_empty()): continue;
		var manifest_info := _read_steam_manifest(steamapps_dir.path_join(file_name))
		if(manifest_info.is_empty() || str(manifest_info.get("installdir", "")) != install_dir_name): continue;
		var installed_manifest_id := _resolve_installed_manifest_id(app_id, manifest_info.get("installed_depot_manifests", {}))
		return {
			"app_id": app_id,
			"steam_uri": "steam://run/" + app_id,
			"steam_game_path": source_dir,
			"installed_manifest_id": installed_manifest_id,
		}
	return {}

func login(username: String, password: String) -> Util.Stats:
	if(username.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.steam_username_not_set")
	if(password.is_empty()):
		return Util.Stats.new(false, "error.steam_credentials_not_set")
	Util.set_loading_status("Checking patcher tools...")
	var depot_downloader_result := _ensure_depot_downloader()
	if(!depot_downloader_result.ok):
		return depot_downloader_result
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		return Util.Stats.new(false, "error.depotdownloader_executable_not_found")

	var temp_dir := Filesys.temp_dir("steam_login")
	Filesys.delete_directory_if_exists(temp_dir)
	Filesys.ensure_directory(temp_dir)
	var output: Array = []
	var args: PackedStringArray = [
		"-app", "480",
		"-username", username,
		"-password", password,
		"-remember-password",
		"-manifest-only",
		"-dir", temp_dir,
	]
	Util.set_loading_status(Util.trans("status.steam_login_waiting_guard"))
	var exit_code := OS.execute(depot_downloader_path, args, output, true, false)
	Filesys.delete_directory_if_exists(temp_dir)
	if(exit_code != 0):
		return Util.Stats.new(false, _format_depotdownloader_error("\n".join(output), true))
	return Util.Stats.new(true, "status.steam_logged_in")

func ensure_patchers() -> Util.Stats:
	Util.set_loading_status("Checking patcher database...")
	var config_result := Net.load_remote_database_json("Patcher.json")
	if(!config_result.ok): return config_result;

	for patcher_name in config_result.data.keys():
		var normalized_name := str(patcher_name).to_lower()
		if(normalized_name == "xdelta" || normalized_name == "xdelta3"): continue;
		var url := str(config_result.data.get(patcher_name, ""))
		if(url.is_empty() || _is_patcher_installed(str(patcher_name))): continue;
		Util.set_loading_status("Downloading patcher: %s" % patcher_name)
		var install_result := _install_patcher_archive(str(patcher_name), url)
		if(!install_result.ok): return install_result;
	return Util.Stats.new(true, "status.patchers_ready")

func download_database_manifest(app_id: String, manifest_id: String, destination_dir: String, username: String = "", password: String = "") -> Util.Stats:
	Util.set_loading_status("Checking patcher tools...")
	var depot_downloader_result := _ensure_depot_downloader()
	if(!depot_downloader_result.ok): return depot_downloader_result;
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		return Util.Stats.new(false, "error.depotdownloader_executable_not_found")

	var game_result := load_database_game(app_id)
	if(!game_result.ok): return game_result;
	if(!_database_game_has_manifest(game_result.data, manifest_id)):
		return Util.Stats.new(false, "error.database_manifest_not_listed")

	var manifest_result := load_database_manifest(app_id, manifest_id)
	if(!manifest_result.ok): return manifest_result;

	Filesys.ensure_directory(destination_dir)
	var depots = manifest_result.data.get("depots", [])
	var depot_count = depots.size() if typeof(depots) == TYPE_ARRAY else 0;
	var depot_index := 0
	for depot_entry in manifest_result.data.get("depots", []):
		if(typeof(depot_entry) != TYPE_DICTIONARY): continue;
		depot_index += 1
		var depot_id := _json_number_to_string(depot_entry.get("depot_id", ""))
		var depot_manifest_id := _json_number_to_string(depot_entry.get("manifest_id", ""))
		if(depot_id.is_empty() || depot_manifest_id.is_empty()): continue;
		Util.set_loading_status("Downloading game files... %d/%d" % [depot_index, depot_count])
		var args := [
			"-app", app_id,
			"-depot", depot_id,
			"-manifest", depot_manifest_id,
			"-dir", destination_dir,
		]
		if(!username.is_empty()):
			args.append_array(["-username", "\"%s\"" % username, "-remember-password"])
			if(!password.is_empty()):
				args.append_array(["-password", "\"%s\"" % password])
		var output: Array = []
		var exit_code := OS.execute(depot_downloader_path, args, output, true, false)
		if(exit_code != 0):
			return Util.Stats.new(false, _format_depotdownloader_error("\n".join(output), false))

	return Util.Stats.new(true, "status.depot_download_complete")

func load_database_game(app_id: String) -> Util.Stats:
	return Net.load_remote_database_json("%s/game.json" % app_id)

func load_database_manifest(app_id: String, manifest_id: String) -> Util.Stats:
	return Net.load_remote_database_json("%s/manifests/%s.json" % [app_id, manifest_id])

func _resolve_installed_manifest_id(app_id: String, installed_depot_manifests: Dictionary) -> String:
	if(typeof(installed_depot_manifests) != TYPE_DICTIONARY || installed_depot_manifests.is_empty()): return ""
	var game_result := load_database_game(app_id)
	if(!game_result.ok): return ""
	var manifests = game_result.data.get("manifests", [])
	if(typeof(manifests) != TYPE_ARRAY): return ""
	for entry in manifests:
		if(typeof(entry) != TYPE_DICTIONARY): continue;
		var manifest_id := _json_number_to_string(entry.get("manifest_id", ""))
		if(manifest_id.is_empty()): continue;
		var manifest_result := load_database_manifest(app_id, manifest_id)
		if(!manifest_result.ok): continue;
		var depots = manifest_result.data.get("depots", [])
		if(typeof(depots) != TYPE_ARRAY || depots.is_empty()): continue;
		var matches := true
		for depot_entry in depots:
			if(typeof(depot_entry) != TYPE_DICTIONARY): continue;
			var depot_id := _json_number_to_string(depot_entry.get("depot_id", ""))
			var depot_manifest_id := _json_number_to_string(depot_entry.get("manifest_id", ""))
			if(depot_id.is_empty() || depot_manifest_id.is_empty()):
				matches = false
				break
			if(str(installed_depot_manifests.get(depot_id, "")).strip_edges() != depot_manifest_id):
				matches = false
				break
		if(matches): return manifest_id;
	return ""

func _resolve_depot_downloader_path() -> String:
	var path := Filesys.PatcherPath.path_join("DepotDownloader").path_join("DepotDownloader.exe")
	if(FileAccess.file_exists(path)): return path;
	return ""

func _ensure_depot_downloader() -> Util.Stats:
	if(!_resolve_depot_downloader_path().is_empty()):
		return Util.Stats.new(true, "status.ok")
	var config_result := Net.load_remote_database_json("Patcher.json")
	if(!config_result.ok):
		return config_result
	var url := str(config_result.data.get("DepotDownloader", ""))
	if(url.is_empty()):
		return Util.Stats.new(false, "error.depotdownloader_executable_not_found")
	Util.set_loading_status("Downloading patcher: DepotDownloader")
	return _install_patcher_archive("DepotDownloader", url)

func _is_patcher_installed(patcher_name: String) -> bool:
	match patcher_name.to_lower():
		"godotdelta":
			return !Filesys.resolve_gddelta_path().is_empty()
		"depotdownloader":
			return !_resolve_depot_downloader_path().is_empty()
		_:
			return false

func _install_patcher_archive(patcher_name: String, url: String) -> Util.Stats:
	Util.set_loading_status("Downloading patcher: %s" % patcher_name)
	var archive_path := Filesys.temp_dir("patcher_" + patcher_name.to_lower() + ".zip")
	var extract_dir := Filesys.temp_dir("patcher_" + patcher_name.to_lower())
	var install_dir := _patcher_install_dir(patcher_name)
	Filesys.delete_directory_if_exists(extract_dir)
	Filesys.delete_directory_if_exists(install_dir)
	if(FileAccess.file_exists(archive_path)):
		DirAccess.remove_absolute(archive_path)

	var download_result := Net.download_url_to_file(url, archive_path)
	if(!download_result.ok): return download_result;

	var extract_result := Filesys.extract_zip(archive_path, extract_dir)
	if(!extract_result.ok):
		DirAccess.remove_absolute(archive_path)
		return extract_result

	var source_dir := _resolve_extracted_root(extract_dir)
	var merge_result := Filesys.merge_directory(source_dir, install_dir)
	DirAccess.remove_absolute(archive_path)
	Filesys.delete_directory_if_exists(extract_dir)
	if(!merge_result.ok):
		return merge_result

	return Util.Stats.new(true, "status.patchers_ready")

func _patcher_install_dir(patcher_name: String) -> String:
	match patcher_name.to_lower():
		"godotdelta":
			return Filesys.PatcherPath.path_join("GodotDelta")
		"depotdownloader":
			return Filesys.PatcherPath.path_join("DepotDownloader")
		_:
			return Filesys.PatcherPath.path_join(patcher_name)

func _resolve_extracted_root(extract_dir: String) -> String:
	var directories := DirAccess.get_directories_at(extract_dir)
	var files := DirAccess.get_files_at(extract_dir)
	if(files.is_empty() && directories.size() == 1):
		return extract_dir.path_join(directories[0])
	return extract_dir

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

func _format_depotdownloader_error(output_text: String, is_login: bool) -> String:
	var lowered := output_text.to_lower()
	if(lowered.contains("steam guard")):
		if(is_login):
			return Util.trans("error.steam_login_guard_required") % [output_text]
		return Util.trans("error.depot_download_guard_required") % [output_text]
	if(lowered.contains("invalidpassword")):
		if(is_login):
			return Util.trans("error.steam_login_invalid_password") % [output_text]
		return Util.trans("error.depot_download_invalid_password") % [output_text]
	if(is_login):
		return Util.trans("error.steam_login_failed") % [output_text]
	return Util.trans("error.depot_download_failed") % [output_text]

func _read_steam_manifest(path: String) -> Dictionary:
	if(!FileAccess.file_exists(path)): return {};
	var file := FileAccess.open(path, FileAccess.READ)
	if(file == null): return {};
	var result := {};
	var installed_depot_manifests := {};
	var key_value_regex := RegEx.new()
	var key_only_regex := RegEx.new()
	if(key_value_regex.compile('^\\s*"([^"]+)"\\s*"([^"]*)"\\s*$') != OK): return {};
	if(key_only_regex.compile('^\\s*"([^"]+)"\\s*$') != OK): return {};
	var stack: Array[String] = []
	var pending_key := ""
	while !file.eof_reached():
		var line := file.get_line().strip_edges()
		if(line.is_empty()): continue;
		var key_value_match := key_value_regex.search(line)
		if(key_value_match != null):
			var key := key_value_match.get_string(1)
			var value := key_value_match.get_string(2)
			if(stack.size() == 1 && stack[0] == "AppState"):
				result[key] = value
			elif(stack.size() == 3 && stack[0] == "AppState" && stack[1] == "InstalledDepots" && key == "manifest"):
				installed_depot_manifests[stack[2]] = value
			continue
		var key_only_match := key_only_regex.search(line)
		if(key_only_match != null):
			pending_key = key_only_match.get_string(1)
			continue
		if(line == "{"):
			if(!pending_key.is_empty()):
				stack.append(pending_key)
				pending_key = ""
			continue
		if(line == "}"):
			if(!stack.is_empty()): stack.pop_back();
			pending_key = "";
	result["installed_depot_manifests"] = installed_depot_manifests
	return result
