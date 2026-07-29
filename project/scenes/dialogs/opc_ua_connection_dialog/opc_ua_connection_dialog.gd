class_name OpcUaConnectionDialog
extends Window

# ── Tree ──────────────────────────────────────────────────────────────────────
@onready var server_tree:              OpcUaServerTree              = %ServerTree
@onready var add_server_button:        Button                       = %AddServerButton
@onready var add_subscription_button:  Button                       = %AddSubscriptionButton
@onready var add_tag_button:           Button                       = %AddTagButton
@onready var remove_button:            Button                       = %RemoveButton

# ── Right panel ───────────────────────────────────────────────────────────────
@onready var no_selection_label:       Label                        = %NoSelectionLabel
@onready var server_detail_form:       OpcUaServerDetailForm        = %ServerDetailForm
@onready var subscription_detail_form: OpcUaSubscriptionDetailForm  = %SubscriptionDetailForm
@onready var tag_detail_form:          OpcUaTagDetailForm           = %TagDetailForm

# ── Footer ────────────────────────────────────────────────────────────────────
@onready var test_button:              Button        = %TestButton
@onready var browse_button:            Button        = %BrowseButton
@onready var status_button:            Button        = %StatusButton
@onready var confirm_button:           Button        = %ConfirmButton
@onready var close_button:             Button        = %CloseButton

# ── State ─────────────────────────────────────────────────────────────────────

enum SelectionType { NONE, SERVER, SUBSCRIPTION, TAG }

var _selection_type:          SelectionType   = SelectionType.NONE
var _selected_server_id:      String          = ""
var _selected_subscription_id: String         = ""
var _selected_tag_id:         String          = ""
var _form_dirty:              bool            = false
var _commit_pending:          bool            = false
var _picker_active:           bool            = false
var _picker_callback:         Callable        = Callable()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _connect_signals()
    _refresh_tree()
    _set_panel(SelectionType.NONE)


func _connect_signals() -> void:
    add_server_button.pressed.connect(_on_add_server_pressed)
    add_subscription_button.pressed.connect(_on_add_subscription_pressed)
    add_tag_button.pressed.connect(_on_add_tag_pressed)
    remove_button.pressed.connect(_on_remove_pressed)

    server_tree.server_selected.connect(_on_server_selected)
    server_tree.subscription_selected.connect(_on_subscription_selected)
    server_tree.tag_selected.connect(_on_tag_selected)
    server_tree.selection_cleared.connect(_on_selection_cleared)

    test_button.pressed.connect(_on_test_pressed)
    browse_button.pressed.connect(_on_browse_pressed)
    confirm_button.pressed.connect(_on_confirm_pressed)
    close_button.pressed.connect(_on_close_pressed)
    close_requested.connect(_on_close_pressed)

    server_detail_form.edited.connect(_on_form_edited)
    subscription_detail_form.edited.connect(_on_form_edited)
    tag_detail_form.edited.connect(_on_form_edited)
    tag_detail_form.browse_requested.connect(_on_tag_browse_requested)

    # AppState.current_project is a permanent instance — bind once, forever.
    # No rebinding needed on project load/close, since identity never changes.
    AppState.current_project.changed.connect(_refresh_tree, CONNECT_DEFERRED)

    # has_project toggles on load/new/close — this is what resets selection
    # state and switches the panel, not a project "pointer" change.
    AppState.has_project.connect_self_changed(_on_has_project_changed)

# ── Project access helpers ────────────────────────────────────────────────────

func _has_project() -> bool:
    return AppState.has_project.value


func _get_server(server_id: String) -> ReactiveOpcUaServer:
    if server_id == "" or not _has_project():
        return null
    return AppState.current_project.opc_ua_servers.value.get(server_id) as ReactiveOpcUaServer


func _get_subscription(server: ReactiveOpcUaServer, subscription_id: String) -> ReactiveOpcUaSubscription:
    if server == null or subscription_id == "":
        return null
    for subscription: ReactiveOpcUaSubscription in server.subscriptions.value:
        if subscription.id.value == subscription_id:
            return subscription
    return null


func _get_tag(subscription: ReactiveOpcUaSubscription, tag_id: String) -> ReactiveOpcUaTag:
    if subscription == null or tag_id == "":
        return null
    for tag: ReactiveOpcUaTag in subscription.tags.value:
        if tag.id.value == tag_id:
            return tag
    return null


