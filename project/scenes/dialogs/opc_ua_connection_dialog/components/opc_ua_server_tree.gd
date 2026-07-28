class_name OpcUaServerTree
extends Tree

## Emitted when a server row is selected (by user click or programmatically
## via select_server()).
signal server_selected(server_id: String)

## Emitted when a subscription row is selected (by user click or
## programmatically via select_subscription()).
signal subscription_selected(server_id: String, subscription_id: String)

## Emitted when a tag row is selected (by user click or programmatically
## via select_tag()).
signal tag_selected(server_id: String, subscription_id: String, tag_id: String)

## Emitted when the selection becomes invalid or is explicitly cleared.
signal selection_cleared

const STATUS_CONNECTED       :String = "● "
const STATUS_DISCONNECTED    :String = "○ "
const STATUS_CONNECTING      :String = "◐ "
const STATUS_CONNECTION_FAILED :String = "✕ "

const INACTIVE_TAG_COLOR: Color = Color(0.6, 0.6, 0.6)

enum _SelectionKind { NONE, SERVER, SUBSCRIPTION, TAG }

var _selected_server_id:      String = ""
var _selected_subscription_id: String = ""
var _selected_tag_id:         String = ""
var _selection_kind:          _SelectionKind = _SelectionKind.NONE

## server_id (String) -> Callable, so each server's connection_status
## binding can be cleanly disconnected when the tree is rebuilt or a
## server is removed.
var _status_bindings: Dictionary = {}

## Callable bound to AppState.current_project.opc_ua_servers so the tree
## rebuilds whenever a server is added/removed from the project.
var _servers_changed_callback: Callable = Callable()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    columns                    = 2
    column_titles_visible      = true
    hide_root                  = true
    set_column_title(0, "Name")
    set_column_title(1, "Info")
    set_column_expand(1, false)
    set_column_custom_minimum_width(1, 90)

    item_selected.connect(_on_item_selected)

    _bind_servers_dictionary()
    _rebuild()


func _exit_tree() -> void:
    _unbind_servers_dictionary()
    _unbind_all_status()

# ── Public API ─────────────────────────────────────────────────────────────

## Selects a server row programmatically and emits server_selected.
func select_server(server_id: String) -> void:
    var item: TreeItem = _find_server_item(server_id)
    if item == null:
        return
    item.select(0)
    _selected_server_id       = server_id
    _selected_subscription_id = ""
    _selected_tag_id          = ""
    _selection_kind           = _SelectionKind.SERVER
    server_selected.emit(server_id)


## Selects a subscription row programmatically and emits subscription_selected.
func select_subscription(server_id: String, subscription_id: String) -> void:
    var item: TreeItem = _find_subscription_item(server_id, subscription_id)
    if item == null:
        return
    item.select(0)
    _selected_server_id       = server_id
    _selected_subscription_id = subscription_id
    _selected_tag_id          = ""
    _selection_kind           = _SelectionKind.SUBSCRIPTION
    subscription_selected.emit(server_id, subscription_id)


## Selects a tag row programmatically and emits tag_selected.
func select_tag(server_id: String, subscription_id: String, tag_id: String) -> void:
    var item: TreeItem = _find_tag_item(server_id, subscription_id, tag_id)
    if item == null:
        return
    item.select(0)
    _selected_server_id       = server_id
    _selected_subscription_id = subscription_id
    _selected_tag_id          = tag_id
    _selection_kind           = _SelectionKind.TAG
    tag_selected.emit(server_id, subscription_id, tag_id)


## Clears the current selection without emitting server_selected /
## subscription_selected / tag_selected. Emits selection_cleared.
func clear_selection() -> void:
    deselect_all()
    _selected_server_id       = ""
    _selected_subscription_id = ""
    _selected_tag_id          = ""
    _selection_kind           = _SelectionKind.NONE
    selection_cleared.emit()


func get_selected_server_id() -> String:
    return _selected_server_id


func get_selected_subscription_id() -> String:
    return _selected_subscription_id


func get_selected_tag_id() -> String:
    return _selected_tag_id


func has_subscription_selected() -> bool:
    return _selection_kind == _SelectionKind.SUBSCRIPTION


