# ui/dialogs/opc_ua_connection_dialog.gd
class_name OpcUaConnectionDialog
extends Window

# ── Tree ──────────────────────────────────────────────────────────────────────
@onready var server_tree:             Tree          = %ServerTree
@onready var add_server_button:       Button        = %AddServerButton
@onready var add_group_button:        Button        = %AddGroupButton
@onready var remove_button:           Button        = %RemoveButton

# ── Right panel ───────────────────────────────────────────────────────────────
@onready var no_selection_label:      Label         = %NoSelectionLabel
@onready var server_detail_form:      VBoxContainer = %ServerDetailForm
@onready var group_detail_form:       VBoxContainer = %GroupDetailForm

# ── Server form fields ────────────────────────────────────────────────────────
@onready var display_name_edit:        LineEdit      = %DisplayNameEdit
@onready var endpoint_edit:            LineEdit      = %EndpointEdit
@onready var security_policy_option:   OptionButton  = %SecurityPolicyOption
@onready var message_mode_option:      OptionButton  = %MessageModeOption
@onready var username_edit:            LineEdit      = %UsernameEdit
@onready var password_edit:            LineEdit      = %PasswordEdit
@onready var poll_interval_spin:       SpinBox       = %PollIntervalSpin
@onready var reconnect_interval_spin:  SpinBox       = %ReconnectIntervalSpin
@onready var max_attempts_spin:        SpinBox       = %MaxAttemptsSpin

# ── Group form fields ─────────────────────────────────────────────────────────
@onready var group_name_edit:          LineEdit      = %GroupNameEdit
@onready var group_interval_spin:      SpinBox       = %GroupIntervalSpin

# ── Footer ────────────────────────────────────────────────────────────────────
@onready var test_button:              Button        = %TestButton
@onready var browse_button:            Button        = %BrowseButton
@onready var status_button:            Button        = %StatusButton
@onready var close_button:             Button        = %CloseButton

# ── Non-UI related ────────────────────────────────────────────────────────────
@onready var server_status_timer:      Timer         = %ServerStatusTimer

# ── State ─────────────────────────────────────────────────────────────────────

enum SelectionType { NONE, SERVER, GROUP }

var _selection_type:       SelectionType = SelectionType.NONE
var _selected_server_id:   String        = ""
var _selected_group_id:    String        = ""
var _form_dirty:           bool          = false
var _commit_pending:       bool          = false

const STATUS_CONNECTED    :String = "● "
const STATUS_DISCONNECTED :String = "○ "

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _populate_option_buttons()
    _configure_tree()
    _connect_signals()
    _refresh_tree()
    _set_panel(SelectionType.NONE)


func _configure_tree() -> void:
    server_tree.columns           = 2
    server_tree.column_titles_visible = true
    server_tree.set_column_title(0, "Name")
    server_tree.set_column_title(1, "Interval")
    server_tree.set_column_expand(1, false)
    server_tree.set_column_custom_minimum_width(1, 90)
    server_tree.hide_root        = true


func _connect_signals() -> void:
    add_server_button.pressed.connect(_on_add_server_pressed)
    add_group_button.pressed.connect(_on_add_group_pressed)
    remove_button.pressed.connect(_on_remove_pressed)
    server_tree.item_selected.connect(_on_tree_item_selected)

    test_button.pressed.connect(_on_test_pressed)
    browse_button.pressed.connect(_on_browse_pressed)
    close_button.pressed.connect(_on_close_pressed)
    status_button.pressed.connect(_on_status_pressed)

    # Server form fields — commit on focus lost for text inputs
    display_name_edit.focus_exited.connect(_on_form_edited)
    endpoint_edit.focus_exited.connect(_on_form_edited)
    username_edit.focus_exited.connect(_on_form_edited)
    password_edit.focus_exited.connect(_on_form_edited)

    # Discrete controls — commit immediately on change
    security_policy_option.item_selected.connect(_on_form_edited.unbind(1))
    message_mode_option.item_selected.connect(_on_form_edited.unbind(1))
    poll_interval_spin.value_changed.connect(_on_form_edited.unbind(1))
    reconnect_interval_spin.value_changed.connect(_on_form_edited.unbind(1))
    max_attempts_spin.value_changed.connect(_on_form_edited.unbind(1))

    # Group form fields
    group_name_edit.focus_exited.connect(_on_form_edited)
    group_interval_spin.value_changed.connect(_on_form_edited.unbind(1))
    
    # Non-UI related
    server_status_timer.timeout.connect(_on_server_status_timeout)

    OpcUaManager.connected.connect(_on_server_connected)
    OpcUaManager.connection_lost.connect(_on_server_connection_lost)
    OpcUaManager.connection_failed.connect(_on_server_connection_failed)
    ProjectManager.opc_ua_registry.configs_changed.connect(
        _refresh_tree.bind(), CONNECT_DEFERRED
    )


