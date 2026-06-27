extends AcceptDialog

signal settings_saved(name_value: String, steam_game_path: String, thumbnail_path: String, is_mod: bool)

@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var game_name_label: Label = %GameNameLabel
@onready var steam_game_path_label: Label = %SteamGamePathLabel
@onready var steam_game_path_row: HBoxContainer = %SteamGamePathRow
@onready var steam_game_path_edit: LineEdit = %SteamGamePathEdit
@onready var browse_button: Button = %BrowseButton
@onready var folder_dialog: FileDialog = %SteamGamePathDialog
@onready var thumbnail_browse_button: Button = %ThumbnailBrowseButton
@onready var thumbnail_dialog: FileDialog = %ThumbnailDialog

var current_is_mod := false
var selected_thumbnail_path := ""

func _ready() -> void:
	browse_button.pressed.connect(_on_browse_pressed)
	thumbnail_browse_button.pressed.connect(_on_thumbnail_browse_pressed)
	confirmed.connect(_on_confirmed)
	folder_dialog.dir_selected.connect(_on_directory_selected)
	thumbnail_dialog.file_selected.connect(_on_thumbnail_selected)

func open_dialog(config: Dictionary, is_mod: bool = false) -> void:
	current_is_mod = is_mod
	title = "Mod Settings" if is_mod else "Game Settings"
	game_name_label.text = "Mod Name" if is_mod else "Game Name"
	game_name_edit.text = str(config.get("name", ""))
	steam_game_path_edit.text = str(config.get("steam_game_path", ""))
	selected_thumbnail_path = ""
	steam_game_path_label.visible = !is_mod
	steam_game_path_row.visible = !is_mod
	popup_centered()
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
	var game_name := game_name_edit.text.strip_edges()
	if(game_name.is_empty()):
		Global.alert(tr("error.game_name_empty"))
		return
	var steam_game_path := ""
	if(!current_is_mod):
		steam_game_path = steam_game_path_edit.text.strip_edges()
	settings_saved.emit(game_name, steam_game_path, selected_thumbnail_path.strip_edges(), current_is_mod)