func has_tag_selected() -> bool:
    return _selection_kind == _SelectionKind.TAG

# ── Servers dictionary binding ────────────────────────────────────────────

## Binds directly to AppState.current_project.opc_ua_servers so the tree
## rebuilds immediately whenever a server is added or removed from the
## project, without polling.
func _bind_servers_dictionary() -> void:
    if AppState.current_project == null:
        return
    _servers_changed_callback = func(_origin: Reactive) -> void:
        _rebuild()
    AppState.current_project.opc_ua_servers.connect_self_changed(_servers_changed_callback)


func _unbind_servers_dictionary() -> void:
    if AppState.current_project != null and _servers_changed_callback.is_valid():
        AppState.current_project.opc_ua_servers.reactive_changed.disconnect(_servers_changed_callback)
    _servers_changed_callback = Callable()


## Convenience accessor for the current project's server dictionary
## (server_id -> ReactiveOpcUaServer).
func _servers_dict() -> Dictionary:
    if AppState.current_project == null:
        return {}
    return AppState.current_project.opc_ua_servers.value

# ── Internal build ────────────────────────────────────────────────────────

func _rebuild() -> void:
    _unbind_all_status()
    clear()
    var root: TreeItem = create_item()
    if root == null:
        return

    for cfg: ReactiveOpcUaServer in _servers_dict().values():
        var server_item: TreeItem = create_item(root)
        server_item.set_text(0, _status_prefix(cfg) + cfg.display_name.value)
        server_item.set_text(1, "")
        server_item.set_metadata(0, { "type": "server", "server_id": cfg.id.value })

        _bind_status(cfg)

        for subscription: ReactiveOpcUaSubscription in cfg.subscriptions.value:
            var subscription_item: TreeItem = create_item(server_item)
            subscription_item.set_text(0, "  " + subscription.display_name.value)
            subscription_item.set_text(1, "%d ms" % subscription.pub_interval_ms.value)
            subscription_item.set_metadata(0, {
                "type":            "subscription",
                "server_id":       cfg.id.value,
                "subscription_id": subscription.id.value
            })

            for tag: ReactiveOpcUaTag in subscription.tags.value:
                var tag_item: TreeItem = create_item(subscription_item)
                tag_item.set_text(0, "    " + tag.display_name.value)
                tag_item.set_text(1, tag.node_id.value)
                tag_item.set_metadata(0, {
                    "type":            "tag",
                    "server_id":       cfg.id.value,
                    "subscription_id": subscription.id.value,
                    "tag_id":          tag.id.value
                })

                if not tag.is_active.value:
                    tag_item.set_custom_color(0, INACTIVE_TAG_COLOR)
                    tag_item.set_custom_color(1, INACTIVE_TAG_COLOR)

    _restore_selection()


func _restore_selection() -> void:
    if _selected_server_id == "":
        return

    match _selection_kind:
        _SelectionKind.TAG:
            var tag_item: TreeItem = _find_tag_item(
                _selected_server_id, _selected_subscription_id, _selected_tag_id
            )
            if tag_item != null:
                tag_item.select(0)
                return

        _SelectionKind.SUBSCRIPTION:
            var subscription_item: TreeItem = _find_subscription_item(_selected_server_id, _selected_subscription_id)
            if subscription_item != null:
                subscription_item.select(0)
                return

        _SelectionKind.SERVER:
            var server_item: TreeItem = _find_server_item(_selected_server_id)
            if server_item != null:
                server_item.select(0)
                return

    # Previously selected item no longer exists.
    _selected_server_id       = ""
    _selected_subscription_id = ""
    _selected_tag_id          = ""
    _selection_kind           = _SelectionKind.NONE
    selection_cleared.emit()

# ── Status binding ───────────────────────────────────────────────────────────

## Binds directly to this server's reactive connection_status field, so the
## row's status prefix updates immediately on any transition
## (disconnected/connecting/connected/failed) without polling.
func _bind_status(cfg: ReactiveOpcUaServer) -> void:
    var server_id: String = cfg.id.value
    var callback: Callable = func(_origin: Reactive) -> void:
        _refresh_status_row(server_id)

    cfg.connection_status.connect_self_changed(callback)
    _status_bindings[server_id] = { "cfg": cfg, "callable": callback }


