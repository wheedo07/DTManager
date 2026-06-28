extends PanelContainer

signal mod_created(mod_name: String, source_path: String)

@onready var title_label: Label = %TitleLabel
@onready var mod_name_edit: LineEdit = %ModNameEdit
@onready var mod_source_edit: LineEdit = %ModSourceEdit
@onready var browse_button: Button = %BrowseButton
@onready var create_button: Button = %CreateButton
@onready var close_button: Button = %CloseButton
@onready var mod_source_dialog: FileDialog = %ModSourceDialog
var picker_active := false

func open_dialog(base_mod_name: String = "") -> void:
	mod_name_edit.text = ""
	mod_source_edit.text = ""
	title_label.text = tr("ui.dialog.add_mod") if base_mod_name.is_empty() else "Patch %s" % base_mod_name
	_show_centered()
	mod_name_edit.grab_focus()

func _on_browse_pressed() -> void:
	picker_active = true
	mod_source_dialog.popup_centered_ratio(0.8)

func _on_mod_source_selected(path: String) -> void:
	mod_source_edit.text = path
	if(mod_name_edit.text.is_empty()):
		mod_name_edit.text = path.get_file().get_basename()
	call_deferred("_finish_picker_interaction")

func _on_picker_canceled() -> void:
	call_deferred("_finish_picker_interaction")

func _finish_picker_interaction() -> void:
	picker_active = false

func _show_centered() -> void:
	show()
	position = (get_viewport_rect().size - size) * 0.5

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
