extends PanelContainer

signal confirmed

@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %DeleteConfirmLabel
@onready var confirm_button: Button = %ConfirmButton

func open_dialog(message: String, title: String = "ui.common.delete", confirm_text: String = "ui.common.delete") -> void:
	title_label.text = tr(title)
	message_label.text = message
	confirm_button.text = tr(confirm_text)
	Global.show_centered(self)

func _on_confirm_pressed() -> void:
	hide()
	confirmed.emit()
