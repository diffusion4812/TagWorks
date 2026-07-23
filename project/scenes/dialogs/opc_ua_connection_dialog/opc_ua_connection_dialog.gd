# ui/dialogs/opc_ua_connection_dialog.gd
class_name OpcUaConnectionDialog
extends Window

# ── Tree ──────────────────────────────────────────────────────────────────────
@onready var server_tree:             OpcUaServerTree       = %ServerTree
@onready var add_server_button:       Button                = %AddServerButton
@onready var add_group_button:        Button                = %AddGroupButton
@onready var remove_button:           Button                = %RemoveButton

# ── Right panel ───────────────────────────────────────────────────────────────
@onready var no_selection_label:      Label                 = %NoSelectionLabel
@onready var server_detail_form:      OpcUaServerDetailForm = %ServerDetailForm
@onready var group_detail_form:       OpcUaGroupDetailForm  = %GroupDetailForm

# ── Footer ────────────────────────────────────────────────────────────────────
@onready var test_button:              Button        = %TestButton
@onready var browse_button:            Button        = %BrowseButton
@onready var status_button:            Button        = %StatusButton
@onready var close_button:             Button        = %CloseButton

# ── State ─────────────────────────────────────────────────────────────────────

enum SelectionType { NONE, SERVER, GROUP }

var _selection_type:       SelectionType   = SelectionType.NONE
var _selected_server_id:   String          = ""
var _selected_group_id:    String          = ""
var _form_dirty:           bool            = false
var _commit_pending:       bool            = false
var _bound_project:        ReactiveProject = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _connect_signals()
    _rebind_project_signal()
    _refresh_tree()
    _set_panel(SelectionType.NONE)


func _connect_signals() -> void:
    add_server_button.pressed.connect(_on_add_server_pressed)
    add_group_button.pressed.connect(_on_add_group_pressed)
    remove_button.pressed.connect(_on_remove_pressed)

    server_tree.server_selected.connect(_on_server_selected)
    server_tree.group_selected.connect(_on_group_selected)
    server_tree.selection_cleared.connect(_on_selection_cleared)

    test_button.pressed.connect(_on_test_pressed)
    browse_button.pressed.connect(_on_browse_pressed)
    close_button.pressed.connect(_on_close_pressed)
    status_button.pressed.connect(_on_status_pressed)

    server_detail_form.edited.connect(_on_form_edited)
    group_detail_form.edited.connect(_on_form_edited)

    OpcUaManager.connection_failed.connect(_on_server_connection_failed)

    # React to the *active project itself* changing (load / unload / switch)
    AppState.current_project.changed.connect(_on_current_project_changed)

# ── Project access helpers ────────────────────────────────────────────────────

func _has_project() -> bool:
    return AppState.current_project.value != null


func _project() -> ReactiveProject:
    return AppState.current_project.value


func _servers() -> Array[OpcUaServerConfig]:
    var project: ReactiveProject = _project()
    if project == null:
        return []
    return project.servers


func _get_server(server_id: String) -> OpcUaServerConfig:
    if server_id == "":
        return null
    for cfg: OpcUaServerConfig in _servers():
        if cfg.id == server_id:
            return cfg
    return null


func _add_server(cfg: OpcUaServerConfig) -> void:
    if not _has_project():
        return
    _servers().append(cfg)
    _notify_project_changed()


func _remove_server(server_id: String) -> void:
    if not _has_project():
        return
    var servers: Array[OpcUaServerConfig] = _servers()
    for i: int in servers.size():
        if servers[i].id == server_id:
            servers.remove_at(i)
            break
    _notify_project_changed()


func _notify_project_changed() -> void:
    var project: ReactiveProject = _project()
    if project != null:
        project.changed.emit()

# ── Project (re)binding ───────────────────────────────────────────────────────

func _on_current_project_changed() -> void:
    _rebind_project_signal()

    _selection_type     = SelectionType.NONE
    _selected_server_id = ""
    _selected_group_id  = ""
    server_tree.clear_selection()
    _set_panel(SelectionType.NONE)

    _refresh_tree()


func _rebind_project_signal() -> void:
    if _bound_project != null and _bound_project.changed.is_connected(_refresh_tree):
        _bound_project.changed.disconnect(_refresh_tree)

    _bound_project = _project()

    if _bound_project != null:
        _bound_project.changed.connect(_refresh_tree, CONNECT_DEFERRED)

# ── Tree refresh ──────────────────────────────────────────────────────────────

func _refresh_tree() -> void:
    if not is_node_ready():
        return

    var has_project: bool = _has_project()

    add_server_button.disabled = not has_project
    server_tree.visible        = has_project
    no_selection_label.text    = "No project loaded." if not has_project else "No selection."

    if not has_project:
        server_tree.clear_selection()
        _set_panel(SelectionType.NONE)
        return

    server_tree.set_servers(_servers())

# ── Panel switching ───────────────────────────────────────────────────────────

func _set_panel(type: SelectionType) -> void:
    no_selection_label.visible = (type == SelectionType.NONE)
    server_detail_form.visible = (type == SelectionType.SERVER)
    group_detail_form.visible  = (type == SelectionType.GROUP)

    add_group_button.disabled  = (not _has_project()) or (_selected_server_id == "")
    remove_button.disabled     = (type == SelectionType.NONE)

    var server_selected: bool = (type == SelectionType.SERVER)
    test_button.visible       = server_selected
    browse_button.visible     = server_selected
    status_button.visible     = server_selected

