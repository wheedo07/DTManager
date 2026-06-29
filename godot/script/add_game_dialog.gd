extends PanelContainer

signal game_created(game_name: String, executable_path: String)

@onready var title_label: Label = %TitleLabel
@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var game_exe_edit: LineEdit = %GameExeEdit
@onready var browse_button: Button = %BrowseButton
@onready var create_button: Button = %CreateButton
@onready var close_button: Button = %CloseButton
@onready var game_exe_dialog: FileDialog = %GameExeDialog

func open_dialog() -> void:
	title_label.text = tr("ui.dialog.add_game")
	game_name_edit.text = ""
	game_exe_edit.text = ""
	Global.show_centered(self)
	game_name_edit.grab_focus()

func _on_browse_pressed() -> void:
	game_exe_dialog.popup_centered_ratio(0.8)

func _on_game_exe_selected(path: String) -> void:
	game_exe_edit.text = path
	if(game_name_edit.text.is_empty()):
		game_name_edit.text = path.get_file().get_basename()

func _on_confirmed() -> void:
	var game_name := game_name_edit.text.strip_edges()
	var executable_path := game_exe_edit.text.strip_edges()

	if(game_name.is_empty()):
		Global.alert(tr("error.game_name_empty"))
		return
	if(executable_path.is_empty()):
		Global.alert(tr("error.executable_path_empty"))
		return

	game_created.emit(game_name, executable_path)
