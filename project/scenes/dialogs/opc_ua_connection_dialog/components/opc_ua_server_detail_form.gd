# ui/components/opc_ua_server_detail_form.gd
class_name OpcUaServerDetailForm
extends VBoxContainer

## Emitted whenever the user changes a field (after focus loss for text
## fields, immediately for discrete controls). Does NOT fire while
## load_config() is populating the form.
signal edited

@onready var display_name_edit:        LineEdit      = %DisplayNameEdit
@onready var endpoint_edit:            LineEdit      = %EndpointEdit
@onready var security_policy_option:   OptionButton  = %SecurityPolicyOption
@onready var message_mode_option:      OptionButton  = %MessageModeOption
@onready var username_edit:            LineEdit      = %UsernameEdit
@onready var password_edit:            LineEdit      = %PasswordEdit
@onready var poll_interval_spin:       SpinBox       = %PollIntervalSpin
@onready var reconnect_interval_spin:  SpinBox       = %ReconnectIntervalSpin
@onready var max_attempts_spin:        SpinBox       = %MaxAttemptsSpin

var _loading: bool = false

func _ready() -> void:
    _populate_option_buttons()
    _connect_signals()


func _populate_option_buttons() -> void:
    security_policy_option.clear()
    for policy: String in ["None", "Basic128Rsa15", "Basic256", "Basic256Sha256"]:
        security_policy_option.add_item(policy)

    message_mode_option.clear()
    for message_mode: String in ["None", "Sign", "SignAndEncrypt"]:
        message_mode_option.add_item(message_mode)


func _connect_signals() -> void:
    display_name_edit.focus_exited.connect(_emit_edited)
    endpoint_edit.focus_exited.connect(_emit_edited)
    username_edit.focus_exited.connect(_emit_edited)
    password_edit.focus_exited.connect(_emit_edited)

    security_policy_option.item_selected.connect(_emit_edited.unbind(1))
    message_mode_option.item_selected.connect(_emit_edited.unbind(1))
    poll_interval_spin.value_changed.connect(_emit_edited.unbind(1))
    reconnect_interval_spin.value_changed.connect(_emit_edited.unbind(1))
    max_attempts_spin.value_changed.connect(_emit_edited.unbind(1))


func _emit_edited() -> void:
    if _loading:
        return
    edited.emit()

# ── Public API ─────────────────────────────────────────────────────────────

func load_config(cfg: ReactiveOpcUaServer) -> void:
    _loading = true

    display_name_edit.text         = cfg.display_name.value
    endpoint_edit.text             = cfg.endpoint_url.value
    username_edit.text             = cfg.username.value
    password_edit.text             = cfg.password.value
    poll_interval_spin.value       = cfg.poll_interval_sec.value
    reconnect_interval_spin.value  = cfg.reconnect_interval_sec.value
    max_attempts_spin.value        = cfg.max_reconnect_attempts.value

    _select_option(security_policy_option, cfg.security_policy.value)
    _select_option(message_mode_option,    cfg.message_mode.value)

    _loading = false


func commit_to(cfg: ReactiveOpcUaServer) -> void:
    cfg.display_name.value           = display_name_edit.text.strip_edges()
    cfg.endpoint_url.value           = endpoint_edit.text.strip_edges()
    cfg.security_policy.value        = security_policy_option.get_item_text(
                                     security_policy_option.selected)
    cfg.message_mode.value           = message_mode_option.get_item_text(
                                     message_mode_option.selected)
    cfg.username.value               = username_edit.text.strip_edges()
    cfg.password.value               = password_edit.text
    cfg.poll_interval_sec.value      = poll_interval_spin.value
    cfg.reconnect_interval_sec.value = reconnect_interval_spin.value
    cfg.max_reconnect_attempts.value = int(max_attempts_spin.value)

# ── Utility ────────────────────────────────────────────────────────────────

func _select_option(option: OptionButton, value: String) -> void:
    for i: int in option.item_count:
        if option.get_item_text(i) == value:
            option.select(i)
            return
