extends Button

signal mod_selected(index: int)

@onready var card_panel: PanelContainer = %CardPanel
@onready var accent_bar: ColorRect = %AccentBar
@onready var name_label: Label = %NameLabel
@onready var state_label: Label = %StateLabel

var mod_index := 0
var selected := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(func() -> void: _apply_state(true))
	mouse_exited.connect(func() -> void: _apply_state(false))


func setup(mod_name: String, is_selected: bool, index: int) -> void:
	mod_index = index
	selected = is_selected
	name_label.text = mod_name
	_apply_state(false)


func _on_pressed() -> void:
	mod_selected.emit(mod_index)


func _apply_state(hovered: bool) -> void:
	state_label.text = "ACTIVE" if selected else "MOD"
	name_label.modulate = Color(1, 0.9, 0.12, 1) if hovered else Color(1, 1, 1, 1)
	state_label.modulate = Color(1, 0.9, 0.12, 1) if hovered || selected else Color(0.72, 0.72, 0.72, 1)
	accent_bar.color = Color(1, 0.9, 0.12, 1) if hovered || selected else Color(0.24, 0.24, 0.24, 1)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 1) if hovered || selected else Color(0, 0, 0, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 0.9, 0.12, 1) if hovered || selected else Color(0.45, 0.45, 0.45, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card_panel.add_theme_stylebox_override("panel", style)
