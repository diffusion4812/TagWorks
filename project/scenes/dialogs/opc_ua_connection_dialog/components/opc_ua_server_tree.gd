# ui/components/opc_ua_server_tree.gd
class_name OpcUaServerTree
extends Tree

## Emitted when a server row is selected (by user click or programmatically
## via select_server()).
signal server_selected(server_id: String)

## Emitted when a subscription-group row is selected (by user click or
## programmatically via select_group()).
signal group_selected(server_id: String, group_id: String)

## Emitted when the selection becomes invalid or is explicitly cleared.
signal selection_cleared

@onready var _status_refresh_timer: Timer = $StatusRefreshTimer

const STATUS_CONNECTED    :String = "● "
const STATUS_DISCONNECTED :String = "○ "

var _servers:            Array[ReactiveOpcUaServer] = []
var _selected_server_id: String = ""
var _selected_group_id:  String = ""
var _has_group_selected:  bool   = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    columns                    = 2
    column_titles_visible      = true
    hide_root                  = true
    set_column_title(0, "Name")
    set_column_title(1, "Interval")
    set_column_expand(1, false)
    set_column_custom_minimum_width(1, 90)

    item_selected.connect(_on_item_selected)

    _status_refresh_timer.timeout.connect(_on_status_refresh_timeout)

    OpcUaManager.connected.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_lost.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_failed.connect(_on_connection_state_changed.unbind(1))

# ── Public API ─────────────────────────────────────────────────────────────

## Rebuilds the tree from the given server list, preserving the current
## selection if it still exists.
func set_servers(servers: Array[ReactiveOpcUaServer]) -> void:
    _servers = servers
    _rebuild()


## Refreshes only the connection-status prefixes, without rebuilding the
## tree structure. Cheaper than set_servers() when only status may have
## changed.
func refresh_status_icons() -> void:
    var root: TreeItem = get_root()
    if root == null:
        return

    var server_item: TreeItem = root.get_first_child()
    while server_item != null:
        var meta: Dictionary = server_item.get_metadata(0)
        if meta.get("type") == "server":
            var server_id: String = meta.get("server_id", "")
            var cfg: ReactiveOpcUaServer = _find_server(server_id)
            if cfg != null:
                server_item.set_text(0, _status_prefix(server_id) + cfg.display_name.value)
        server_item = server_item.get_next()


## Selects a server row programmatically and emits server_selected.
func select_server(server_id: String) -> void:
    var item: TreeItem = _find_server_item(server_id)
    if item == null:
        return
    item.select(0)
    _selected_server_id  = server_id
    _selected_group_id   = ""
    _has_group_selected  = false
    server_selected.emit(server_id)


## Selects a group row programmatically and emits group_selected.
func select_group(server_id: String, group_id: String) -> void:
    var item: TreeItem = _find_group_item(server_id, group_id)
    if item == null:
        return
    item.select(0)
    _selected_server_id  = server_id
    _selected_group_id   = group_id
    _has_group_selected  = true
    group_selected.emit(server_id, group_id)


## Clears the current selection without emitting server_selected /
## group_selected. Emits selection_cleared.
func clear_selection() -> void:
    deselect_all()
    _selected_server_id = ""
    _selected_group_id  = ""
    _has_group_selected = false
    selection_cleared.emit()


func get_selected_server_id() -> String:
    return _selected_server_id


func get_selected_group_id() -> String:
    return _selected_group_id


func has_group_selected() -> bool:
    return _has_group_selected

# ── Internal build ────────────────────────────────────────────────────────

func _rebuild() -> void:
    clear()
    var root: TreeItem = create_item()
    if root == null:
        return

    for cfg: ReactiveOpcUaServer in _servers:
        var server_item: TreeItem = create_item(root)
        server_item.set_text(0, _status_prefix(cfg.id.value) + cfg.display_name.value)
        server_item.set_text(1, "")
        server_item.set_metadata(0, { "type": "server", "server_id": cfg.id.value })

        for group: ReactiveOpcUaGroup in cfg.groups.value:
            var group_item: TreeItem = create_item(server_item)
            group_item.set_text(0, "  " + group.display_name.value)
            group_item.set_text(1, "%d ms" % group.pub_interval_ms.value)
            group_item.set_metadata(0, {
                "type":      "group",
                "server_id": cfg.id.value,
                "group_id":  group.id.value
            })

    _restore_selection()


func _restore_selection() -> void:
    if _selected_server_id == "":
        return

    if _has_group_selected:
        var group_item: TreeItem = _find_group_item(_selected_server_id, _selected_group_id)
        if group_item != null:
            group_item.select(0)
            return
    else:
        var server_item: TreeItem = _find_server_item(_selected_server_id)
        if server_item != null:
            server_item.select(0)
            return

    # Previously selected item no longer exists.
    _selected_server_id = ""
    _selected_group_id  = ""
    _has_group_selected = false
    selection_cleared.emit()

# ── Lookup helpers ────────────────────────────────────────────────────────

func _find_server(server_id: String) -> ReactiveOpcUaServer:
    for cfg: ReactiveOpcUaServer in _servers:
        if cfg.id.value == server_id:
            return cfg
    return null


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


func _find_group_item(server_id: String, group_id: String) -> TreeItem:
    var server_item: TreeItem = _find_server_item(server_id)
    if server_item == null:
        return null
    var group_item: TreeItem = server_item.get_first_child()
    while group_item != null:
        var meta: Dictionary = group_item.get_metadata(0)
        if meta.get("group_id") == group_id:
            return group_item
        group_item = group_item.get_next()
    return null


func _status_prefix(server_id: String) -> String:
    return STATUS_CONNECTED if OpcUaManager.is_server_connected(server_id) \
                            else STATUS_DISCONNECTED

# ── Signal handlers ───────────────────────────────────────────────────────

func _on_item_selected() -> void:
    var item: TreeItem = get_selected()
    if item == null:
        return

    var meta: Dictionary = item.get_metadata(0)
    var type: String     = meta.get("type", "")

    if type == "server":
        _selected_server_id = meta.get("server_id", "")
        _selected_group_id  = ""
        _has_group_selected = false
        server_selected.emit(_selected_server_id)

    elif type == "group":
        _selected_server_id = meta.get("server_id", "")
        _selected_group_id  = meta.get("group_id",  "")
        _has_group_selected = true
        group_selected.emit(_selected_server_id, _selected_group_id)


func _on_connection_state_changed() -> void:
    refresh_status_icons()


func _on_status_refresh_timeout() -> void:
    refresh_status_icons()