func _populate_option_buttons() -> void:
    security_policy_option.clear()
    for policy: String in ["None", "Basic128Rsa15", "Basic256", "Basic256Sha256"]:
        security_policy_option.add_item(policy)

    message_mode_option.clear()
    for message_mode: String in ["None", "Sign", "SignAndEncrypt"]:
        message_mode_option.add_item(message_mode)

# ── Tree ──────────────────────────────────────────────────────────────────────

func _refresh_tree() -> void:
    if not is_node_ready():
        return
    if server_tree == null:
        return

    server_tree.clear()
    var root: TreeItem = server_tree.create_item()
    if root == null:
        return

    for cfg: OpcUaServerConfig in ProjectManager.opc_ua_registry.get_all_configs():
        var server_item: TreeItem = server_tree.create_item(root)
        var prefix     : String   = STATUS_CONNECTED if OpcUaManager.is_server_connected(cfg.id) \
                                            else STATUS_DISCONNECTED
        server_item.set_text(0, prefix + cfg.display_name)
        server_item.set_text(1, "")
        server_item.set_metadata(0, { "type": "server", "server_id": cfg.id })

        for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
            var group_item: TreeItem = server_tree.create_item(server_item)
            group_item.set_text(0, "  " + group.display_name)
            group_item.set_text(1, "%d ms" % group.pub_interval_ms)
            group_item.set_metadata(0, {
                "type":      "group",
                "server_id": cfg.id,
                "group_id":  group.id
            })

    # Restore previous selection
    _reselect_item()


func _reselect_item() -> void:
    var root: TreeItem = server_tree.get_root()
    if root == null:
        return

    var server_item: TreeItem = root.get_first_child()
    while server_item != null:
        var meta: Dictionary = server_item.get_metadata(0)
        if meta.get("server_id") == _selected_server_id:
            if _selection_type == SelectionType.SERVER:
                server_item.select(0)
                return
            var group_item: TreeItem = server_item.get_first_child()
            while group_item != null:
                var gmeta: Dictionary = group_item.get_metadata(0)
                if gmeta.get("group_id") == _selected_group_id:
                    group_item.select(0)
                    return
                group_item = group_item.get_next()
        server_item = server_item.get_next()

    # Selection no longer valid
    _selection_type     = SelectionType.NONE
    _selected_server_id = ""
    _selected_group_id  = ""
    _set_panel(SelectionType.NONE)

# ── Panel switching ───────────────────────────────────────────────────────────

func _set_panel(type: SelectionType) -> void:
    no_selection_label.visible = (type == SelectionType.NONE)
    server_detail_form.visible = (type == SelectionType.SERVER)
    group_detail_form.visible  = (type == SelectionType.GROUP)

    add_group_button.disabled  = (_selected_server_id == "")
    remove_button.disabled     = (type == SelectionType.NONE)

    var server_selected: bool = (type == SelectionType.SERVER)
    test_button.visible       = server_selected
    browse_button.visible     = server_selected
    status_button.visible     = server_selected

# ── Form loading ──────────────────────────────────────────────────────────────

func _load_server_form(server_id: String) -> void:
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        return

    _form_dirty = false

    display_name_edit.text        = cfg.display_name
    endpoint_edit.text            = cfg.endpoint_url
    username_edit.text            = cfg.username
    password_edit.text            = cfg.password
    poll_interval_spin.value      = cfg.poll_interval_sec
    reconnect_interval_spin.value = cfg.reconnect_interval_sec
    max_attempts_spin.value       = cfg.max_reconnect_attempts

    _select_option(security_policy_option, cfg.security_policy)
    _select_option(message_mode_option,    cfg.message_mode)

    _form_dirty = false


