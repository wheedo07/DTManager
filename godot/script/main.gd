extends Control

const MOD_ROW_SCENE := preload("res://scenes/mod_row.tscn");

@export var HOVER_MODULATE:Color = Color.YELLOW;
@export var NORMAL_MODULATE:Color = Color(1, 1, 1);
@onready var prev_game_button: Button = %PrevGameButton
@onready var next_game_button: Button = %NextGameButton
@onready var add_mod_button: Button = %AddModButton
@onready var add_game_button: Button = %AddGameButton
@onready var settings_button: Button = %SettingsButton
@onready var game_name_label: Label = %GameName
@onready var mods_header_label: Label = %ModsHeader
@onready var version_label: Label = %VersionLabel
@onready var mod_list: VBoxContainer = %ModList
@onready var preview_image: TextureRect = %PreviewImage
@onready var preview_title_label: Label = %PreviewTitle
@onready var preview_subtitle_label: Label = %PreviewSubtitle
@onready var selected_mod_name_label: Label = %SelectedModName
@onready var play_button: Button = %PlayButton
@onready var open_folder_button: Button = %OpenFolderButton
@onready var save_button: Button = %SaveButton
@onready var delete_button: Button = %DeleteButton
@onready var add_game_dialog: Control = %AddGameDialog
@onready var add_mod_dialog: Control = %AddModDialog
@onready var game_settings_dialog: Control = %GameSettingsDialog
@onready var save_dialog = %SaveDialog
@onready var confirm_dialog: Control = %ConfirmDialog
@onready var loading_overlay: Control = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel
@onready var reimport_game_dialog: FileDialog = %ReimportGameDialog

var games: Array[Dictionary] = []
var mods: Array[Dictionary] = []
var selected_game_index := 0
var selected_mod_index := -1
var worker_thread: Thread
var worker_action := ""
var worker_meta: Dictionary = {}
var loading_active := false
var pending_delete_action := ""
var pending_delete_meta: Dictionary = {}

func _ready() -> void:
	version_label.text = "v%s (Beta)" % ProjectSettings.get_setting("application/config/version");
	loading_overlay.visible = false
	_refresh_all()

func _on_play_button_pressed() -> void:
	_on_action_pressed("play")

func _on_open_folder_button_pressed() -> void:
	_on_action_pressed("open_folder")

func _on_save_button_pressed() -> void:
	_on_action_pressed("save")

func _on_delete_button_pressed() -> void:
	_on_action_pressed("delete")

func _process(_delta: float) -> void:
	if(loading_active):
		loading_label.text = Util.get_loading_status(loading_label.text)
	if(worker_thread == null || worker_thread.is_alive()): return;
	var result = worker_thread.wait_to_finish();
	worker_thread = null;
	_set_loading(false);
	_handle_worker_result(result);