func _remove_subscription(cfg: ReactiveOpcUaServer, subscription_id: String) -> void:
    if cfg == null:
        return
    for i: int in cfg.subscriptions.value.size():
        var subscription: ReactiveOpcUaSubscription = cfg.subscriptions.value[i]
        if subscription.id.value == subscription_id:
            cfg.subscriptions.remove_at(i)
            return
    push_warning("Delete: selected subscription '%s' not found on server '%s'." % [subscription_id, cfg.id.value])

# ── Project load / close handling ─────────────────────────────────────────────

## Fires when a project is loaded, created, or closed (has_project toggles).
## Note: this does NOT fire on ordinary edits to the current project's
## contents — those are covered by the permanent AppState.current_project.changed
## connection above, which simply calls _refresh_tree().
func _on_has_project_changed(_origin: ReactiveBool) -> void:
    _selection_type            = SelectionType.NONE
    _selected_server_id        = ""
    _selected_subscription_id  = ""
    _selected_tag_id           = ""
    server_tree.clear_selection()
    _set_panel(SelectionType.NONE)

    _refresh_tree()

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

# ── Panel switching ───────────────────────────────────────────────────────────

func _set_panel(type: SelectionType) -> void:
    no_selection_label.visible      = (type == SelectionType.NONE)
    server_detail_form.visible      = (type == SelectionType.SERVER)
    subscription_detail_form.visible = (type == SelectionType.SUBSCRIPTION)
    tag_detail_form.visible         = (type == SelectionType.TAG)

    add_subscription_button.disabled = (not _has_project()) or (_selected_server_id == "")
    add_tag_button.disabled          = (not _has_project()) or (_selected_subscription_id == "")
    remove_button.disabled           = (type == SelectionType.NONE)

    match type:
        SelectionType.NONE:
            remove_button.text = "Remove"
        SelectionType.SERVER:
            remove_button.text = "Remove Server"
        SelectionType.SUBSCRIPTION:
            remove_button.text = "Remove Subscription"
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


func _load_subscription_form(server_id: String, subscription_id: String) -> void:
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, subscription_id) if cfg else null
    if subscription == null:
        return

    _form_dirty = false
    subscription_detail_form.load_config(subscription)
    _form_dirty = false


func _load_tag_form(server_id: String, subscription_id: String, tag_id: String) -> void:
    var cfg: ReactiveOpcUaServer = _get_server(server_id)
    var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, subscription_id) if cfg else null
    var tag: ReactiveOpcUaTag = _get_tag(subscription, tag_id) if subscription else null
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
        SelectionType.SUBSCRIPTION:
            _commit_subscription_form()
        SelectionType.TAG:
            _commit_tag_form()

    _form_dirty = false


func _commit_server_form() -> void:
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    if cfg == null:
        return

    server_detail_form.commit_to(cfg)


func _commit_subscription_form() -> void:
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, _selected_subscription_id) if cfg else null
    if subscription == null:
        return

    subscription_detail_form.commit_to(subscription)


func _commit_tag_form() -> void:
    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, _selected_subscription_id) if cfg else null
    var tag: ReactiveOpcUaTag = _get_tag(subscription, _selected_tag_id) if subscription else null
    if tag == null:
        return

    tag_detail_form.commit_to(tag)

# ── Tree selection handlers ───────────────────────────────────────────────────

func _on_server_selected(server_id: String) -> void:
    _commit_form()
    _selection_type           = SelectionType.SERVER
    _selected_server_id       = server_id
    _selected_subscription_id = ""
    _selected_tag_id          = ""
    _load_server_form(server_id)
    _set_panel(SelectionType.SERVER)


func _on_subscription_selected(server_id: String, subscription_id: String) -> void:
    _commit_form()
    _selection_type           = SelectionType.SUBSCRIPTION
    _selected_server_id       = server_id
    _selected_subscription_id = subscription_id
    _selected_tag_id          = ""
    _load_subscription_form(server_id, subscription_id)
    _set_panel(SelectionType.SUBSCRIPTION)


func _on_tag_selected(server_id: String, subscription_id: String, tag_id: String) -> void:
    _commit_form()
    _selection_type           = SelectionType.TAG
    _selected_server_id       = server_id
    _selected_subscription_id = subscription_id
    _selected_tag_id          = tag_id
    _load_tag_form(server_id, subscription_id, tag_id)
    _set_panel(SelectionType.TAG)


func _on_selection_cleared() -> void:
    _commit_form()
    _selection_type           = SelectionType.NONE
    _selected_server_id       = ""
    _selected_subscription_id = ""
    _selected_tag_id          = ""
    _set_panel(SelectionType.NONE)