func _load_group_form(server_id: String, group_id: String) -> void:
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
    var group: OpcUaSubscriptionGroupConfig = cfg.get_group(group_id) if cfg else null
    if group == null:
        return

    _form_dirty = false

    group_name_edit.text       = group.display_name
    group_interval_spin.value  = group.pub_interval_ms

    _form_dirty = false

# ── Form commit ───────────────────────────────────────────────────────────────

func _commit_form() -> void:
    if not _form_dirty:
        return

    match _selection_type:
        SelectionType.SERVER:
            _commit_server_form()
        SelectionType.GROUP:
            _commit_group_form()

    _form_dirty = false
    _refresh_tree()


func _commit_server_form() -> void:
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
    if cfg == null:
        return

    cfg.display_name           = display_name_edit.text.strip_edges()
    cfg.endpoint_url           = endpoint_edit.text.strip_edges()
    cfg.security_policy        = security_policy_option.get_item_text(
                                     security_policy_option.selected)
    cfg.message_mode           = message_mode_option.get_item_text(
                                     message_mode_option.selected)
    cfg.username               = username_edit.text.strip_edges()
    cfg.password               = password_edit.text
    cfg.poll_interval_sec      = poll_interval_spin.value
    cfg.reconnect_interval_sec = reconnect_interval_spin.value
    cfg.max_reconnect_attempts = int(max_attempts_spin.value)


func _commit_group_form() -> void:
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
    var group: OpcUaSubscriptionGroupConfig = cfg.get_group(_selected_group_id) if cfg else null
    if group == null:
        return

    group.display_name   = group_name_edit.text.strip_edges()
    group.pub_interval_ms = group_interval_spin.value

# ── Tree selection ────────────────────────────────────────────────────────────

func _on_tree_item_selected() -> void:
    _commit_form()

    var item: TreeItem = server_tree.get_selected()
    if item == null:
        return

    var meta: Dictionary = item.get_metadata(0)
    var type: String     = meta.get("type", "")

    if type == "server":
        _selection_type     = SelectionType.SERVER
        _selected_server_id = meta.get("server_id", "")
        _selected_group_id  = ""
        _load_server_form(_selected_server_id)
        _set_panel(SelectionType.SERVER)

    elif type == "group":
        _selection_type     = SelectionType.GROUP
        _selected_server_id = meta.get("server_id", "")
        _selected_group_id  = meta.get("group_id",  "")
        _load_group_form(_selected_server_id, _selected_group_id)
        _set_panel(SelectionType.GROUP)

# ── Add / Remove ──────────────────────────────────────────────────────────────

func _on_add_server_pressed() -> void:
    _commit_form()

    var cfg: OpcUaServerConfig = OpcUaServerConfig.new()
    cfg.id                     = "server_%d" % Time.get_ticks_msec()
    cfg.display_name           = "New Server"
    cfg.endpoint_url           = "opc.tcp://127.0.0.1:4840"

    ProjectManager.opc_ua_registry.add_config(cfg)
    OpcUaManager.add_server(cfg)

    _selection_type     = SelectionType.SERVER
    _selected_server_id = cfg.id
    _selected_group_id  = ""
    _refresh_tree()


func _on_add_group_pressed() -> void:
    if _selected_server_id == "":
        return

    _commit_form()

    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
    if cfg == null:
        return

    var group: OpcUaSubscriptionGroupConfig = OpcUaSubscriptionGroupConfig.new()
    group.id              = "group_%d" % Time.get_ticks_msec()
    group.display_name    = "New Group"
    group.pub_interval_ms = 500.0
    cfg.add_group(group)

    ProjectManager.opc_ua_registry.mark_dirty(_selected_server_id)

    _selection_type    = SelectionType.GROUP
    _selected_group_id = group.id
    _refresh_tree()


