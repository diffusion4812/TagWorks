# autoloads/opc_ua_manager.gd
## Autoload singleton. Derives its set of live OpcUaServer instances
## purely from AppState.current_project.opc_ua_servers.
##
## SIMPLE MODE: no per-server diffing/reconciliation. Any structural change
## to opc_ua_servers (add/remove/reorder) tears down ALL existing connections
## and rebuilds the full set from scratch. This is intentionally coarse for
## MVP simplicity — revisit with the diff-based reconciliation approach
## (match by server id, apply_config() on existing connections, only
## spawn/teardown what actually changed) once the basic flow is validated
## end-to-end.
extends Node

var _connections: Dictionary = {}   # server_id (String) -> OpcUaServer

func _ready() -> void:
    # AppState.current_project is a permanent instance — bind once, forever.
    # Structural changes to opc_ua_servers (add/remove/reorder) always
    # trigger a rebuild; no rebinding needed on project load/close, since
    # has_project toggling doesn't change instance identity either.
    AppState.current_project.opc_ua_servers.connect_self_changed(
        func(_origin: Reactive) -> void:
            _rebuild_all()
    )
    _rebuild_all()


# ── Rebuild (no reconciliation) ─────────────────────────────────────────────

## Tears down every existing connection and spawns fresh ones from the
## current project state. Called on initial load and on any subsequent
## structural change to opc_ua_servers.
func _rebuild_all() -> void:
    _teardown_all()

    if not AppState.has_project.value:
        return

    var seen_ids: Dictionary = {}
    for cfg: ReactiveOpcUaServer in AppState.current_project.opc_ua_servers.values():
        var server_id: String = cfg.id.value
        if seen_ids.has(server_id):
            push_warning("OpcUaManager: duplicate server id '%s' — skipping duplicate." % server_id)
            continue
        seen_ids[server_id] = true
        _spawn_connection(cfg)


func _spawn_connection(cfg: ReactiveOpcUaServer) -> void:
    var connection: OpcUaServer = OpcUaServer.new(cfg)
    add_child(connection)

    _connections[cfg.id.value] = connection


func _teardown_all() -> void:
    for connection: OpcUaServer in _connections.values():
        connection.disconnect_from_server()
        connection.teardown()
        connection.queue_free()
    _connections.clear()


# ── Routing API ──────────────────────────────────────────────────────────────

func get_connection(server_id: String) -> OpcUaServer:
    return _connections.get(server_id)


func get_client(server_id: String) -> GodotOpcUa:
    var connection: OpcUaServer = _connections.get(server_id)
    return connection.client if connection != null else null


func write_tag(server_id: String, node_id: OpcUaNodeId, value: Variant) -> bool:
    var connection: OpcUaServer = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: write_tag on unknown server '%s'." % server_id)
        return false
    return connection.write_tag(node_id, value)


func get_tag(server_id: String, node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
    var connection: OpcUaServer = _connections.get(server_id)
    return connection.get_tag(node_id) if connection != null else null


func connect_server(server_id: String) -> void:
    var connection: OpcUaServer = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: connect_server on unknown server '%s'." % server_id)
        return
    connection.connect_to_server()


func disconnect_server(server_id: String) -> void:
    var connection: OpcUaServer = _connections.get(server_id)
    if connection == null:
        push_warning("OpcUaManager: disconnect_server on unknown server '%s'." % server_id)
        return
    connection.disconnect_from_server()