# ── Form loading ──────────────────────────────────────────────────────────────

func _load_server_form(server_id: String) -> void:
    var cfg: OpcUaServerConfig = _get_server(server_id)
    if cfg == null:
        return

    _form_dirty = false
    server_detail_form.load_config(cfg)
    _form_dirty = false


func _load_group_form(server_id: String, group_id: String) -> void:
    var cfg: OpcUaServerConfig = _get_server(server_id)
    var group: OpcUaSubscriptionGroupConfig = cfg.get_group(group_id) if cfg else null
    if group == null:
        return

    _form_dirty = false
    group_detail_form.load_config(group)
    _form_dirty = false

# ── Form commit ───────────────────────────────────────────────────────────────

func _commit_form() -> void:
    if not _form_dirty:
        return
    if not _has_project():
        _form_dirty = false
        return

    match _selection_type:
        SelectionType.SERVER:
            _commit_server_form()
        SelectionType.GROUP:
            _commit_group_form()

    _form_dirty = false
    _refresh_tree()


func _commit_server_form() -> void:
    var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
    if cfg == null:
        return

    server_detail_form.commit_to(cfg)
    _notify_project_changed()


func _commit_group_form() -> void:
    var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
    var group: OpcUaSubscriptionGroupConfig = cfg.get_group(_selected_group_id) if cfg else null
    if group == null:
        return

    group_detail_form.commit_to(group)
    _notify_project_changed()

# ── Tree selection handlers ───────────────────────────────────────────────────

func _on_server_selected(server_id: String) -> void:
    _commit_form()
    _selection_type     = SelectionType.SERVER
    _selected_server_id = server_id
    _selected_group_id  = ""
    _load_server_form(server_id)
    _set_panel(SelectionType.SERVER)


func _on_group_selected(server_id: String, group_id: String) -> void:
    _commit_form()
    _selection_type     = SelectionType.GROUP
    _selected_server_id = server_id
    _selected_group_id  = group_id
    _load_group_form(server_id, group_id)
    _set_panel(SelectionType.GROUP)


func _on_selection_cleared() -> void:
    _commit_form()
    _selection_type     = SelectionType.NONE
    _selected_server_id = ""
    _selected_group_id  = ""
    _set_panel(SelectionType.NONE)

# ── Add / Remove ──────────────────────────────────────────────────────────────

func _on_add_server_pressed() -> void:
    if not _has_project():
        OS.alert("Please load or create a project before adding an OPC UA server.", "No Project Loaded")
        return

    _commit_form()

    var cfg: OpcUaServerConfig = OpcUaServerConfig.new()
    cfg.id           = "server_%d" % Time.get_ticks_msec()
    cfg.display_name = "New Server"
    cfg.endpoint_url = "opc.tcp://127.0.0.1:4840"

    _add_server(cfg)
    OpcUaManager.add_server(cfg)

    server_tree.set_servers(_servers())
    server_tree.select_server(cfg.id)


func _on_add_group_pressed() -> void:
    if not _has_project() or _selected_server_id == "":
        return

    _commit_form()

    var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
    if cfg == null:
        return

    var group: OpcUaSubscriptionGroupConfig = OpcUaSubscriptionGroupConfig.new()
    group.id              = "group_%d" % Time.get_ticks_msec()
    group.display_name    = "New Group"
    group.pub_interval_ms = 500.0
    cfg.add_group(group)

    _notify_project_changed()

    server_tree.set_servers(_servers())
    server_tree.select_group(_selected_server_id, group.id)


func _on_remove_pressed() -> void:
    if not _has_project():
        return

    _commit_form()

    match _selection_type:
        SelectionType.SERVER:
            OpcUaManager.remove_server(_selected_server_id)
            _remove_server(_selected_server_id)
            _selected_server_id = ""
            _selection_type     = SelectionType.NONE

        SelectionType.GROUP:
            var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
            if cfg:
                cfg.remove_group(_selected_group_id)
                _notify_project_changed()
            _selected_group_id = ""
            _selection_type    = SelectionType.SERVER

    server_tree.set_servers(_servers())

    if _selection_type == SelectionType.SERVER:
        server_tree.select_server(_selected_server_id)
    else:
        server_tree.clear_selection()

    _set_panel(_selection_type)

# ── Connection buttons ────────────────────────────────────────────────────────

func _on_test_pressed() -> void:
    _commit_form()
    var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
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

    var cfg: OpcUaServerConfig = _get_server(_selected_server_id)
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

# ── Form dirty tracking ───────────────────────────────────────────────────────

func _on_form_edited() -> void:
    _form_dirty = true
    if not _commit_pending:
        _commit_pending = true
        call_deferred("_deferred_commit")


func _deferred_commit() -> void:
    _commit_pending = false
    _commit_form()

# ── OpcUaManager signals ──────────────────────────────────────────────────────

func _on_server_connection_failed(server_id: String) -> void:
    if server_id == _selected_server_id:
        OS.alert(
            "Could not reconnect after maximum attempts.",
            "Connection Failed — %s" % _selected_server_id
        )
