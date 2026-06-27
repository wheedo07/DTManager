extends AcceptDialog

signal game_created(game_name: String, executable_path: String)

@onready var game_name_edit: LineEdit = %GameNameEdit
@onready var game_exe_edit: LineEdit = %GameExeEdit
@onready var browse_button: Button = %BrowseButton
@onready var game_exe_dialog: FileDialog = %GameExeDialog

func _ready() -> void:
	browse_button.pressed.connect(_on_browse_pressed)
	confirmed.connect(_on_confirmed)
	game_exe_dialog.file_selected.connect(_on_game_exe_selected)

func open_dialog() -> void:
	game_name_edit.text = ""
	game_exe_edit.text = ""
	popup_centered()
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
