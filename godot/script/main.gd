extends Control

const MOD_ROW_SCENE := preload("res://scenes/mod_row.tscn");

@export var HOVER_MODULATE:Color = Color.YELLOW;
@export var NORMAL_MODULATE:Color = Color(1, 1, 1);
@onready var prev_game_button: Button = %PrevGameButton
@onready var next_game_button: Button = %NextGameButton
@onready var add_mod_button: Button = %AddModButton
@onready var add_game_button: Button = %AddGameButton
@onready var refresh_button: Button = %RefreshButton
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
@onready var add_game_dialog: AcceptDialog = %AddGameDialog
@onready var add_mod_dialog: AcceptDialog = %AddModDialog
@onready var game_settings_dialog: AcceptDialog = %GameSettingsDialog
@onready var save_dialog = %SaveDialog
@onready var loading_overlay: Control = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel

var games: Array[Dictionary] = []
var mods: Array[Dictionary] = []
var selected_game_index := 0
var selected_mod_index := -1
var worker_thread: Thread
var worker_action := ""
var worker_meta: Dictionary = {}
var loading_active := false

func _ready() -> void:
	version_label.text = "v%s (Beta)" % ProjectSettings.get_setting("application/config/version");
	add_game_dialog.game_created.connect(_on_game_created)
	add_mod_dialog.mod_created.connect(_on_mod_created)
	game_settings_dialog.app_settings_saved.connect(_on_app_settings_saved)
	game_settings_dialog.item_settings_saved.connect(_on_item_settings_saved)
	game_settings_dialog.maintenance_requested.connect(_on_maintenance_requested)
	game_settings_dialog.steam_login_requested.connect(_on_steam_login_requested)
	save_dialog.backup_requested.connect(_on_save_backup_requested)
	save_dialog.restore_requested.connect(_on_save_restore_requested)
	loading_overlay.visible = false
	if(!play_button.pressed.is_connected(func() -> void: _on_action_pressed("play"))):
		play_button.pressed.connect(func() -> void: _on_action_pressed("play"))
	if(!open_folder_button.pressed.is_connected(func() -> void: _on_action_pressed("open_folder"))):
		open_folder_button.pressed.connect(func() -> void: _on_action_pressed("open_folder"))
	if(!save_button.pressed.is_connected(func() -> void: _on_action_pressed("save"))):
		save_button.pressed.connect(func() -> void: _on_action_pressed("save"))
	if(!delete_button.pressed.is_connected(func() -> void: _on_action_pressed("delete"))):
		delete_button.pressed.connect(func() -> void: _on_action_pressed("delete"))
	_bind_hover([
		prev_game_button,
		next_game_button,
		add_mod_button,
		add_game_button,
		refresh_button,
		settings_button,
		play_button,
		open_folder_button,
		save_button,
		delete_button,
	])
	_refresh_all()

func _process(_delta: float) -> void:
	if(loading_active):
		loading_label.text = Util.get_loading_status(loading_label.text)
	if(worker_thread == null || worker_thread.is_alive()): return;
	var result = worker_thread.wait_to_finish();
	worker_thread = null;
	_set_loading(false);
	_handle_worker_result(result);

func _bind_hover(buttons: Array) -> void:
	for button in buttons:
		button.mouse_entered.connect(func() -> void: button.modulate = HOVER_MODULATE)
		button.mouse_exited.connect(func() -> void: button.modulate = NORMAL_MODULATE)

func _refresh_all() -> void:
	games = Filesys.list_games()
	if(games.is_empty()):
		selected_game_index = 0
		selected_mod_index = -1
		mods = []
		_refresh_screen()
		return

	selected_game_index = clampi(selected_game_index, 0, games.size() - 1)
	var game_name = _selected_game().get("name", "")
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
	var game_name := str(game.get("name", ""));
	var mod_name := ""
	if(_has_selected_mod()):
		mod_name = str(_selected_mod().get("name", ""))
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
		var mod_name := str(_selected_mod().get("name", ""))
		add_mod_button.text = "Patch Mod"
		add_mod_button.tooltip_text = "Base mod: %s" % mod_name
		return
	add_mod_button.text = "Add Mod"
	add_mod_button.tooltip_text = ""

func _selected_game() -> Dictionary:
	if(games.is_empty()): return {};
	return games[selected_game_index];

func _selected_mod() -> Dictionary:
	if(!_has_selected_mod()): return {};
	return mods[selected_mod_index];

func _has_selected_mod() -> bool:
	return !mods.is_empty() && selected_mod_index >= 0 && selected_mod_index < mods.size();

func _set_loading(active: bool, message: String = "ui.main.loading") -> void:
	loading_active = active;
	var display_message := tr(message) if message.begins_with("ui.") || message.begins_with("status.") || message.begins_with("error.") else message
	if(active):
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
		"save_backup", "save_restore":
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
		base_mod_name = str(_selected_mod().get("name", ""))
	add_mod_dialog.open_dialog(base_mod_name);