# ── Add / Remove ──────────────────────────────────────────────────────────────

func _on_add_server_pressed() -> void:
    if not _has_project():
        OS.alert("Please load or create a project before adding an OPC UA server.", "No Project Loaded")
        return

    _commit_form()

    var id: String = "server_%d" % Time.get_ticks_msec()
    var cfg: ReactiveOpcUaServer = ReactiveOpcUaServer.new({}, AppState.current_project.opc_ua_servers, id)
    cfg.id.value           = id
    cfg.display_name.value = "New Server"
    cfg.endpoint_url.value = "opc.tcp://127.0.0.1:4840"

    AppState.current_project.opc_ua_servers.set_entry(id, cfg)

    server_tree.select_server(cfg.id.value)


func _on_add_subscription_pressed() -> void:
    if not _has_project() or _selected_server_id == "":
        return

    _commit_form()

    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    if cfg == null:
        return

    var id: String = "subscription_%d" % Time.get_ticks_msec()
    var subscription: ReactiveOpcUaSubscription = ReactiveOpcUaSubscription.new({}, cfg, id)
    subscription.id.value              = id
    subscription.display_name.value    = "New Subscription"
    subscription.pub_interval_ms.value = 500.0
    cfg.subscriptions.append(subscription)

    server_tree.select_subscription(_selected_server_id, subscription.id.value)


func _on_add_tag_pressed() -> void:
    if not _has_project() or _selected_server_id == "" or _selected_subscription_id == "":
        return

    _commit_form()

    var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
    var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, _selected_subscription_id) if cfg else null
    if subscription == null:
        return

    var id: String = "tag_%d" % Time.get_ticks_msec()
    var tag: ReactiveOpcUaTag = ReactiveOpcUaTag.new({}, subscription, id)
    tag.id.value           = id
    tag.node_id.value      = ""
    tag.display_name.value = "New Tag"

    subscription.tags.append(tag)

    server_tree.refresh()
    server_tree.select_tag(_selected_server_id, _selected_subscription_id, tag.id.value)


func _on_remove_pressed() -> void:
    if not _has_project():
        return

    _commit_form()

    match _selection_type:
        SelectionType.SERVER:
            AppState.current_project.opc_ua_servers.erase(_selected_server_id)
            _selected_server_id       = ""
            _selected_subscription_id = ""
            _selected_tag_id          = ""
            _selection_type           = SelectionType.NONE

        SelectionType.SUBSCRIPTION:
            var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
            if cfg:
                _remove_subscription(cfg, _selected_subscription_id)
            _selected_subscription_id = ""
            _selected_tag_id          = ""
            _selection_type           = SelectionType.SERVER

        SelectionType.TAG:
            var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
            var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, _selected_subscription_id) if cfg else null
            if subscription:
                var tag_index: int = -1
                for i: int in subscription.tags.value.size():
                    var tag: ReactiveOpcUaTag = subscription.tags.value[i]
                    if tag.id.value == _selected_tag_id:
                        tag_index = i
                        break

                if tag_index != -1:
                    subscription.tags.remove_at(tag_index)
                else:
                    push_warning("Delete: selected tag '%s' not found in subscription '%s'." % [_selected_tag_id, _selected_subscription_id])

            _selected_tag_id = ""
            _selection_type  = SelectionType.SUBSCRIPTION

    server_tree.refresh()

    match _selection_type:
        SelectionType.SERVER:
            server_tree.select_server(_selected_server_id)
        SelectionType.SUBSCRIPTION:
            server_tree.select_subscription(_selected_server_id, _selected_subscription_id)
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
        "Test Connection — %s" % cfg.display_name.value
    )


func _on_browse_pressed() -> void:
    if _selected_server_id == "":
        return

    _commit_form()

    # Footer "Browse" is view-only — no callback needed on pick.
    _open_browser_for_server(_selected_server_id)

func _on_confirm_pressed() -> void:
    _commit_form()

    if _picker_active and _selection_type == SelectionType.TAG:
        var cfg: ReactiveOpcUaServer = _get_server(_selected_server_id)
        var subscription: ReactiveOpcUaSubscription = _get_subscription(cfg, _selected_subscription_id) if cfg else null
        var tag: ReactiveOpcUaTag = _get_tag(subscription, _selected_tag_id) if subscription else null

        if tag != null:
            var result: OpcUaTagBinding = OpcUaTagBinding.new(
                _selected_server_id,
                _selected_subscription_id,
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
    if _selected_server_id == "" or _selected_subscription_id == "" or _selected_tag_id == "":
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
