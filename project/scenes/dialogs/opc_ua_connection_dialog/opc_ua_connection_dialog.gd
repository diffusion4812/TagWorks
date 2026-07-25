# ui/dialogs/opc_ua_connection_dialog.gd
class_name OpcUaConnectionDialog
extends Window

# ── Tree ──────────────────────────────────────────────────────────────────────
@onready var server_tree:             OpcUaServerTree       = %ServerTree
@onready var add_server_button:       Button                = %AddServerButton
@onready var add_group_button:        Button                = %AddGroupButton
@onready var add_tag_button:          Button                = %AddTagButton
@onready var remove_button:           Button                = %RemoveButton

# ── Right panel ───────────────────────────────────────────────────────────────
@onready var no_selection_label:      Label                 = %NoSelectionLabel
@onready var server_detail_form:      OpcUaServerDetailForm = %ServerDetailForm
@onready var group_detail_form:       OpcUaGroupDetailForm  = %GroupDetailForm
@onready var tag_detail_form:         OpcUaTagDetailForm    = %TagDetailForm

# ── Footer ────────────────────────────────────────────────────────────────────
@onready var test_button:              Button        = %TestButton
@onready var browse_button:            Button        = %BrowseButton
@onready var status_button:            Button        = %StatusButton
@onready var confirm_button:           Button        = %ConfirmButton
@onready var close_button:             Button        = %CloseButton

# ── State ─────────────────────────────────────────────────────────────────────

enum SelectionType { NONE, SERVER, GROUP, TAG }

var _selection_type:       SelectionType   = SelectionType.NONE
var _selected_server_id:   String          = ""
var _selected_group_id:    String          = ""
var _selected_tag_id:      String          = ""
var _form_dirty:           bool            = false
var _commit_pending:       bool            = false
var _bound_project:        ReactiveProject = null
var _picker_active:   bool     = false
var _picker_callback: Callable = Callable()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _connect_signals()
    _rebind_project_signal()
    _refresh_tree()
    _set_panel(SelectionType.NONE)


func _connect_signals() -> void:
    add_server_button.pressed.connect(_on_add_server_pressed)
    add_group_button.pressed.connect(_on_add_group_pressed)
    add_tag_button.pressed.connect(_on_add_tag_pressed)
    remove_button.pressed.connect(_on_remove_pressed)

    server_tree.server_selected.connect(_on_server_selected)
    server_tree.group_selected.connect(_on_group_selected)
    server_tree.tag_selected.connect(_on_tag_selected)
    server_tree.selection_cleared.connect(_on_selection_cleared)

    test_button.pressed.connect(_on_test_pressed)
    browse_button.pressed.connect(_on_browse_pressed)
    status_button.pressed.connect(_on_status_pressed)
    confirm_button.pressed.connect(_on_confirm_pressed)
    close_button.pressed.connect(_on_close_pressed)
    close_requested.connect(_on_close_pressed)

    server_detail_form.edited.connect(_on_form_edited)
    group_detail_form.edited.connect(_on_form_edited)
    tag_detail_form.edited.connect(_on_form_edited)
    tag_detail_form.browse_requested.connect(_on_tag_browse_requested)

    OpcUaManager.connection_failed.connect(_on_server_connection_failed)

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
    if server == null or group_id == "":
        return null
    for group: ReactiveOpcUaGroup in server.groups.value:
        if group.id.value == group_id:
            return group
    return null


func _get_tag(group: ReactiveOpcUaGroup, tag_id: String) -> ReactiveOpcUaTag:
    if group == null or tag_id == "":
        return null
    for tag: ReactiveOpcUaTag in group.tags.value:
        if tag.id.value == tag_id:
            return tag
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