func _unhandled_input(event: InputEvent) -> void:
	if(!loading_active): return;
	if(event is InputEventKey || event is InputEventJoypadButton || event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled()

func _set_hover_button_modulate(button_path: NodePath, hovered: bool) -> void:
	var button := get_node_or_null(button_path)
	if(button is CanvasItem):
		button.modulate = HOVER_MODULATE if hovered else NORMAL_MODULATE

func _refresh_all() -> void:
	games = Filesys.list_games()
	if(games.is_empty()):
		selected_game_index = 0
		selected_mod_index = -1
		mods = []
		_refresh_screen()
		return

	selected_game_index = clampi(selected_game_index, 0, games.size() - 1)
	var game_name = _selected_game_name()
	mods = Filesys.list_mods(game_name)
	if(selected_mod_index >= mods.size()):
		selected_mod_index = -1
	_refresh_screen()

func _refresh_screen() -> void:
	mods_header_label.text = tr("ui.main.installed_mods");
	_rebuild_mod_list();
	_refresh_add_mod_button();

	if(games.is_empty()):
		game_name_label.text = tr("ui.main.no_game")
		_show_text_preview("DT Manager", "Add a game to continue.")
		selected_mod_name_label.text = tr("ui.main.no_mod_selected")
		return;

	var game := _selected_game()
	var game_name := _selected_game_name()
	var mod_name := ""
	if(_has_selected_mod()):
		mod_name = _selected_mod_name()
	_refresh_preview_image(game_name, mod_name);
	var run_path := str(game.get("run_path", ""));
	game_name_label.text = str(game.get("name", "Unnamed Game"));
	preview_title_label.text = game_name_label.text;
	preview_subtitle_label.text = run_path if !run_path.is_empty() else "Run path is empty.";
	_refresh_selected_mod();

func _refresh_preview_image(game_name: String, mod_name: String = "") -> void:
	var thumbnail_paths: Array[String] = []
	if(!mod_name.is_empty()):
		thumbnail_paths.append(Filesys.get_mod_thumbnail_path(game_name, mod_name))
	thumbnail_paths.append(Filesys.get_game_thumbnail_path(game_name))

	for thumbnail_path in thumbnail_paths:
		if(!FileAccess.file_exists(thumbnail_path)): continue;
		var image := Image.load_from_file(thumbnail_path)
		if(image == null || image.is_empty()): continue;
		preview_image.texture = ImageTexture.create_from_image(image);
		preview_image.visible = true;
		preview_title_label.visible = false;
		preview_subtitle_label.visible = false;
		return

	_show_text_preview(preview_title_label.text, preview_subtitle_label.text);

func _show_text_preview(title: String, subtitle: String) -> void:
	preview_image.texture = null;
	preview_image.visible = false;
	preview_title_label.text = title;
	preview_subtitle_label.text = subtitle;
	preview_title_label.visible = true;
	preview_subtitle_label.visible = true;

func _rebuild_mod_list() -> void:
	for child in mod_list.get_children():
		child.queue_free();

	for index in range(mods.size()):
		var row := MOD_ROW_SCENE.instantiate()
		row.mod_selected.connect(_on_mod_selected)
		mod_list.add_child(row)
		row.setup(str(mods[index].get("name", "Unnamed Mod")), index == selected_mod_index, index)

func _refresh_selected_mod() -> void:
	if(!_has_selected_mod()):
		selected_mod_name_label.text = tr("ui.game.default");
		return;

	selected_mod_index = clampi(selected_mod_index, 0, mods.size() - 1);
	selected_mod_name_label.text = str(mods[selected_mod_index].get("name", "Unnamed Mod"));

func _refresh_add_mod_button() -> void:
	if(_has_selected_mod()):
		var mod_name := _selected_mod_name()
		add_mod_button.text = "Patch Mod"
		add_mod_button.tooltip_text = "Base mod: %s" % mod_name
		return
	add_mod_button.text = "Add Mod"
	add_mod_button.tooltip_text = ""

func _selected_game() -> Dictionary:
	if(games.is_empty()): return {};
	return games[selected_game_index];

func _selected_game_name() -> String:
	return str(_selected_game().get("name", ""))

func _selected_mod() -> Dictionary:
	if(!_has_selected_mod()): return {};
	return mods[selected_mod_index];

func _selected_mod_name() -> String:
	return str(_selected_mod().get("name", ""))

func _has_selected_mod() -> bool:
	return !mods.is_empty() && selected_mod_index >= 0 && selected_mod_index < mods.size();

func _ensure_game_selected() -> bool:
	if(!games.is_empty()): return true;
	Global.alert(tr("error.no_game_selected"))
	return false

func _set_loading(active: bool, message: String = "ui.main.loading") -> void:
	loading_active = active;
	var display_message := tr(message) if message.begins_with("ui.") || message.begins_with("status.") || message.begins_with("error.") else message
	if(active):
		get_viewport().gui_release_focus()
		add_game_dialog.hide()
		add_mod_dialog.hide()
		game_settings_dialog.hide()
		save_dialog.hide()
		Util.set_loading_status(display_message)
	else:
		Util.clear_loading_status()
	loading_overlay.visible = active;
	loading_label.text = display_message;

func _start_worker(action: String, message: String, task: Callable, meta: Dictionary = {}) -> void:
	if(loading_active): return;
	worker_action = action;
	worker_meta = meta;
	worker_thread = Thread.new();
	_set_loading(true, message)
	var start_error := worker_thread.start(task);
	if(start_error != OK):
		worker_thread = null;
		_set_loading(false);
		Global.alert(tr("error.failed_to_start_background_task"));

func _handle_worker_result(result) -> void:
	if(typeof(result) != TYPE_DICTIONARY):
		Global.alert(tr("error.background_task_invalid_result"));
		return;

	var ok := bool(result.get("ok", false));
	var message := str(result.get("message", tr("error.unknown")));
	if(!ok):
		Global.alert(message);
		return;

	match worker_action:
		"add_game":
			var game_name := str(worker_meta.get("game_name", ""));
			_refresh_all();
			_select_game_by_name(game_name);
			selected_mod_index = -1;
			_refresh_all();
		"add_mod":
			_refresh_all();
			selected_mod_index = -1;
			_refresh_screen();
		"reimport_game":
			_refresh_all();
			var reimported_game := str(worker_meta.get("game_name", ""));
			if(!reimported_game.is_empty()):
				_select_game_by_name(reimported_game);
			_refresh_screen();
		"delete":
			_refresh_all();
		"settings":
			_refresh_all();
			var renamed_game := str(worker_meta.get("game_name", ""));
			if(!renamed_game.is_empty()):
				_select_game_by_name(renamed_game);
			var renamed_mod := str(worker_meta.get("mod_name", ""));
			if(!renamed_mod.is_empty()):
				for index in range(mods.size()):
					if(str(mods[index].get("name", "")) == renamed_mod):
						selected_mod_index = index;
						break;
		"play":
			pass;
		"download_patchers":
			pass;
		"save_current", "save_restore", "save_rename", "save_delete", "save_import_zip", "save_export_zip":
			_refresh_save_dialog(true)
		_:
			_refresh_all();

func _select_game_by_name(game_name: String) -> void:
	for index in range(games.size()):
		if(str(games[index].get("name", "")) == game_name):
			selected_game_index = index;
			return;

func _on_prev_game_pressed() -> void:
	if(games.is_empty() || loading_active): return;
	selected_game_index = posmod(selected_game_index - 1, games.size());
	selected_mod_index = -1;
	_refresh_all();

func _on_next_game_pressed() -> void:
	if(games.is_empty() || loading_active): return;
	selected_game_index = posmod(selected_game_index + 1, games.size());
	selected_mod_index = -1;
	_refresh_all();

func _on_mod_selected(index: int) -> void:
	if(loading_active): return;
	selected_mod_index = -1 if selected_mod_index == index else index;
	_rebuild_mod_list();
	_refresh_screen();

func _on_add_game_pressed() -> void:
	if(loading_active): return;
	add_game_dialog.open_dialog();

func _on_add_mod_pressed() -> void:
	if(loading_active): return;
	if(games.is_empty()):
		Global.alert(tr("error.add_game_first"));
		return;
	var base_mod_name := ""
	if(_has_selected_mod()):
		base_mod_name = _selected_mod_name()
	add_mod_dialog.open_dialog(base_mod_name);

func _on_reimport_game_pressed() -> void:
	if(loading_active): return;
	if(!_ensure_game_selected()):
		return;
	reimport_game_dialog.current_dir = _get_reimport_initial_dir()
	reimport_game_dialog.current_file = ""
	reimport_game_dialog.popup_centered_ratio(0.8)

func _on_reimport_game_selected(path: String) -> void:
	if(loading_active): return;
	if(!_ensure_game_selected()): return;
	var game_name := _selected_game_name()
	_start_worker("reimport_game", "Reimporting game files...", Callable(self, "_thread_reimport_game").bind(game_name, path), {"game_name": game_name})

func _get_reimport_initial_dir() -> String:
	var game := _selected_game()
	var steam_game_path := str(game.get("steam_game_path", "")).strip_edges()
	if(!steam_game_path.is_empty()): return steam_game_path
	return Filesys.GamePath.path_join(_selected_game_name())

func _on_settings_pressed() -> void:
	if(loading_active): return;
	var app_config_result := Filesys.load_app_config();
	if(!app_config_result.ok):
		Global.alert(app_config_result.message);
		return;
	var item_config := {};
	var is_mod := false
	if(games.is_empty()):
		game_settings_dialog.open_dialog(app_config_result.data, item_config, false);
		return;
	var game_name := _selected_game_name()
	if(_has_selected_mod()):
		var mod_name := _selected_mod_name()
		var mod_config_result := Filesys.load_mod_config(game_name, mod_name);
		if(!mod_config_result.ok):
			Global.alert(mod_config_result.message);
			return;
		item_config = mod_config_result.data
		is_mod = true
		game_settings_dialog.open_dialog(app_config_result.data, item_config, is_mod);
		return;
	var config_result := Filesys.load_game_config(game_name);
	if(!config_result.ok):
		Global.alert(config_result.message);
		return;
	item_config = config_result.data
	game_settings_dialog.open_dialog(app_config_result.data, item_config, false);

func _on_action_pressed(action: String) -> void:
	match action:
		"play":
			_play_selected_mod();
		"open_folder":
			_open_selected_folder();
		"save":
			_open_save_dialog();
		"delete":
			_delete_selected_item();
		_:
			Global.alert(tr("error.unknown_action"));


func _play_selected_mod() -> void:
	if(!_ensure_game_selected()): return;
	var game_name := _selected_game_name()
	var mod_name := "";
	if(_has_selected_mod()):
		mod_name = _selected_mod_name()
	_start_worker("play", "Launching game...", Callable(self, "_thread_play").bind(game_name, mod_name));

func _open_selected_folder() -> void:
	if(!_ensure_game_selected()): return;
	if(!_has_selected_mod()):
		Global.open_path(Filesys.GamePath.path_join(_selected_game_name()));
		return;

	var mod_path := Filesys.ModPath.path_join(_selected_game_name()).path_join(_selected_mod_name());
	Global.open_path(mod_path);

func _delete_selected_item() -> void:
	if(!_ensure_game_selected()): return;
	if(mods.is_empty()):
		_open_delete_confirm("game", {
			"game_name": _selected_game_name(),
		})
		return;
	if(!_has_selected_mod()):
		Global.alert(tr("error.select_mod_to_delete"));
		return;
	_open_delete_confirm("mod", {
		"game_name": _selected_game_name(),
		"mod_name": _selected_mod_name(),
	})

func _open_delete_confirm(action: String, meta: Dictionary) -> void:
	pending_delete_action = action
	pending_delete_meta = meta.duplicate(true)
	var message := ""
	var title := "ui.common.delete"
	var confirm_text := "ui.common.delete"
	match action:
		"mod":
			message = tr("ui.delete.confirm_mod") % str(meta.get("mod_name", ""))
		"save_current":
			message = tr("ui.save.confirm_overwrite_save") % str(meta.get("slot_name", ""))
			title = "ui.common.save"
			confirm_text = "ui.common.save"
		"save":
			message = tr("ui.delete.confirm_save") % str(meta.get("slot_name", ""))
			confirm_text = "ui.common.overwrite"
		_:
			message = tr("ui.delete.confirm_game") % str(meta.get("game_name", ""))
	confirm_dialog.open(message, title, confirm_text)

func _on_delete_confirmed() -> void:
	match pending_delete_action:
		"game":
			_start_worker("delete", "Deleting game...", Callable(self, "_thread_delete_game").bind(str(pending_delete_meta.get("game_name", ""))))
		"mod":
			_start_worker("delete", "Deleting mod...", Callable(self, "_thread_delete_mod").bind(str(pending_delete_meta.get("game_name", "")), str(pending_delete_meta.get("mod_name", ""))))
		"save_current":
			_start_worker("save_current", "Saving current save...", Callable(self, "_thread_save_current").bind(str(pending_delete_meta.get("game_name", "")), str(pending_delete_meta.get("slot_name", ""))))
		"save":
			_start_worker("save_delete", "Deleting save...", Callable(self, "_thread_delete_save").bind(str(pending_delete_meta.get("game_name", "")), str(pending_delete_meta.get("slot_name", ""))))
	pending_delete_action = ""
	pending_delete_meta = {}

func _open_save_dialog() -> void:
	if(!_ensure_game_selected()): return;
	_refresh_save_dialog(true)

func _refresh_save_dialog(open_dialog: bool = false) -> void:
	if(games.is_empty()): return;
	var game_name := _selected_game_name()
	var config_result := Filesys.load_game_config(game_name)
	if(!config_result.ok):
		Global.alert(config_result.message)
		return
	var save_path := str(config_result.data.get("save_path", ""))
	var slots := Filesys.list_save_slots(game_name)
	if(open_dialog):
		save_dialog.open_dialog(game_name, save_path, slots)
		return
	save_dialog.refresh_slots(slots)

func _on_game_created(game_name: String, executable_path: String) -> void:
	_start_worker("add_game", "Copying game files...", Callable(self, "_thread_add_game").bind(executable_path, game_name), {"game_name": game_name})

func _on_app_settings_saved(steam_username: String, steam_password: String) -> void:
	_start_worker("app_settings", "Saving app settings...", Callable(self, "_thread_save_app_settings").bind(steam_username, steam_password))

func _on_item_settings_saved(new_name: String, steam_game_path: String, save_path: String, thumbnail_path: String, use_steam_launch: bool, is_mod: bool) -> void:
	if(!_ensure_game_selected()): return;
	var game_name := _selected_game_name()
	if(is_mod):
		if(!_has_selected_mod()):
			Global.alert(tr("error.no_game_selected"));
			return;
		var mod_name := _selected_mod_name()
		_start_worker("settings", "Saving settings...", Callable(self, "_thread_save_mod_settings").bind(game_name, mod_name, new_name, thumbnail_path), {"game_name": game_name, "mod_name": new_name})
		return
	_start_worker("settings", "Saving settings...", Callable(self, "_thread_save_game_settings").bind(game_name, new_name, steam_game_path, save_path, thumbnail_path, use_steam_launch), {"game_name": new_name})

func _on_mod_created(mod_name: String, source_path: String) -> void:
	if(!_ensure_game_selected()): return;
	var game_name := _selected_game_name()
	var base_mod_name := ""
	if(_has_selected_mod()):
		base_mod_name = _selected_mod_name()
	_start_worker("add_mod", tr("status.building_mod_files"), Callable(self, "_thread_add_mod").bind(game_name, source_path, mod_name, base_mod_name), {"mod_name": mod_name})

func _on_maintenance_requested(action: String) -> void:
	if(loading_active): return;
	match action:
		"download_patchers":
			_start_worker("download_patchers", "Downloading patchers...", Callable(self, "_thread_download_patchers"))
		_:
			Global.alert(tr("error.unknown_action"));

func _on_steam_login_requested(steam_username: String, steam_password: String) -> void:
	if(loading_active): return;
	_start_worker("steam_login", "Logging in to Steam...", Callable(self, "_thread_steam_login").bind(steam_username, steam_password))

func _on_save_current_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_start_worker("save_current", "Saving current save...", Callable(self, "_thread_save_current").bind(game_name, slot_name))

func _on_save_current_confirm_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_open_delete_confirm("save_current", {
		"game_name": game_name,
		"slot_name": slot_name,
	})

func _on_save_restore_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_start_worker("save_restore", "Restoring save...", Callable(self, "_thread_restore_save").bind(game_name, slot_name))

func _on_save_rename_requested(game_name: String, old_name: String, new_name: String) -> void:
	if(loading_active): return;
	_start_worker("save_rename", "Renaming save...", Callable(self, "_thread_rename_save").bind(game_name, old_name, new_name))

func _on_save_delete_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_open_delete_confirm("save", {
		"game_name": game_name,
		"slot_name": slot_name,
	})

func _on_save_import_zip_requested(game_name: String, slot_name: String, zip_path: String) -> void:
	if(loading_active): return;
	_start_worker("save_import_zip", "Importing save ZIP...", Callable(self, "_thread_import_save_zip").bind(game_name, slot_name, zip_path))

func _on_save_export_zip_requested(game_name: String, slot_name: String, zip_path: String) -> void:
	if(loading_active): return;
	_start_worker("save_export_zip", "Exporting save ZIP...", Callable(self, "_thread_export_save_zip").bind(game_name, slot_name, zip_path))

func _thread_add_game(executable_path: String, game_name: String) -> Dictionary:
	return Filesys.addGame(executable_path, game_name).to_dict();

func _thread_add_mod(game_name: String, source_path: String, mod_name: String, base_mod_name: String) -> Dictionary:
	return Filesys.addMod(game_name, source_path, mod_name, base_mod_name).to_dict();

func _thread_reimport_game(game_name: String, executable_path: String) -> Dictionary:
	return Filesys.reimport_game(game_name, executable_path).to_dict();

func _thread_download_patchers() -> Dictionary:
	return Steam.ensure_patchers().to_dict();

func _thread_steam_login(steam_username: String, steam_password: String) -> Dictionary:
	var save_result := Filesys.save_app_config({
		"steam_username": steam_username,
		"steam_password": steam_password,
	})
	if(!save_result.ok): return save_result.to_dict();
	return Steam.login(steam_username, steam_password).to_dict();

func _thread_save_current(game_name: String, slot_name: String) -> Dictionary:
	return Filesys.backup_save_slot(game_name, slot_name).to_dict();

func _thread_restore_save(game_name: String, slot_name: String) -> Dictionary:
	return Filesys.restore_save_slot(game_name, slot_name).to_dict();

func _thread_rename_save(game_name: String, old_name: String, new_name: String) -> Dictionary:
	return Filesys.rename_save_slot(game_name, old_name, new_name).to_dict();

func _thread_delete_save(game_name: String, slot_name: String) -> Dictionary:
	return Filesys.delete_save_slot(game_name, slot_name).to_dict();

func _thread_import_save_zip(game_name: String, slot_name: String, zip_path: String) -> Dictionary:
	return Filesys.import_save_slot_zip(game_name, slot_name, zip_path).to_dict();

func _thread_export_save_zip(game_name: String, slot_name: String, zip_path: String) -> Dictionary:
	return Filesys.export_save_slot_zip(game_name, slot_name, zip_path).to_dict();

func _thread_save_app_settings(steam_username: String, steam_password: String) -> Dictionary:
	return Filesys.save_app_config({
		"steam_username": steam_username,
		"steam_password": steam_password,
	}).to_dict();

func _thread_delete_game(game_name: String) -> Dictionary:
	return Filesys.delete_game(game_name).to_dict();

func _thread_delete_mod(game_name: String, mod_name: String) -> Dictionary:
	return Filesys.delete_mod(game_name, mod_name).to_dict();

func _thread_save_game_settings(old_name: String, new_name: String, steam_game_path: String, save_path: String, thumbnail_path: String, use_steam_launch: bool) -> Dictionary:
	var target_name := old_name
	if(old_name != new_name):
		var rename_result := Filesys.rename_game(old_name, new_name)
		if(!rename_result.ok):
			return rename_result.to_dict()
		target_name = new_name
	var config_result := Filesys.load_game_config(target_name)
	if(!config_result.ok):
		return config_result.to_dict()
	var config := config_result.data.duplicate(true)
	config["name"] = target_name
	config["save_path"] = save_path.strip_edges()
	config["use_steam_launch"] = use_steam_launch
	config.erase("app_id")
	config.erase("steam_uri")
	config.erase("steam_game_path")
	config.erase("installed_manifest_id")
	if(!steam_game_path.is_empty()):
		var steam_info := Steam.detect_install(steam_game_path)
		if(steam_info.is_empty()):
			return Util.Stats.new(false, tr("error.steam_manifest_not_found")).to_dict()
		config["app_id"] = str(steam_info.get("app_id", ""))
		config["steam_uri"] = str(steam_info.get("steam_uri", ""))
		config["steam_game_path"] = str(steam_info.get("steam_game_path", ""))
		config["installed_manifest_id"] = str(steam_info.get("installed_manifest_id", "")).strip_edges()
	var save_result := Filesys.save_game_config(target_name, config)
	if(!save_result.ok):
		return save_result.to_dict()
	return Filesys.save_thumbnail(Filesys.get_game_thumbnail_path(target_name), thumbnail_path).to_dict()

func _thread_save_mod_settings(game_name: String, old_name: String, new_name: String, thumbnail_path: String) -> Dictionary:
	var target_name := old_name
	if(old_name != new_name):
		var rename_result := Filesys.rename_mod(game_name, old_name, new_name)
		if(!rename_result.ok):
			return rename_result.to_dict()
		target_name = new_name
	var config_result := Filesys.load_mod_config(game_name, target_name)
	if(!config_result.ok):
		return config_result.to_dict()
	var config := config_result.data.duplicate(true)
	config["name"] = target_name
	var save_result := Filesys.save_mod_config(game_name, target_name, config)
	if(!save_result.ok):
		return save_result.to_dict()
	return Filesys.save_thumbnail(Filesys.get_mod_thumbnail_path(game_name, target_name), thumbnail_path).to_dict()

func _thread_play(game_name: String, mod_name: String) -> Dictionary:
	var runtime_builder := RuntimeBuilder.new()
	return runtime_builder.prepare_and_launch(game_name, mod_name).to_dict();
