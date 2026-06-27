extends AcceptDialog

signal app_settings_saved(steam_username: String, steam_password: String)
signal item_settings_saved(name_value: String, steam_game_path: String, thumbnail_path: String, is_mod: bool)
signal maintenance_requested(action: String)
signal steam_account_check_requested(steam_username: String, steam_password: String)

@onready var tabs: TabContainer = %Tabs
@onready var app_section: VBoxContainer = %AppSection
@onready var item_section: VBoxContainer = %ItemSection
@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var game_name_label: Label = %GameNameLabel
@onready var steam_game_path_label: Label = %SteamGamePathLabel
@onready var steam_game_path_row: HBoxContainer = %SteamGamePathRow
@onready var steam_game_path_edit: LineEdit = %SteamGamePathEdit
@onready var steam_username_label: Label = %SteamUsernameLabel
@onready var steam_username_edit: LineEdit = %SteamUsernameEdit
@onready var steam_password_label: Label = %SteamPasswordLabel
@onready var steam_password_edit: LineEdit = %SteamPasswordEdit
@onready var check_steam_account_button: Button = %CheckSteamAccountButton
@onready var browse_button: Button = %BrowseButton
@onready var folder_dialog: FileDialog = %SteamGamePathDialog
@onready var thumbnail_browse_button: Button = %ThumbnailBrowseButton
@onready var thumbnail_dialog: FileDialog = %ThumbnailDialog
@onready var sync_database_button: Button = %SyncDatabaseButton
@onready var download_patchers_button: Button = %DownloadPatchersButton

var current_is_mod := false
var selected_thumbnail_path := ""
var has_item_settings := false

func _ready() -> void:
	browse_button.pressed.connect(_on_browse_pressed)
	thumbnail_browse_button.pressed.connect(_on_thumbnail_browse_pressed)
	check_steam_account_button.pressed.connect(func() -> void: steam_account_check_requested.emit(steam_username_edit.text.strip_edges(), steam_password_edit.text))
	sync_database_button.pressed.connect(func() -> void: maintenance_requested.emit("sync_database"))
	download_patchers_button.pressed.connect(func() -> void: maintenance_requested.emit("download_patchers"))
	confirmed.connect(_on_confirmed)
	folder_dialog.dir_selected.connect(_on_directory_selected)
	thumbnail_dialog.file_selected.connect(_on_thumbnail_selected)

func open_dialog(app_config: Dictionary, item_config: Dictionary = {}, is_mod: bool = false) -> void:
	current_is_mod = is_mod
	has_item_settings = !item_config.is_empty()
	title = "Settings"
	game_name_label.text = "Mod Name" if is_mod else "Game Name"
	game_name_edit.text = str(item_config.get("name", ""))
	steam_game_path_edit.text = str(item_config.get("steam_game_path", ""))
	steam_username_edit.text = str(app_config.get("steam_username", ""))
	steam_password_edit.text = str(app_config.get("steam_password", ""))
	selected_thumbnail_path = ""
	steam_game_path_label.visible = !is_mod && has_item_settings
	steam_game_path_row.visible = !is_mod && has_item_settings
	tabs.set_tab_title(0, tr("ui.settings.app_tab"))
	tabs.set_tab_title(1, tr("ui.settings.item_tab"))
	tabs.set_tab_hidden(1, !has_item_settings)
	tabs.current_tab = 0 if !has_item_settings else 1
	popup_centered()
	if(tabs.current_tab == 0):
		steam_username_edit.grab_focus()
	else:
		game_name_edit.grab_focus()

func _on_browse_pressed() -> void:
	folder_dialog.popup_centered_ratio(0.8)

func _on_directory_selected(path: String) -> void:
	steam_game_path_edit.text = path

func _on_thumbnail_browse_pressed() -> void:
	thumbnail_dialog.popup_centered_ratio(0.8)

func _on_thumbnail_selected(path: String) -> void:
	selected_thumbnail_path = path

func _on_confirmed() -> void:
	if(tabs.current_tab == 0):
		app_settings_saved.emit(steam_username_edit.text.strip_edges(), steam_password_edit.text)
		return
	var game_name := game_name_edit.text.strip_edges()
	if(game_name.is_empty()):
		Global.alert(tr("error.game_name_empty"))
		return
	var steam_game_path := ""
	if(!current_is_mod):
		steam_game_path = steam_game_path_edit.text.strip_edges()
	item_settings_saved.emit(game_name, steam_game_path, selected_thumbnail_path.strip_edges(), current_is_mod)
