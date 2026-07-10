# scenes/status_bar/status_bar.gd
class_name AppStatusBar
extends HBoxContainer

@onready var indicator:   Label = $MarginContainer/InnerBar/ConnectionIndicator
@onready var server_lbl:  Label = $MarginContainer/InnerBar/ServerLabel
@onready var message_lbl: Label = $MarginContainer/InnerBar/MessageLabel
@onready var time_lbl:    Label = $MarginContainer/InnerBar/TimeLabel

@onready var _clock_timer: Timer = $Timer

func _ready() -> void:
    _setup_clock_timer()
    _update_time()
    set_disconnected()

func _setup_clock_timer() -> void:
    _clock_timer.timeout.connect(_update_time)

func _update_time() -> void:
    var t: Dictionary = Time.get_time_dict_from_system()
    time_lbl.text = "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

func set_connected(url: String) -> void:
    indicator.text  = "🟢 Connected"
    server_lbl.text = "Server: %s" % url

func set_disconnected() -> void:
    indicator.text  = "🔴 Disconnected"
    server_lbl.text = "Server: —"

func show_message(text: String) -> void:
    message_lbl.text = text
    await get_tree().create_timer(3.0).timeout
    message_lbl.text = ""
