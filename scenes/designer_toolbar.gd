# scenes/designer_toolbar.gd
extends HBoxContainer

signal mode_toggled(is_edit: bool)
signal layout_save_requested(name: String)
signal layout_load_requested(name: String)

var _is_edit_mode: bool = false

@onready var toggle_btn:  Button = $ToggleModeButton
@onready var save_btn:    Button = $SaveButton
@onready var load_btn:    Button = $LoadButton
@onready var connect_btn: Button = $ConnectButton

func _ready() -> void:
    toggle_btn.pressed.connect(_on_toggle_pressed)
    save_btn.pressed.connect(_on_save_pressed)
    connect_btn.pressed.connect(
        func(): $ConnectionDialog.popup_centered()
    )

func _on_toggle_pressed() -> void:
    _is_edit_mode = not _is_edit_mode
    toggle_btn.text = "▶ Run" if _is_edit_mode else "✏️ Edit"
    emit_signal("mode_toggled", _is_edit_mode)

func _on_save_pressed() -> void:
    emit_signal("layout_save_requested", "default")
