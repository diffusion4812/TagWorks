# autoloads/opc_ua_manager.gd
## Autoload singleton. Derives its set of live OpcUaServerConnection instances
## purely from AppState.current_project.value.opc_ua_servers.
##
## SIMPLE MODE: no per-server diffing/reconciliation. Any change to the
## current project, or to its `opc_ua_servers` array, tears down ALL
## existing connections and rebuilds the full set from scratch. This is
## intentionally coarse for MVP simplicity — revisit with the diff-based
## reconciliation approach (match by server id, apply_config() on existing
## connections, only spawn/teardown what actually changed) once the basic
## flow is validated end-to-end.
extends Node

signal tag_value_changed(server_id: String, subscription_id: String, node_id: OpcUaNodeId, value: Variant)

var _connections: Dictionary = {}   # server_id (String) -> OpcUaServerConnection

var _bound_project: ReactiveProject = null
var _servers_changed_callable: Callable = Callable()


func _ready() -> void:
    AppState.current_project.connect_self_changed(_on_current_project_changed)
    _bind_project()
    _rebuild_all()


func _on_current_project_changed(_origin: ReactiveVariant) -> void:
    _bind_project()
    _rebuild_all()


# ── Binding ────────────────────────────────────────────────────────────────

func _bind_project() -> void:
    if _bound_project != null and _servers_changed_callable.is_valid():
        _bound_project.opc_ua_servers.reactive_changed.disconnect(_servers_changed_callable)

    _bound_project = null
    _servers_changed_callable = Callable()

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    _servers_changed_callable = func(_origin: Reactive) -> void:
        _rebuild_all()

    project.opc_ua_servers.connect_self_changed(_servers_changed_callable)
    _bound_project = project


# ── Rebuild (no reconciliation) ─────────────────────────────────────────────

## Tears down every existing connection and spawns fresh ones from the
## current project state. Called on initial load and on any subsequent
## change to the bound project's servers array.
func _rebuild_all() -> void:
    _teardown_all()

    if _bound_project == null:
        return

    var seen_ids: Dictionary = {}
    for cfg: ReactiveOpcUaServer in _bound_project.opc_ua_servers.value:
        var server_id: String = cfg.id.value
        if seen_ids.has(server_id):
            push_warning("OpcUaManager: duplicate server id '%s' — skipping duplicate." % server_id)
            continue
        seen_ids[server_id] = true
        _spawn_connection(cfg)


func _spawn_connection(cfg: ReactiveOpcUaServer) -> void:
    var server_id: String = cfg.id.value
    var connection: OpcUaServerConnection = OpcUaServerConnection.new()
    add_child(connection)

    connection.tag_value_changed.connect(
        func(subscription_id: String, node_id: OpcUaNodeId, value: Variant) -> void:
            tag_value_changed.emit(server_id, subscription_id, node_id, value)
    )

    _connections[server_id] = connection
    connection.apply_config(cfg)


func _teardown_all() -> void:
    for connection: OpcUaServerConnection in _connections.values():
        connection.disconnect_from_server()
        connection.teardown()
        connection.queue_free()
    _connections.clear()


# ── Routing API ──────────────────────────────────────────────────────────────

func get_connection(server_id: String) -> OpcUaServerConnection:
    return _connections.get(server_id)


func get_client(server_id: String) -> GodotOpcUa:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    return connection.client if connection != null else null


func write_tag(server_id: String, node_id: OpcUaNodeId, value: Variant) -> bool:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: write_tag on unknown server '%s'." % server_id)
        return false
    return connection.write_tag(node_id, value)


func get_tag(server_id: String, node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    return connection.get_tag(node_id) if connection != null else null


func connect_server(server_id: String) -> void:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: connect_server on unknown server '%s'." % server_id)
        return
    connection.connect_to_server()


func disconnect_server(server_id: String) -> void:
    var connection: OpcUaServerConnection = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: disconnect_server on unknown server '%s'." % server_id)
        return
    connection.disconnect_from_server()
