extends HBoxContainer

signal selected(slot_name: String)
signal menu_requested(slot_name: String, anchor_rect: Rect2)

const DEFAULT_ACCENT_COLOR := Color(0.24, 0.24, 0.24, 1)
const SELECTED_ACCENT_COLOR := Color(1, 0.9, 0.12, 1)
const DEFAULT_NAME_COLOR := Color(1, 1, 1, 1)
const SELECTED_NAME_COLOR := Color(1, 0.96, 0.72, 1)
const DEFAULT_STATE_COLOR := Color(0.72, 0.72, 0.72, 1)
const SELECTED_STATE_COLOR := Color(1, 0.9, 0.12, 1)
const DEFAULT_CARD_MODULATE := Color(1, 1, 1, 1)
const SELECTED_CARD_MODULATE := Color(1.12, 1.08, 0.92, 1)

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
	_apply_selected_state()

func _on_main_button_pressed() -> void:
	selected.emit(slot_name)

func _on_menu_button_pressed() -> void:
	menu_requested.emit(slot_name, menu_button.get_global_rect())

func _apply_selected_state() -> void:
	accent_bar.color = SELECTED_ACCENT_COLOR if is_selected else DEFAULT_ACCENT_COLOR
	name_label.add_theme_color_override("font_color", SELECTED_NAME_COLOR if is_selected else DEFAULT_NAME_COLOR)
	state_label.add_theme_color_override("font_color", SELECTED_STATE_COLOR if is_selected else DEFAULT_STATE_COLOR)
	card_panel.self_modulate = SELECTED_CARD_MODULATE if is_selected else DEFAULT_CARD_MODULATE
