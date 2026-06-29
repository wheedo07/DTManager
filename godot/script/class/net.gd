extends RefCounted
class_name Net

const DATABASE_REPO_OWNER := "wheedo07"
const DATABASE_REPO_NAME := "DTManager"
const DATABASE_REPO_BRANCH := "main"

static func download_url_to_file(url: String, output_path: String) -> Util.Stats:
	var request_result := _request_url(url, ["User-Agent: DTManager"])
	if(!bool(request_result.get("ok", false))):
		return Util.Stats.new(false, str(request_result.get("message", "error.failed_to_download_file")))
	Filesys.ensure_directory(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if(file == null):
		return Util.Stats.new(false, "error.failed_to_write_extracted_file")
	file.store_buffer(request_result.get("body", PackedByteArray()))
	return Util.Stats.new(true, "status.ok")

static func load_remote_database_json(relative_path: String) -> Util.Stats:
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

static func _request_json_from_url(url: String, headers: PackedStringArray = []) -> Dictionary:
	var request_result := _request_url(url, headers)
	if(!bool(request_result.get("ok", false))): return request_result;
	var parsed = JSON.parse_string(PackedByteArray(request_result.get("body", [])).get_string_from_utf8())
	if(parsed == null):
		return {"ok": false, "message": Util.trans("error.failed_to_parse_remote_json")}
	return {"ok": true, "data": parsed}

static func _request_url(url: String, headers: PackedStringArray = [], redirect_count: int = 0) -> Dictionary:
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
		if(chunk.is_empty()): continue;
		body.append_array(chunk)
	return {"ok": true, "body": body}