func _unbind_all_status() -> void:
    for binding: Dictionary in _status_bindings.values():
        var cfg: ReactiveOpcUaServer = binding.get("cfg")
        var callback: Callable = binding.get("callable")
        if cfg != null and callback.is_valid():
            cfg.connection_status.reactive_changed.disconnect(callback)
    _status_bindings.clear()


## Updates a single server row's status prefix in place, without touching
## the rest of the tree structure.
func _refresh_status_row(server_id: String) -> void:
    var item: TreeItem = _find_server_item(server_id)
    if item == null:
        return
    var cfg: ReactiveOpcUaServer = _find_server(server_id)
    if cfg == null:
        return
    item.set_text(0, _status_prefix(cfg) + cfg.display_name.value)

# ── Lookup helpers ────────────────────────────────────────────────────────

func _find_server(server_id: String) -> ReactiveOpcUaServer:
    return _servers_dict().get(server_id) as ReactiveOpcUaServer


func _find_server_item(server_id: String) -> TreeItem:
    var root: TreeItem = get_root()
    if root == null:
        return null
    var item: TreeItem = root.get_first_child()
    while item != null:
        var meta: Dictionary = item.get_metadata(0)
        if meta.get("server_id") == server_id and meta.get("type") == "server":
            return item
        item = item.get_next()
    return null


func _find_subscription_item(server_id: String, subscription_id: String) -> TreeItem:
    var server_item: TreeItem = _find_server_item(server_id)
    if server_item == null:
        return null
    var subscription_item: TreeItem = server_item.get_first_child()
    while subscription_item != null:
        var meta: Dictionary = subscription_item.get_metadata(0)
        if meta.get("subscription_id") == subscription_id:
            return subscription_item
        subscription_item = subscription_item.get_next()
    return null


func _find_tag_item(server_id: String, subscription_id: String, tag_id: String) -> TreeItem:
    var subscription_item: TreeItem = _find_subscription_item(server_id, subscription_id)
    if subscription_item == null:
        return null
    var tag_item: TreeItem = subscription_item.get_first_child()
    while tag_item != null:
        var meta: Dictionary = tag_item.get_metadata(0)
        if meta.get("tag_id") == tag_id:
            return tag_item
        tag_item = tag_item.get_next()
    return null


func _status_prefix(cfg: ReactiveOpcUaServer) -> String:
    match cfg.connection_status.value:
        ReactiveOpcUaServer.ConnectionStatus.CONNECTED:
            return STATUS_CONNECTED
        ReactiveOpcUaServer.ConnectionStatus.CONNECTING:
            return STATUS_CONNECTING
        ReactiveOpcUaServer.ConnectionStatus.CONNECTION_FAILED:
            return STATUS_CONNECTION_FAILED
        _:
            return STATUS_DISCONNECTED

# ── Signal handlers ───────────────────────────────────────────────────────

func _on_item_selected() -> void:
    var item: TreeItem = get_selected()
    if item == null:
        return

    var meta: Dictionary = item.get_metadata(0)
    var type: String     = meta.get("type", "")

    match type:
        "server":
            _selected_server_id       = meta.get("server_id", "")
            _selected_subscription_id = ""
            _selected_tag_id          = ""
            _selection_kind           = _SelectionKind.SERVER
            server_selected.emit(_selected_server_id)

        "subscription":
            _selected_server_id       = meta.get("server_id", "")
            _selected_subscription_id = meta.get("subscription_id", "")
            _selected_tag_id          = ""
            _selection_kind           = _SelectionKind.SUBSCRIPTION
            subscription_selected.emit(_selected_server_id, _selected_subscription_id)

        "tag":
            _selected_server_id       = meta.get("server_id", "")
            _selected_subscription_id = meta.get("subscription_id", "")
            _selected_tag_id          = meta.get("tag_id", "")
            _selection_kind           = _SelectionKind.TAG
            tag_selected.emit(_selected_server_id, _selected_subscription_id, _selected_tag_id)
