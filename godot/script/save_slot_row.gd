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

func _ready() -> void:
	main_button.pressed.connect(func() -> void: selected.emit(slot_name))
	menu_button.pressed.connect(func() -> void: menu_requested.emit(slot_name, menu_button.get_global_rect()))
	main_button.mouse_entered.connect(func() -> void: _apply_state(true))
	main_button.mouse_exited.connect(func() -> void: _apply_state(false))
	menu_button.mouse_entered.connect(func() -> void: _apply_state(true))
	menu_button.mouse_exited.connect(func() -> void: _apply_state(false))

func setup(p_slot_name: String, p_selected: bool) -> void:
	slot_name = p_slot_name
	is_selected = p_selected
	name_label.text = p_slot_name
	_apply_state(false)

func _apply_state(hovered: bool) -> void:
	state_label.text = tr("ui.mod.state_active") if is_selected else tr("ui.save.slot")
	name_label.modulate = Color(1, 0.9, 0.12, 1) if hovered else Color(1, 1, 1, 1)
	state_label.modulate = Color(1, 0.9, 0.12, 1) if hovered || is_selected else Color(0.72, 0.72, 0.72, 1)
	accent_bar.color = Color(1, 0.9, 0.12, 1) if hovered || is_selected else Color(0.24, 0.24, 0.24, 1)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 1) if hovered || is_selected else Color(0, 0, 0, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 0.9, 0.12, 1) if hovered || is_selected else Color(0.45, 0.45, 0.45, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card_panel.add_theme_stylebox_override("panel", style)