func _on_remove_pressed() -> void:
    _commit_form()

    match _selection_type:
        SelectionType.SERVER:
            OpcUaManager.remove_server(_selected_server_id)
            ProjectManager.opc_ua_registry.remove_config(_selected_server_id)
            _selected_server_id = ""
            _selection_type     = SelectionType.NONE

        SelectionType.GROUP:
            var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
            if cfg:
                cfg.remove_group(_selected_group_id)
            _selected_group_id = ""
            _selection_type    = SelectionType.SERVER

    _refresh_tree()
    _set_panel(_selection_type)

# ── Connection buttons ────────────────────────────────────────────────────────

func _on_test_pressed() -> void:
    _commit_form()
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
    if cfg == null:
        return

    var test_client: GodotOpcUa = GodotOpcUa.new()
    var ok: bool
    if cfg.username.is_empty():
        ok = test_client.connect_to_server(cfg.endpoint_url)
    else:
        ok = test_client.connect_with_credentials(
            cfg.endpoint_url, cfg.username, cfg.password
        )
    test_client.disconnect_server()

    OS.alert(
        "Connection successful." if ok else "Connection failed.",
        "Test Connection — %s" % cfg.display_name
    )

func _on_browse_pressed() -> void:
    if _selected_server_id == "":
        return

    _commit_form()

    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(_selected_server_id)
    if cfg == null:
        return

    var browse_nodes: BrowseNodes = get_node("/root/Main/Dialogs/BrowseNodes")

    if OpcUaManager.is_server_connected(_selected_server_id):
        # Borrow the live managed connection — browse only, no selection
        browse_nodes.open_managed(OpcUaManager, _selected_server_id)
        return

    # Open a temporary connection for browsing
    var temp_client: GodotOpcUa = GodotOpcUa.new()
    var ok: bool
    if cfg.username.is_empty():
        ok = temp_client.connect_to_server(cfg.endpoint_url)
    else:
        ok = temp_client.connect_with_credentials(
            cfg.endpoint_url, cfg.username, cfg.password
        )

    if not ok:
        OS.alert(
            "Could not connect to server for browsing.\nCheck the endpoint and credentials.",
            "Browse Failed — %s" % cfg.display_name
        )
        return

    browse_nodes.open_temporary(temp_client)

func _on_status_pressed() -> void:
    if _selected_server_id == "":
        return

    _commit_form()

    var status_dialog: OpcUaStatusDialog = get_node("/root/Main/Dialogs/OpcUaStatusDialog")

    status_dialog.focus_server(_selected_server_id)
    status_dialog.show()

func _on_close_pressed() -> void:
    _commit_form()
    hide()


func _on_form_edited() -> void:
    _form_dirty = true
    if not _commit_pending:
        _commit_pending = true
        call_deferred("_deferred_commit")

func _deferred_commit() -> void:
    _commit_pending = false
    _commit_form()

# ── OpcUaManager signals ──────────────────────────────────────────────────────

func _on_server_connected(_server_id: String) -> void:
    _refresh_tree()


func _on_server_connection_lost(_server_id: String) -> void:
    _refresh_tree()


func _on_server_connection_failed(server_id: String) -> void:
    _refresh_tree()
    if server_id == _selected_server_id:
        OS.alert(
            "Could not reconnect after maximum attempts.",
            "Connection Failed — %s" % _selected_server_id
        )

# ── Non-UI related ────────────────────────────────────────────────────────────

func _on_server_status_timeout() -> void:
    var root: TreeItem = server_tree.get_root()
    if root == null:
        return

    var server_item: TreeItem = root.get_first_child()
    while server_item != null:
        var meta: Dictionary = server_item.get_metadata(0)
        if meta.get("type") == "server":
            var server_id: String = meta.get("server_id", "")
            var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
            if cfg != null:
                var prefix: String = STATUS_CONNECTED if OpcUaManager.is_server_connected(server_id) \
                                               else STATUS_DISCONNECTED
                server_item.set_text(0, prefix + cfg.display_name)

        server_item = server_item.get_next()
    
# ── Utility ───────────────────────────────────────────────────────────────────

func _select_option(option: OptionButton, value: String) -> void:
    for i: int in option.item_count:
        if option.get_item_text(i) == value:
            option.select(i)
            return