func _on_refresh_pressed() -> void:
	if(loading_active): return;
	_refresh_all();

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
	var game_name := str(_selected_game().get("name", ""));
	if(_has_selected_mod()):
		var mod_name := str(_selected_mod().get("name", ""));
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
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"));
		return;

	var game_name := str(_selected_game().get("name", ""));
	var mod_name := "";
	if(_has_selected_mod()):
		mod_name = str(_selected_mod().get("name", ""));
	_start_worker("play", "Launching game...", Callable(self, "_thread_play").bind(game_name, mod_name));

func _open_selected_folder() -> void:
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"));
		return;

	if(!_has_selected_mod()):
		Global.open_path(Filesys.GamePath.path_join(str(_selected_game().get("name", ""))));
		return;

	var mod_path := Filesys.ModPath.path_join(str(_selected_game().get("name", ""))).path_join(str(_selected_mod().get("name", "")));
	Global.open_path(mod_path);

func _delete_selected_item() -> void:
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"));
		return;

	if(mods.is_empty()):
		_start_worker("delete", "Deleting game...", Callable(self, "_thread_delete_game").bind(str(_selected_game().get("name", ""))));
		return;
	if(!_has_selected_mod()):
		Global.alert(tr("error.select_mod_to_delete"));
		return;

	_start_worker("delete", "Deleting mod...", Callable(self, "_thread_delete_mod").bind(str(_selected_game().get("name", "")), str(_selected_mod().get("name", ""))));

func _open_save_dialog() -> void:
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"))
		return
	_refresh_save_dialog(true)

func _refresh_save_dialog(open_dialog: bool = false) -> void:
	if(games.is_empty()):
		return
	var game_name := str(_selected_game().get("name", ""))
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

func _on_item_settings_saved(new_name: String, steam_game_path: String, save_path: String, thumbnail_path: String, is_mod: bool) -> void:
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"));
		return;
	var game_name := str(_selected_game().get("name", ""));
	if(is_mod):
		if(!_has_selected_mod()):
			Global.alert(tr("error.no_game_selected"));
			return;
		var mod_name := str(_selected_mod().get("name", ""));
		_start_worker("settings", "Saving settings...", Callable(self, "_thread_save_mod_settings").bind(game_name, mod_name, new_name, thumbnail_path), {"game_name": game_name, "mod_name": new_name})
		return
	_start_worker("settings", "Saving settings...", Callable(self, "_thread_save_game_settings").bind(game_name, new_name, steam_game_path, save_path, thumbnail_path), {"game_name": new_name})

func _on_mod_created(mod_name: String, source_path: String) -> void:
	if(games.is_empty()):
		Global.alert(tr("error.no_game_selected"));
		return;

	var game_name := str(_selected_game().get("name", ""));
	var base_mod_name := ""
	if(_has_selected_mod()):
		base_mod_name = str(_selected_mod().get("name", ""))
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

func _on_save_backup_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_start_worker("save_backup", "Backing up save...", Callable(self, "_thread_backup_save").bind(game_name, slot_name))

func _on_save_restore_requested(game_name: String, slot_name: String) -> void:
	if(loading_active): return;
	_start_worker("save_restore", "Restoring save...", Callable(self, "_thread_restore_save").bind(game_name, slot_name))

func _thread_add_game(executable_path: String, game_name: String) -> Dictionary:
	return Filesys.addGame(executable_path, game_name).to_dict();

func _thread_add_mod(game_name: String, source_path: String, mod_name: String, base_mod_name: String) -> Dictionary:
	return Filesys.addMod(game_name, source_path, mod_name, base_mod_name).to_dict();

func _thread_download_patchers() -> Dictionary:
	return Steam.ensure_patchers().to_dict();

func _thread_steam_login(steam_username: String, steam_password: String) -> Dictionary:
	var save_result := Filesys.save_app_config({
		"steam_username": steam_username,
		"steam_password": steam_password,
	})
	if(!save_result.ok): return save_result.to_dict();
	return Steam.login(steam_username, steam_password).to_dict();

func _thread_backup_save(game_name: String, slot_name: String) -> Dictionary:
	return Filesys.backup_save_slot(game_name, slot_name).to_dict();

func _thread_restore_save(game_name: String, slot_name: String) -> Dictionary:
	return Filesys.restore_save_slot(game_name, slot_name).to_dict();

func _thread_save_app_settings(steam_username: String, steam_password: String) -> Dictionary:
	return Filesys.save_app_config({
		"steam_username": steam_username,
		"steam_password": steam_password,
	}).to_dict();

func _thread_delete_game(game_name: String) -> Dictionary:
	return Filesys.delete_game(game_name).to_dict();

func _thread_delete_mod(game_name: String, mod_name: String) -> Dictionary:
	return Filesys.delete_mod(game_name, mod_name).to_dict();

func _thread_save_game_settings(old_name: String, new_name: String, steam_game_path: String, save_path: String, thumbnail_path: String) -> Dictionary:
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
	config.erase("steam_uri")
	config.erase("steam_game_path")
	if(!steam_game_path.is_empty()):
		var steam_info := Steam.detect_install(steam_game_path)
		if(steam_info.is_empty()):
			return Util.Stats.new(false, tr("error.steam_manifest_not_found")).to_dict()
		config["steam_uri"] = str(steam_info.get("steam_uri", ""))
		config["steam_game_path"] = str(steam_info.get("steam_game_path", ""))
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
