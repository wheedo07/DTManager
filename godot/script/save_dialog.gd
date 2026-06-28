extends AcceptDialog

signal backup_requested(game_name: String, slot_name: String)
signal restore_requested(game_name: String, slot_name: String)

@onready var game_name_label: Label = %GameNameLabel
@onready var save_path_label: Label = %SavePathValue
@onready var slot_list: ItemList = %SlotList
@onready var empty_label: Label = %EmptyLabel
@onready var backup_button: Button = %BackupButton
@onready var restore_button: Button = %RestoreButton

var current_game_name := ""

func _ready() -> void:
	backup_button.pressed.connect(_on_backup_pressed)
	restore_button.pressed.connect(_on_restore_pressed)
	slot_list.item_selected.connect(func(_index: int) -> void: _refresh_actions())
	slot_list.empty_clicked.connect(func(_at_position: Vector2, _mouse_button_index: int) -> void:
		slot_list.deselect_all()
		_refresh_actions()
	)

func open_dialog(game_name: String, save_path: String, slots: Array[String]) -> void:
	current_game_name = game_name
	game_name_label.text = game_name
	save_path_label.text = save_path
	_set_slots(slots)
	popup_centered()

func refresh_slots(slots: Array[String]) -> void:
	var selected_slot := get_selected_slot_name()
	_set_slots(slots, selected_slot)

func get_selected_slot_name() -> String:
	var selected := slot_list.get_selected_items()
	if(selected.is_empty()): return "";
	return slot_list.get_item_text(selected[0])

func _notification(what: int) -> void:
	if(what != NOTIFICATION_WM_WINDOW_FOCUS_OUT || !visible): return;
	hide()

func _set_slots(slots: Array[String], selected_slot: String = "") -> void:
	slot_list.clear()
	var selected_index := -1
	for index in range(slots.size()):
		var slot_name := str(slots[index])
		slot_list.add_item(slot_name)
		if(slot_name == selected_slot):
			selected_index = index
	empty_label.visible = slots.is_empty()
	slot_list.visible = !slots.is_empty()
	if(selected_index >= 0):
		slot_list.select(selected_index)
	_refresh_actions()

func _refresh_actions() -> void:
	restore_button.disabled = get_selected_slot_name().is_empty()

func _on_backup_pressed() -> void:
	var slot_name := _build_slot_name()
	backup_requested.emit(current_game_name, slot_name)

func _on_restore_pressed() -> void:
	var slot_name := get_selected_slot_name()
	if(slot_name.is_empty()):
		Global.alert(tr("error.no_save_slot_selected"))
		return
	restore_requested.emit(current_game_name, slot_name)

func _build_slot_name() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "slot_%04d%02d%02d_%02d%02d%02d" % [
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]