func _on_current_project_changed(_origin: ReactiveVariant) -> void:
    _rebind_project_signal()

    _selection_type     = SelectionType.NONE
    _selected_server_id = ""
    _selected_group_id  = ""
    _selected_tag_id    = ""
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
    tag_detail_form.visible    = (type == SelectionType.TAG)

    add_group_button.disabled  = (not _has_project()) or (_selected_server_id == "")
    add_tag_button.disabled    = (not _has_project()) or (_selected_group_id == "")
    remove_button.disabled     = (type == SelectionType.NONE)

    match type:
        SelectionType.NONE:
            remove_button.text = "Remove"
        SelectionType.SERVER:
            remove_button.text = "Remove Server"
        SelectionType.GROUP:
            remove_button.text = "Remove Group"
        SelectionType.TAG:
            remove_button.text = "Remove Tag"

    var server_selected: bool = (type == SelectionType.SERVER)
    test_button.visible       = server_selected
    browse_button.visible     = server_selected
    status_button.visible     = server_selected

    confirm_button.disabled = not (_picker_active and type == SelectionType.TAG)

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


func _load_tag_form(server_id: String, group_id: String, tag_id: String) -> void:
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    var group: ReactiveOpcUaGroup = _get_group(cfg, group_id) if cfg else null
    var tag: ReactiveOpcUaTag = _get_tag(group, tag_id) if group else null
    if tag == null:
        return

    _form_dirty = false
    tag_detail_form.load_config(tag)
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
        SelectionType.TAG:
            _commit_tag_form()

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


func _commit_tag_form() -> void:
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var group: ReactiveOpcUaGroup = _get_group(cfg, _selected_group_id) if cfg else null
    var tag: ReactiveOpcUaTag = _get_tag(group, _selected_tag_id) if group else null
    if tag == null:
        return

    tag_detail_form.commit_to(tag)

# ── Tree selection handlers ───────────────────────────────────────────────────

func _on_server_selected(server_id: String) -> void:
    _commit_form()
    _selection_type     = SelectionType.SERVER
    _selected_server_id = server_id
    _selected_group_id  = ""
    _selected_tag_id    = ""
    _load_server_form(server_id)
    _set_panel(SelectionType.SERVER)


func _on_group_selected(server_id: String, group_id: String) -> void:
    _commit_form()
    _selection_type     = SelectionType.GROUP
    _selected_server_id = server_id
    _selected_group_id  = group_id
    _selected_tag_id    = ""
    _load_group_form(server_id, group_id)
    _set_panel(SelectionType.GROUP)


func _on_tag_selected(server_id: String, group_id: String, tag_id: String) -> void:
    _commit_form()
    _selection_type     = SelectionType.TAG
    _selected_server_id = server_id
    _selected_group_id  = group_id
    _selected_tag_id    = tag_id
    _load_tag_form(server_id, group_id, tag_id)
    _set_panel(SelectionType.TAG)


func _on_selection_cleared() -> void:
    _commit_form()
    _selection_type     = SelectionType.NONE
    _selected_server_id = ""
    _selected_group_id  = ""
    _selected_tag_id    = ""
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


func _on_add_tag_pressed() -> void:
    if not _has_project() or _selected_server_id == "" or _selected_group_id == "":
        return

    _commit_form()

    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var group: ReactiveOpcUaGroup = _get_group(cfg, _selected_group_id) if cfg else null
    if group == null:
        return

    var id: String = "tag_%d" % Time.get_ticks_msec()
    var tag: ReactiveOpcUaTag = ReactiveOpcUaTag.new({}, group, id)
    tag.id.value           = id
    tag.node_id.value      = ""
    tag.display_name.value = "New Tag"

    group.tags.append(tag)

    server_tree.set_servers(_servers())
    server_tree.select_tag(_selected_server_id, _selected_group_id, tag.id.value)


