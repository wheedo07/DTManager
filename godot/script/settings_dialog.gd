extends PopupPanel

signal app_settings_saved(steam_username: String, steam_password: String)
signal item_settings_saved(name_value: String, steam_game_path: String, save_path: String, thumbnail_path: String, use_steam_launch: bool, is_mod: bool)
signal maintenance_requested(action: String)
signal steam_login_requested(steam_username: String, steam_password: String)

@onready var title_label: Label = %TitleLabel
@onready var tabs: TabContainer = %Tabs
@onready var app_section: VBoxContainer = %AppSection
@onready var item_section: VBoxContainer = %ItemSection
@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var game_name_label: Label = %GameNameLabel
@onready var steam_game_path_label: Label = %SteamGamePathLabel
@onready var steam_game_path_row: HBoxContainer = %SteamGamePathRow
@onready var steam_game_path_edit: LineEdit = %SteamGamePathEdit
@onready var use_steam_launch_check_box: CheckBox = %UseSteamLaunchCheckBox
@onready var save_path_label: Label = %SavePathLabel
@onready var save_path_row: HBoxContainer = %SavePathRow
@onready var save_path_edit: LineEdit = %SavePathEdit
@onready var steam_username_label: Label = %SteamUsernameLabel
@onready var steam_username_edit: LineEdit = %SteamUsernameEdit
@onready var steam_password_label: Label = %SteamPasswordLabel
@onready var steam_password_edit: LineEdit = %SteamPasswordEdit
@onready var steam_login_button: Button = %SteamLoginButton
@onready var browse_button: Button = %BrowseButton
@onready var folder_dialog: FileDialog = %SteamGamePathDialog
@onready var save_browse_button: Button = %SaveBrowseButton
@onready var save_folder_dialog: FileDialog = %SavePathDialog
@onready var thumbnail_browse_button: Button = %ThumbnailBrowseButton
@onready var thumbnail_dialog: FileDialog = %ThumbnailDialog
@onready var download_patchers_button: Button = %DownloadPatchersButton
@onready var save_button: Button = %SaveButton
@onready var close_button: Button = %CloseButton

var current_is_mod := false
var selected_thumbnail_path := ""
var has_item_settings := false

func open_dialog(app_config: Dictionary, item_config: Dictionary = {}, is_mod: bool = false) -> void:
	current_is_mod = is_mod
	has_item_settings = !item_config.is_empty()
	title_label.text = tr("ui.settings.title")
	game_name_label.text = tr("ui.common.mod_name") if is_mod else tr("ui.common.game_name")
	game_name_edit.text = str(item_config.get("name", ""))
	steam_game_path_edit.text = str(item_config.get("steam_game_path", ""))
	use_steam_launch_check_box.button_pressed = bool(item_config.get("use_steam_launch", !str(item_config.get("steam_uri", "")).is_empty() && !str(item_config.get("steam_game_path", "")).is_empty()))
	save_path_edit.text = str(item_config.get("save_path", ""))
	steam_username_edit.text = str(app_config.get("steam_username", ""))
	steam_password_edit.text = str(app_config.get("steam_password", ""))
	selected_thumbnail_path = ""
	steam_game_path_label.visible = !is_mod && has_item_settings
	steam_game_path_row.visible = !is_mod && has_item_settings
	use_steam_launch_check_box.visible = !is_mod && has_item_settings
	save_path_label.visible = !is_mod && has_item_settings
	save_path_row.visible = !is_mod && has_item_settings
	tabs.set_tab_title(0, tr("ui.settings.app_tab"))
	tabs.set_tab_title(1, tr("ui.settings.item_tab"))
	tabs.set_tab_hidden(1, !has_item_settings)
	tabs.current_tab = 0 if !has_item_settings else 1
	popup_centered()
	if(tabs.current_tab == 0):
		steam_username_edit.grab_focus()
	else:
		game_name_edit.grab_focus()

func _notification(what: int) -> void:
	if(what != NOTIFICATION_WM_WINDOW_FOCUS_OUT || !visible): return;
	if(folder_dialog.visible || save_folder_dialog.visible || thumbnail_dialog.visible): return;
	hide()

func _on_browse_pressed() -> void:
	folder_dialog.popup_centered_ratio(0.8)

func _on_directory_selected(path: String) -> void:
	steam_game_path_edit.text = path

func _on_save_browse_pressed() -> void:
	save_folder_dialog.popup_centered_ratio(0.8)

func _on_save_directory_selected(path: String) -> void:
	save_path_edit.text = path

func _on_thumbnail_browse_pressed() -> void:
	thumbnail_dialog.popup_centered_ratio(0.8)

func _on_thumbnail_selected(path: String) -> void:
	selected_thumbnail_path = path

func _on_steam_login_button_pressed() -> void:
	steam_login_requested.emit(steam_username_edit.text.strip_edges(), steam_password_edit.text)

func _on_download_patchers_button_pressed() -> void:
	maintenance_requested.emit("download_patchers")

func _on_confirmed() -> void:
	if(tabs.current_tab == 0):
		app_settings_saved.emit(steam_username_edit.text.strip_edges(), steam_password_edit.text)
		return
	var game_name := game_name_edit.text.strip_edges()
	if(game_name.is_empty()):
		Global.alert(tr("error.game_name_empty"))
		return
	var steam_game_path := ""
	var save_path := ""
	var use_steam_launch := false
	if(!current_is_mod):
		steam_game_path = steam_game_path_edit.text.strip_edges()
		save_path = save_path_edit.text.strip_edges()
		use_steam_launch = use_steam_launch_check_box.button_pressed
	item_settings_saved.emit(game_name, steam_game_path, save_path, selected_thumbnail_path.strip_edges(), use_steam_launch, current_is_mod)
