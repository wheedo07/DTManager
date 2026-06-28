extends HBoxContainer

signal selected(slot_name: String)
signal menu_requested(slot_name: String, anchor_rect: Rect2)

@onready var main_button: Button = %MainButton
@onready var name_label: Label = %NameLabel
@onready var state_label: Label = %StateLabel
@onready var menu_button: Button = %MenuButton
@onready var accent_bar: ColorRect = %AccentBar
@onready var card_panel: PanelContainer = %CardPanel

var slot_name := ""
var is_selected := false

func setup(p_slot_name: String, p_selected: bool) -> void:
	slot_name = p_slot_name
	is_selected = p_selected
	name_label.text = p_slot_name

func _on_main_button_pressed() -> void:
	selected.emit(slot_name)

func _on_menu_button_pressed() -> void:
	menu_requested.emit(slot_name, menu_button.get_global_rect())