func _on_remove_pressed() -> void:
    if not _has_project():
        return

    _commit_form()

    match _selection_type:
        SelectionType.SERVER:
            OpcUaManager.remove_server(_selected_server_id)
            _remove_server(_selected_server_id)
            _selected_server_id = ""
            _selected_group_id  = ""
            _selected_tag_id    = ""
            _selection_type     = SelectionType.NONE

        SelectionType.GROUP:
            var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
            if cfg:
                cfg.remove_group(_selected_group_id)
            _selected_group_id = ""
            _selected_tag_id   = ""
            _selection_type    = SelectionType.SERVER

        SelectionType.TAG:
            var cfg2: ReactiveOpcUaServer = _get_server(_selected_server_id)
            var group: ReactiveOpcUaGroup = _get_group(cfg2, _selected_group_id) if cfg2 else null
            if group:
                group.remove_tag(_selected_tag_id)
            _selected_tag_id = ""
            _selection_type  = SelectionType.GROUP

    server_tree.set_servers(_servers())

    match _selection_type:
        SelectionType.SERVER:
            server_tree.select_server(_selected_server_id)
        SelectionType.GROUP:
            server_tree.select_group(_selected_server_id, _selected_group_id)
        _:
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
    if cfg.username.value.is_empty():
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

    # Footer "Browse" is view-only — no callback needed on pick.
    _open_browser_for_server(_selected_server_id)

func _on_status_pressed() -> void:
    if _selected_server_id == "":
        return

    _commit_form()

    var status_dialog: OpcUaStatusDialog = get_node("/root/Main/Dialogs/OpcUaStatusDialog")

    status_dialog.focus_server(_selected_server_id)
    status_dialog.show()

func _on_confirm_pressed() -> void:
    _commit_form()

    if _picker_active and _selection_type == SelectionType.TAG:
        var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
        var group: ReactiveOpcUaGroup = _get_group(cfg, _selected_group_id) if cfg else null
        var tag: ReactiveOpcUaTag = _get_tag(group, _selected_tag_id) if group else null

        if tag != null:
            var result: OpcUaTagBinding = OpcUaTagBinding.new(
                _selected_server_id,
                _selected_group_id,
                OpcUaNodeId.parse(tag.node_id.value) if tag.node_id.value != "" else null
            )
            var callback: Callable = _picker_callback

            _end_picker_session()
            hide()

            if callback.is_valid():
                callback.call(result)
            return

    _end_picker_session()
    hide()


func _on_close_pressed() -> void:
    _commit_form()
    _end_picker_session()
    hide()


func _end_picker_session() -> void:
    _picker_active         = false
    _picker_callback        = Callable()
    confirm_button.visible  = false

# ── Tag node picking (Browse) ─────────────────────────────────────────────────

func _on_tag_browse_requested() -> void:
    if _selected_server_id == "" or _selected_group_id == "" or _selected_tag_id == "":
        return

    _open_browser_for_server(_selected_server_id, func(node_id: OpcUaNodeId) -> void:
        tag_detail_form.apply_picked_node_id(node_id)
    )

# ── Shared browse helper ──────────────────────────────────────────────────────

func _open_browser_for_server(server_id: String, on_picked: Callable = Callable()) -> void:
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    if cfg == null:
        return

    var browse_nodes: BrowseNodes = get_node("/root/Main/Dialogs/BrowseNodes")
    browse_nodes.browse(cfg, on_picked)

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


# =============================================================================
# Public API
# =============================================================================

## Opens the dialog for project config/node selection.
##
## If on_selected is valid, the confirm button is shown and, once the
## user confirms, on_selected is called once with the chosen OpcUaNodeId
## (connected CONNECT_ONE_SHOT). If enable_selection is false, this behaves
## as a read-only browse/test session — no confirm button, no callback.
func browse(on_selected: Callable = Callable()) -> void:
    _picker_active   = on_selected.is_valid()
    _picker_callback = on_selected

    confirm_button.visible = _picker_active
    confirm_button.text    = "Select Tag" if _picker_active else "Confirm"
    confirm_button.disabled = not (_picker_active and _selection_type == SelectionType.TAG)

    popup_centered(Vector2i(900, 600))
