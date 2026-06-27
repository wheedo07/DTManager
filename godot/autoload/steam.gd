extends Node

const DATABASE_REPO_OWNER := "wheedo07"
const DATABASE_REPO_NAME := "DTManager"
const DATABASE_REPO_BRANCH := "main"

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
		return {
			"steam_uri": "steam://run/" + app_id,
			"steam_game_path": source_dir,
		}
	return {}

func login(username: String, password: String) -> Util.Stats:
	if(username.strip_edges().is_empty()):
		return Util.Stats.new(false, "error.steam_username_not_set")
	if(password.is_empty()):
		return Util.Stats.new(false, "error.steam_credentials_not_set")
	Util.set_loading_status("Checking patcher tools...")
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		var patcher_result := ensure_patchers()
		if(!patcher_result.ok):
			return patcher_result
		depot_downloader_path = _resolve_depot_downloader_path()
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
		Util.set_loading_status("Downloading patcher: %s" % patcher_name)
		var install_result := _install_patcher_archive(str(patcher_name), url)
		if(!install_result.ok):
			return install_result

	return Util.Stats.new(true, "status.patchers_ready")

func download_database_manifest(app_id: String, manifest_id: String, destination_dir: String, username: String = "", password: String = "") -> Util.Stats:
	Util.set_loading_status("Checking patcher tools...")
	var depot_downloader_path := _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		var patcher_result := ensure_patchers()
		if(!patcher_result.ok):
			return patcher_result
		depot_downloader_path = _resolve_depot_downloader_path()
	if(depot_downloader_path.is_empty()):
		return Util.Stats.new(false, "error.depotdownloader_executable_not_found")

	var game_result := load_database_game(app_id)
	if(!game_result.ok):
		return game_result
	if(!_database_game_has_manifest(game_result.data, manifest_id)):
		return Util.Stats.new(false, "error.database_manifest_not_listed")

	var manifest_result := load_database_manifest(app_id, manifest_id)
	if(!manifest_result.ok):
		return manifest_result

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
	return _load_remote_database_json("%s/game.json" % app_id)

func load_database_manifest(app_id: String, manifest_id: String) -> Util.Stats:
	return _load_remote_database_json("%s/manifests/%s.json" % [app_id, manifest_id])

func _resolve_depot_downloader_path() -> String:
	var path := Filesys.PatcherPath.path_join("DepotDownloader").path_join("DepotDownloader.exe")
	if(FileAccess.file_exists(path)):
		return path
	return ""

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

	var download_result := _download_url_to_file(url, archive_path)
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

func _download_url_to_file(url: String, output_path: String) -> Util.Stats:
	var request_result := _request_url(url, ["User-Agent: DTManager"])
	if(!bool(request_result.get("ok", false))):
		return Util.Stats.new(false, str(request_result.get("message", "error.failed_to_download_file")))
	Filesys.ensure_directory(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if(file == null):
		return Util.Stats.new(false, "error.failed_to_write_extracted_file")
	file.store_buffer(request_result.get("body", PackedByteArray()))
	return Util.Stats.new(true, "status.ok")

func _request_json_from_url(url: String, headers: PackedStringArray = []) -> Dictionary:
	var request_result := _request_url(url, headers)
	if(!bool(request_result.get("ok", false))):
		return request_result
	var parsed = JSON.parse_string(PackedByteArray(request_result.get("body", [])).get_string_from_utf8())
	if(parsed == null):
		return {"ok": false, "message": Util.trans("error.failed_to_parse_remote_json")}
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
		return Util.Stats.new(false, str(result.get("message", "error.database_sync_failed")))
	if(typeof(result.get("data", null)) != TYPE_DICTIONARY):
		return Util.Stats.new(false, "error.database_tree_invalid")
	return Util.Stats.new(true, "status.ok", result.get("data", {}))

func _request_url(url: String, headers: PackedStringArray = [], redirect_count: int = 0) -> Dictionary:
	if(redirect_count > 5):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	var url_info := Filesys.parse_url(url)
	if(url_info.is_empty()):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	var client := HTTPClient.new()
	var tls_options = TLSOptions.client() if bool(url_info.get("https", false)) else null
	var connect_error := client.connect_to_host(str(url_info.get("host", "")), int(url_info.get("port", 0)), tls_options)
	if(connect_error != OK):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	while client.get_status() == HTTPClient.STATUS_RESOLVING || client.get_status() == HTTPClient.STATUS_CONNECTING:
		client.poll()
	if(client.get_status() != HTTPClient.STATUS_CONNECTED):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	var request_error := client.request(HTTPClient.METHOD_GET, str(url_info.get("path", "/")), headers)
	if(request_error != OK):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
	if(client.get_status() != HTTPClient.STATUS_BODY && !client.has_response()):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	var response_code := client.get_response_code()
	var response_headers := client.get_response_headers_as_dictionary()
	if(response_code >= 300 && response_code < 400):
		var location := str(response_headers.get("Location", response_headers.get("location", "")))
		if(location.is_empty()):
			return {"ok": false, "message": Util.trans("error.http_request_failed")}
		return _request_url(location, headers, redirect_count + 1)
	if(response_code < 200 || response_code >= 300):
		return {"ok": false, "message": Util.trans("error.http_request_failed")}
	var body := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if(chunk.is_empty()):
			continue
		body.append_array(chunk)
	return {"ok": true, "body": body}

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
