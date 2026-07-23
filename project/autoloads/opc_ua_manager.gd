# autoloads/opc_ua_manager.gd
## Autoload singleton. Derives its set of live OpcUaServerConnection instances
## purely from AppState.current_project.value.servers. UI code never calls
## add_server()/remove_server() directly — it only mutates project data;
## this manager reconciles automatically whenever:
##   1. AppState.current_project itself changes (a new project is loaded), or
##   2. the current project's `servers` array layout changes (add/remove/reorder).
extends Node

signal connected(server_id: String)
signal connection_lost(server_id: String)
signal connection_failed(server_id: String)
signal data_changed(server_id: String, node_id: String, value: Variant)

var _connections: Dictionary = {}   # server_id (String) -> OpcUaServerConnection

# Tracks the actual ReactiveProject we're currently bound to, so we can
# unbind cleanly (and avoid dangling references) when the project changes.
var _bound_project: ReactiveProject = null
var _servers_changed_callable: Callable = Callable()


func _ready() -> void:
    AppState.current_project.changed.connect(_on_current_project_changed)
    _bind_project()
    _reconcile()


func _on_current_project_changed() -> void:
    _bind_project()
    _reconcile()


# ── Binding ────────────────────────────────────────────────────────────────

## Rebinds to the current project's `servers` array, so that any change to
## the server layout (add/remove/reorder) triggers reconciliation, even
## though AppState.current_project.value itself did not change. Explicitly
## unbinds from the previously bound project first to avoid dangling
## references or duplicate listeners.
func _bind_project() -> void:
    if _bound_project != null and _servers_changed_callable.is_valid():
        _bound_project.servers.reactive_changed.disconnect(_servers_changed_callable)

    _bound_project = null
    _servers_changed_callable = Callable()

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    _servers_changed_callable = func(_origin: ReactiveArray) -> void:
        _reconcile()

    project.servers.connect_self_changed(_servers_changed_callable)
    _bound_project = project


# ── Reconciliation ──────────────────────────────────────────────────────────

func _reconcile() -> void:
    var project: ReactiveProject = _bound_project

    if project == null:
        _teardown_all()
        return

    var configured_ids: Dictionary = {}

    for cfg: ReactiveOpcUaServer in project.servers.values():
        var server_id: String = cfg.id.value
        configured_ids[server_id] = true

        if _connections.has(server_id):
            var connection: OpcUaServerConnection = _connections[server_id]
            connection.apply_config(cfg)
        else:
            _spawn_connection(cfg)

    # Remove connections whose server no longer exists in the project.
    for server_id: String in _connections.keys().duplicate():
        if not configured_ids.has(server_id):
            _teardown_connection(server_id)


func _spawn_connection(cfg: ReactiveOpcUaServer) -> void:
    var server_id: String = cfg.id.value
    var connection: OpcUaServerConnection = OpcUaServerConnection.new(cfg.id.value)
    add_child(connection)

    connection.connected.connect(func() -> void: connected.emit(server_id))
    connection.connection_lost.connect(func() -> void: connection_lost.emit(server_id))
    connection.connection_failed.connect(func() -> void: connection_failed.emit(server_id))
    connection.data_changed.connect(
        func(node_id: String, value: Variant) -> void:
            data_changed.emit(server_id, node_id, value)
    )

    _connections[server_id] = connection
    connection.apply_config(cfg)


func _teardown_connection(server_id: String) -> void:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    if connection != null:
        connection.teardown()
    _connections.erase(server_id)


func _teardown_all() -> void:
    for server_id: String in _connections.keys().duplicate():
        _teardown_connection(server_id)


# ── Public read-only API (used by UI) ───────────────────────────────────────

func is_server_connected(server_id: String) -> bool:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    return connection != null and connection.is_connected_to_server()


func get_connection(server_id: String) -> OpcUaServerConnection:
    return _connections.get(server_id)


## Borrows the live managed client for ad-hoc operations (e.g. browsing).
## Returns null if the server is not currently connected.
func get_client(server_id: String) -> GodotOpcUa:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    if connection != null and connection.is_connected_to_server():
        return connection.client
    return null
