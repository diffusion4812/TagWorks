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
    AppState.current_project.connect_self_changed(_on_current_project_changed)

# ── Project access helpers ────────────────────────────────────────────────────

func _has_project() -> bool:
    return AppState.current_project.value != null


func _project() -> ReactiveProject:
    return AppState.current_project.value


func _servers() -> Array[ReactiveOpcUaServer]:
    var project: ReactiveProject = _project()
    if project == null:
        return []

    var typed_servers: Array[ReactiveOpcUaServer] = []
    typed_servers.assign(project.opc_ua_servers.value)
    return typed_servers


func _get_server(server_id: String) -> ReactiveOpcUaServer:
    if server_id == "":
        return null
    for cfg: ReactiveOpcUaServer in _servers():
        if cfg.id.value == server_id:
            return cfg
    return null

func _get_group(server: ReactiveOpcUaServer, group_id: String) -> ReactiveOpcUaGroup:
    for group: ReactiveOpcUaGroup in server.groups.value:
        if group.id.value == group_id:
            return group
    return null

func _add_server(cfg: ReactiveOpcUaServer) -> void:
    if not _has_project():
        return
    _project().opc_ua_servers.append(cfg)


func _remove_server(server_id: String) -> void:
    if not _has_project():
        return
    var servers: Array[ReactiveOpcUaServer] = _servers()
    for i: int in servers.size():
        if servers[i].id.value == server_id:
            servers.remove_at(i)
            break

# ── Project (re)binding ───────────────────────────────────────────────────────

func _on_current_project_changed(_project: ReactiveVariant) -> void:
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
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    if cfg == null:
        return

    _form_dirty = false
    server_detail_form.load_config(cfg)
    _form_dirty = false


func _load_group_form(server_id: String, group_id: String) -> void:
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    var group: ReactiveOpcUaGroup = _get_group(cfg, group_id) if cfg else null
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
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    if cfg == null:
        return

    server_detail_form.commit_to(cfg)


func _commit_group_form() -> void:
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var group: ReactiveOpcUaGroup = _get_group(cfg, _selected_group_id) if cfg else null
    if group == null:
        return

    group_detail_form.commit_to(group)

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

    var id: String = "server_%d" % Time.get_ticks_msec()
    var cfg: ReactiveOpcUaServer = ReactiveOpcUaServer.new({}, _bound_project.opc_ua_servers, id)
    cfg.id.value           = id
    cfg.display_name.value = "New Server"
    cfg.endpoint_url.value = "opc.tcp://127.0.0.1:4840"

    _add_server(cfg)

    server_tree.set_servers(_servers())
    server_tree.select_server(cfg.id.value)


func _on_add_group_pressed() -> void:
    if not _has_project() or _selected_server_id == "":
        return

    _commit_form()

    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    if cfg == null:
        return

    var id: String = "group_%d" % Time.get_ticks_msec()
    var group: ReactiveOpcUaGroup = ReactiveOpcUaGroup.new({}, cfg, id)
    group.id.value              = id
    group.display_name.value    = "New Group"
    group.pub_interval_ms.value = 500.0
    cfg.groups.append(group)

    server_tree.set_servers(_servers())
    server_tree.select_group(_selected_server_id, group.id.value)


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
            var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
            if cfg:
                cfg.remove_group(_selected_group_id)
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
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    if cfg == null:
        return

    var test_client: GodotOpcUa = GodotOpcUa.new()
    var ok: bool
    if cfg.username.is_empty():
        ok = test_client.connect_to_server(cfg.endpoint_url.value)
    else:
        ok = test_client.connect_with_credentials(
            cfg.endpoint_url.value, cfg.username.value, cfg.password.value
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

    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
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
        ok = temp_client.connect_to_server(cfg.endpoint_url.value)
    else:
        ok = temp_client.connect_with_credentials(
            cfg.endpoint_url.value, cfg.username.value, cfg.password.value
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
