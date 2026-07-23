# opcua/opc_ua_server_connection.gd
class_name OpcUaServerConnection
extends Node

signal connected(server_id: String)
signal connection_lost(server_id: String)
signal connection_failed(server_id: String)
signal tag_value_changed(server_id: String, node_id: OpcUaNodeId, value: Variant)

var server_id: String
var config: ReactiveOpcUaServer

var _client: GodotOpcUa
var _connected: bool = false
var _last_tick_ms: int = 0
var _poll_accum_sec: float = 0.0

## group_id (String) -> OpcUaGroup
var _groups: Dictionary = {}

var _bound_groups: ReactiveArray = null
var _groups_changed_callable: Callable = Callable()

var client: GodotOpcUa:
    get:
        return _client

# ── Init ──────────────────────────────────────────────────────────────────

func _init(p_server_id: String) -> void:
    server_id = p_server_id
    name = "OpcUaServerConnection_%s" % p_server_id
    _client = GodotOpcUa.new()

# ── Per-frame polling ───────────────────────────────────────────────────────

func _process(delta: float) -> void:
    if config == null:
        return

    _poll_accum_sec += delta
    var interval: float = maxf(config.poll_interval_sec.value, 0.001)
    if _poll_accum_sec < interval:
        return

    _poll_accum_sec = 0.0
    poll()


func _exit_tree() -> void:
    if _connected:
        disconnect_from_server()

# ── Config application ──────────────────────────────────────────────────────

func apply_config(cfg: ReactiveOpcUaServer) -> void:
    var is_initial: bool = config == null

    var connection_params_changed: bool = is_initial \
        or config.endpoint_url.value != cfg.endpoint_url.value \
        or config.security_policy.value != cfg.security_policy.value \
        or config.message_mode.value != cfg.message_mode.value \
        or config.username.value != cfg.username.value \
        or config.password.value != cfg.password.value

    config = cfg
    server_id = cfg.id.value

    _client.set_reconnect_interval(cfg.reconnect_interval_sec.value)
    _client.set_max_reconnect_attempts(cfg.max_reconnect_attempts.value)

    _bind_groups(cfg.groups)
    _reconcile_groups()

    if connection_params_changed:
        if _connected:
            disconnect_from_server()
        connect_to_server()
    elif not _connected:
        connect_to_server()

# ── Binding ─────────────────────────────────────────────────────────────────

func _bind_groups(groups: ReactiveArray) -> void:
    if _bound_groups != null and _groups_changed_callable.is_valid():
        _bound_groups.disconnect_self_changed(_groups_changed_callable)

    _bound_groups = null
    _groups_changed_callable = Callable()

    if groups == null:
        return

    _groups_changed_callable = func(_origin: Reactive) -> void:
        _reconcile_groups()

    groups.connect_self_changed(_groups_changed_callable)
    _bound_groups = groups

# ── Reconciliation ──────────────────────────────────────────────────────────

func _reconcile_groups() -> void:
    if config == null:
        return

    var configured_ids: Dictionary = {}

    for group_cfg: ReactiveOpcUaGroup in config.groups.values():
        var group_id: String = group_cfg.id.value
        configured_ids[group_id] = true

        if _groups.has(group_id):
            var group: OpcUaGroup = _groups[group_id]
            group.apply_config(group_cfg)
        else:
            _spawn_group(group_cfg)

    for group_id: String in _groups.keys().duplicate():
        if not configured_ids.has(group_id):
            _teardown_group(group_id)


func _spawn_group(group_cfg: ReactiveOpcUaGroup) -> void:
    var group_id: String = group_cfg.id.value
    var group: OpcUaGroup = OpcUaGroup.new(group_id)

    group.tag_value_changed.connect(
        func(node_id: OpcUaNodeId, value: Variant) -> void:
            tag_value_changed.emit(server_id, node_id, value)
    )

    _groups[group_id] = group
    group.apply_config(group_cfg)


func _teardown_group(group_id: String) -> void:
    var group: OpcUaGroup = _groups.get(group_id)
    if group != null:
        group.teardown(_client)
    _groups.erase(group_id)

# ── Connection ────────────────────────────────────────────────────────────

func connect_to_server() -> bool:
    if config == null:
        push_warning("OpcUaServerConnection [%s]: connect attempted before apply_config()." % server_id)
        return false

    var ok: bool
    if config.username.value.is_empty():
        ok = _client.connect_to_server(config.endpoint_url.value)
    else:
        ok = _client.connect_with_credentials(
            config.endpoint_url.value, config.username.value, config.password.value
        )

    if not ok:
        push_warning("OpcUaServerConnection [%s]: connection failed." % server_id)
        return false

    _rebuild_all_groups()
    _last_tick_ms = Time.get_ticks_msec()
    return true


func disconnect_from_server() -> void:
    for group: OpcUaGroup in _groups.values():
        group.delete(_client)
    _client.disconnect_server()
    _connected = false


func teardown() -> void:
    disconnect_from_server()

    for group_id: String in _groups.keys().duplicate():
        _teardown_group(group_id)

    if _bound_groups != null and _groups_changed_callable.is_valid():
        _bound_groups.disconnect_self_changed(_groups_changed_callable)

    _bound_groups = null
    _groups_changed_callable = Callable()

    queue_free()

# ── Poll ─────────────────────────────────────────────────────────────────────

func poll() -> void:
    if _client.has_connection_failed():
        push_warning("OpcUaServerConnection [%s]: reconnection exhausted." % server_id)
        _connected = false
        connection_failed.emit(server_id)
        return

    var now_connected: bool = _client.is_server_connected()
    if now_connected != _connected:
        _connected = now_connected
        if _connected:
            _rebuild_all_groups()
            _last_tick_ms = Time.get_ticks_msec()
            connected.emit(server_id)
        else:
            connection_lost.emit(server_id)

    if not _connected:
        return

    for group: OpcUaGroup in _groups.values():
        if group.is_dirty():
            group.rebuild(_client)

    ## Assumes GodotOpcUa now returns changed tags keyed by OpcUaNodeId.
    ## If it still returns String keys, change this loop to parse each key
    ## via OpcUaNodeId.parse(key) before calling apply_update().
    var changed: Dictionary = _client.get_changed_tags_since(_last_tick_ms)
    _last_tick_ms = Time.get_ticks_msec()

    for node_id: OpcUaNodeId in changed:
        var group: OpcUaGroup = _find_group_for_tag(node_id)
        if group != null:
            group.apply_update(node_id, changed[node_id])

# ── Write ─────────────────────────────────────────────────────────────────

func write_tag(node_id: OpcUaNodeId, value: Variant) -> bool:
    var group: OpcUaGroup = _find_group_for_tag(node_id)
    if group == null:
        push_warning("OpcUaServerConnection [%s]: write on unregistered tag '%s'." % [server_id, node_id.to_string()])
        return false
    return group.write_tag(node_id, value, _client)


func _find_group_for_tag(node_id: OpcUaNodeId) -> OpcUaGroup:
    for group: OpcUaGroup in _groups.values():
        if group.has_tag(node_id):
            return group
    return null

# ── Accessors ─────────────────────────────────────────────────────────────

func is_server_connected() -> bool:
    return _connected


func get_active_group_count() -> int:
    return _groups.size()


func _rebuild_all_groups() -> void:
    for group: OpcUaGroup in _groups.values():
        group.rebuild(_client)
