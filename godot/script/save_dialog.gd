extends PanelContainer

const SAVE_SLOT_ROW_SCENE := preload("res://scenes/save_slot_row.tscn")

signal backup_requested(game_name: String, slot_name: String)
signal restore_requested(game_name: String, slot_name: String)
signal rename_requested(game_name: String, old_name: String, new_name: String)
signal delete_requested(game_name: String, slot_name: String)
signal import_zip_requested(game_name: String, slot_name: String, zip_path: String)
signal export_zip_requested(game_name: String, slot_name: String, zip_path: String)

const MENU_RESTORE_SELECTED := 1
const MENU_EXPORT_ZIP := 2
const MENU_RENAME_SELECTED := 3
const MENU_DELETE_SELECTED := 4

@onready var game_name_label: Label = %GameNameLabel
@onready var save_path_label: Label = %SavePathValue
@onready var slot_list: VBoxContainer = %SlotList
@onready var empty_label: Label = %EmptyLabel
@onready var rename_row: HBoxContainer = %RenameRow
@onready var rename_edit: LineEdit = %RenameEdit
@onready var backup_button: Button = %BackupButton
@onready var import_button: Button = %ImportButton
@onready var close_button: Button = %CloseButton
@onready var context_menu: PopupMenu = %ContextMenu
@onready var import_zip_dialog: FileDialog = %ImportZipDialog
@onready var export_zip_dialog: FileDialog = %ExportZipDialog

var current_game_name := ""
var editing_slot_name := ""
var selected_slot_name := ""
var current_slots: Array[String] = []

func open_dialog(game_name: String, save_path: String, slots: Array[String]) -> void:
	current_game_name = game_name
	editing_slot_name = ""
	selected_slot_name = ""
	game_name_label.text = game_name
	save_path_label.text = save_path
	_set_slots(slots)
	_hide_rename()
	Global.show_centered(self)

func refresh_slots(slots: Array[String]) -> void:
	_set_slots(slots, selected_slot_name)

func get_selected_slot_name() -> String:
	return selected_slot_name

func _set_slots(slots: Array[String], selected_slot: String = "") -> void:
	current_slots = slots.duplicate()
	for child in slot_list.get_children():
		child.queue_free()
	selected_slot_name = selected_slot if slots.has(selected_slot) else ""
	for slot_name_value in slots:
		var slot_name := str(slot_name_value)
		var row = SAVE_SLOT_ROW_SCENE.instantiate()
		row.selected.connect(_on_slot_selected)
		row.menu_requested.connect(_on_slot_menu_requested)
		slot_list.add_child(row)
		row.setup(slot_name, slot_name == selected_slot_name)
	empty_label.visible = slots.is_empty()
	slot_list.visible = !slots.is_empty()

func _on_slot_selected(slot_name: String) -> void:
	_hide_rename()
	_set_slots(current_slots, slot_name)

func _on_slot_menu_requested(slot_name: String, anchor_rect: Rect2) -> void:
	_hide_rename()
	_set_slots(current_slots, slot_name)
	_open_context_menu(anchor_rect)

func _emit_backup_current() -> void:
	var slot_name := _build_slot_name()
	backup_requested.emit(current_game_name, slot_name)

func _emit_restore_selected() -> void:
	var slot_name := get_selected_slot_name()
	if(slot_name.is_empty()):
		Global.alert(tr("error.no_save_slot_selected"))
		return
	restore_requested.emit(current_game_name, slot_name)

func _emit_delete_selected() -> void:
	var slot_name := get_selected_slot_name()
	if(slot_name.is_empty()):
		Global.alert(tr("error.no_save_slot_selected"))
		return
	delete_requested.emit(current_game_name, slot_name)

func _open_import_zip_dialog() -> void:
	import_zip_dialog.popup_centered_ratio(0.8)

func _open_export_zip_dialog(slot_name: String) -> void:
	export_zip_dialog.current_file = "%s.zip" % slot_name
	export_zip_dialog.popup_centered_ratio(0.8)

func _begin_rename_selected(slot_name: String) -> void:
	editing_slot_name = slot_name
	rename_row.visible = true
	rename_edit.text = slot_name
	rename_edit.grab_focus()
	rename_edit.select_all()

func _open_context_menu(anchor_rect: Rect2) -> void:
	context_menu.clear()
	var slot_name := get_selected_slot_name()
	if(!slot_name.is_empty()):
		context_menu.add_item(tr("ui.save.restore_selected"), MENU_RESTORE_SELECTED)
		context_menu.add_item(tr("ui.save.export_zip"), MENU_EXPORT_ZIP)
		context_menu.add_item(tr("ui.save.rename_selected"), MENU_RENAME_SELECTED)
		context_menu.add_item(tr("ui.save.delete_selected"), MENU_DELETE_SELECTED)
	context_menu.reset_size()
	context_menu.popup(anchor_rect)

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		MENU_EXPORT_ZIP:
			var slot_name := get_selected_slot_name()
			if(slot_name.is_empty()):
				Global.alert(tr("error.no_save_slot_selected"))
				return
			_open_export_zip_dialog(slot_name)
		MENU_RESTORE_SELECTED:
			_emit_restore_selected()
		MENU_RENAME_SELECTED:
			var slot_name := get_selected_slot_name()
			if(slot_name.is_empty()):
				Global.alert(tr("error.no_save_slot_selected"))
				return
			_begin_rename_selected(slot_name)
		MENU_DELETE_SELECTED:
			_emit_delete_selected()

func _on_import_zip_selected(path: String) -> void:
	var slot_name := path.get_file().get_basename().strip_edges()
	if(slot_name.is_empty()):
		slot_name = _build_slot_name()
	while _has_slot_name(slot_name):
		slot_name = _next_slot_name(slot_name)
	import_zip_requested.emit(current_game_name, slot_name, path)

func _on_export_zip_selected(path: String) -> void:
	var slot_name := get_selected_slot_name()
	if(slot_name.is_empty()):
		Global.alert(tr("error.no_save_slot_selected"))
		return
	var target_path := path
	if(!target_path.to_lower().ends_with(".zip")):
		target_path += ".zip"
	export_zip_requested.emit(current_game_name, slot_name, target_path)

func _on_rename_submitted(new_name: String) -> void:
	if(editing_slot_name.is_empty()):
		return
	var trimmed_name := new_name.strip_edges()
	if(trimmed_name.is_empty()):
		Global.alert(tr("error.save_slot_name_empty"))
		return
	rename_requested.emit(current_game_name, editing_slot_name, trimmed_name)

func _hide_rename() -> void:
	editing_slot_name = ""
	rename_row.visible = false
	rename_edit.text = ""

func _build_slot_name() -> String:
	var slot_index := current_slots.size() + 1
	var slot_name := "slot_%d" % slot_index
	while _has_slot_name(slot_name):
		slot_index += 1
		slot_name = "slot_%d" % slot_index
	return slot_name

func _has_slot_name(slot_name: String) -> bool:
	for current_slot in current_slots:
		if(str(current_slot) == slot_name): return true;
	return false

func _next_slot_name(slot_name: String) -> String:
	var regex := RegEx.new()
	if(regex.compile("^slot_(\\d+)$") != OK):
		return slot_name + "_1"
	var match := regex.search(slot_name)
	if(match == null):
		return slot_name + "_1"
	return "slot_%d" % (int(match.get_string(1)) + 1)
