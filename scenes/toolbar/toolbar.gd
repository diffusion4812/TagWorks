# scenes/toolbar/toolbar.gd
class_name Toolbar
extends HBoxContainer

signal mode_toggled(is_edit: bool)
signal save_requested(layout_name: String)
signal load_requested(layout_name: String)
signal connect_pressed()

var _is_edit: bool = false

@onready var mode_btn:    Button = $ToggleModeButton
@onready var save_btn:    Button = $SaveButton
@onready var load_btn:    Button = $LoadButton
@onready var connect_btn: Button = $ConnectButton

func _ready() -> void:
    mode_btn.pressed.connect(_on_mode_pressed)
    save_btn.pressed.connect(func(): save_requested.emit("default"))
    load_btn.pressed.connect(func(): load_requested.emit("default"))
    connect_btn.pressed.connect(func(): connect_pressed.emit())
    _update_mode_button()

func _on_mode_pressed() -> void:
    _is_edit = not _is_edit
    mode_toggled.emit(_is_edit)
    _update_mode_button()

func _update_mode_button() -> void:
    mode_btn.text = "▶ Run Mode" if _is_edit else "✏️ Edit Mode"
    save_btn.visible = _is_edit
    load_btn.visible = _is_edit
