extends AcceptDialog

signal mod_created(mod_name: String, source_path: String)

@onready var mod_name_edit: LineEdit = %ModNameEdit
@onready var mod_source_edit: LineEdit = %ModSourceEdit
@onready var browse_button: Button = %BrowseButton
@onready var mod_source_dialog: FileDialog = %ModSourceDialog

func _ready() -> void:
	browse_button.pressed.connect(_on_browse_pressed)
	confirmed.connect(_on_confirmed)
	mod_source_dialog.file_selected.connect(_on_mod_source_selected)

func open_dialog(base_mod_name: String = "") -> void:
	mod_name_edit.text = ""
	mod_source_edit.text = ""
	title = "Add Mod" if base_mod_name.is_empty() else "Patch %s" % base_mod_name
	popup_centered()
	mod_name_edit.grab_focus()

func _notification(what: int) -> void:
	if(what != NOTIFICATION_WM_WINDOW_FOCUS_OUT || !visible || mod_source_dialog.visible): return;
	hide()

func _on_browse_pressed() -> void:
	mod_source_dialog.popup_centered_ratio(0.8)

func _on_mod_source_selected(path: String) -> void:
	mod_source_edit.text = path
	if(mod_name_edit.text.is_empty()):
		mod_name_edit.text = path.get_file().get_basename()

func _on_confirmed() -> void:
	var mod_name := mod_name_edit.text.strip_edges()
	var source_path := mod_source_edit.text.strip_edges()

	if(mod_name.is_empty()):
		Global.alert(tr("error.mod_name_empty"))
		return
	if(source_path.is_empty()):
		Global.alert(tr("error.mod_zip_path_empty"))
		return

	mod_created.emit(mod_name, source_path)
