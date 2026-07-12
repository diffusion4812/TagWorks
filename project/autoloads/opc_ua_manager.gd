# autoloads/opc_ua_manager.gd
extends Node

signal connected(server_id: String)
signal connection_lost(server_id: String)
signal connection_failed(server_id: String)
signal tag_value_changed(server_id: String, node_id: OpcUaNodeId, value: Variant)

## { server_id: String -> OpcUaServerConnection }
var _connections: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    ProjectManager.opc_ua_registry.configs_changed.connect(_on_configs_changed)

func _process(_delta: float) -> void:
    for conn: OpcUaServerConnection in _connections.values():
        conn.poll()

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        disconnect_all()

# ── Server management ─────────────────────────────────────────────────────────

func add_server(config: OpcUaServerConfig) -> void:
    if _connections.has(config.id):
        push_warning("OpcUaManager: server '%s' already added." % config.id)
        return

    var conn := OpcUaServerConnection.new(config)
    conn.connected.connect(func(id): connected.emit(id))
    conn.connection_lost.connect(func(id): connection_lost.emit(id))
    conn.connection_failed.connect(func(id): connection_failed.emit(id))
    conn.tag_value_changed.connect(
        func(id, node_id, value): tag_value_changed.emit(id, node_id, value)
    )
    _connections[config.id] = conn

    # Seed any groups already present on the config at add time
    # This handles the case where a project is loaded with pre-configured groups
    for group: OpcUaSubscriptionGroupConfig in config.subscription_groups:
        conn.add_group(group)


func remove_server(server_id: String) -> void:
    var conn: OpcUaServerConnection = _connections.get(server_id, null)
    if conn == null:
        return
    conn.disconnect_from_server()
    _connections.erase(server_id)


func connect_server(server_id: String) -> bool:
    var conn := _get_connection(server_id)
    return conn.connect_to_server() if conn else false


func disconnect_server(server_id: String) -> void:
    var conn := _get_connection(server_id)
    if conn:
        conn.disconnect_from_server()


func disconnect_all() -> void:
    for conn: OpcUaServerConnection in _connections.values():
        conn.disconnect_from_server()
    _connections.clear()

# ── Group management ──────────────────────────────────────────────────────────

## Adds a subscription group to an existing server connection.
## Safe to call at any time — if the server is already connected the
## new group subscription is created immediately, otherwise it will be
## created the next time the server connects.
func add_group(server_id: String, group: OpcUaSubscriptionGroupConfig) -> void:
    var conn := _get_connection(server_id)
    if conn == null:
        return

    # Guard against duplicate groups
    if conn.has_group(group.id):
        push_warning(
            "OpcUaManager: group '%s' already exists on server '%s'." \
            % [group.id, server_id]
        )
        return

    conn.add_group(group)


## Removes a subscription group and all tags assigned to it.
## Tags that were in this group are unregistered — widgets will stop updating
## until re-bound to a different group.
func remove_group(server_id: String, group_id: String) -> void:
    var conn := _get_connection(server_id)
    if conn:
        conn.remove_group(group_id)


## Updates an existing group's configuration (e.g. display name or interval).
## If the interval changes the group subscription is rebuilt automatically.
func update_group(server_id: String, group: OpcUaSubscriptionGroupConfig) -> void:
    var conn := _get_connection(server_id)
    if conn == null:
        return

    if not conn.has_group(group.id):
        push_warning(
            "OpcUaManager: cannot update unknown group '%s' on server '%s'." \
            % [group.id, server_id]
        )
        return

    conn.update_group(group)

# ── Tag API ───────────────────────────────────────────────────────────────────

func register_tag(
    server_id:       String,
    node_id:         OpcUaNodeId,
    pub_interval_ms: float                      = 500.0,
    sampling_ms:     float                      = -1.0,
    deadband:        float                      = 0.0,
    mode:            OpcUaSubscriptionMode.Mode = OpcUaSubscriptionMode.Mode.ALWAYS
) -> void:
    var conn := _get_connection(server_id)
    if conn == null:
        return

    var resolved_interval := _resolve_group_interval(server_id, pub_interval_ms)
    var resolved_sampling  := sampling_ms if sampling_ms > 0.0 else resolved_interval

    conn.registry.register(
        node_id,
        resolved_sampling,
        resolved_interval,
        deadband,
        mode
    )

    # Stamp the resolved group_id onto the entry so the status window
    # can associate tags with their owning group unambiguously
    var resolved_group_id := _resolve_group_id(server_id, resolved_interval)
    if resolved_group_id != "":
        var entry := conn.registry.get_entry(node_id)
        if entry != null:
            entry.group_id = resolved_group_id


func _resolve_group_interval(server_id: String, pub_interval_ms: float) -> float:
    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        return pub_interval_ms

    if cfg.subscription_groups.is_empty():
        push_warning(
            "OpcUaManager: server '%s' has no subscription groups configured. " \
            % server_id +
            "Tag will be registered at %.0fms as an ad-hoc group." % pub_interval_ms
        )
        return pub_interval_ms

    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        if is_equal_approx(group.pub_interval_ms, pub_interval_ms):
            return group.pub_interval_ms

    var nearest_interval := cfg.subscription_groups[0].pub_interval_ms
    var nearest_delta    := absf(nearest_interval - pub_interval_ms)

    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        var delta := absf(group.pub_interval_ms - pub_interval_ms)
        if delta < nearest_delta:
            nearest_delta    = delta
            nearest_interval = group.pub_interval_ms

    push_warning(
        "OpcUaManager: no subscription group at %.0fms on server '%s'. " \
        % [pub_interval_ms, server_id] +
        "Tag assigned to nearest group at %.0fms." % nearest_interval
    )
    return nearest_interval

func _resolve_group_id(server_id: String, pub_interval_ms: float) -> String:
    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        return ""

    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        if is_equal_approx(group.pub_interval_ms, pub_interval_ms):
            return group.id

    return ""

func unregister_tag(server_id: String, node_id: OpcUaNodeId) -> void:
    var conn := _get_connection(server_id)
    if conn:
        conn.registry.unregister(node_id)


func get_tag_value(server_id: String, node_id: OpcUaNodeId) -> Variant:
    var conn := _get_connection(server_id)
    return conn.registry.get_value(node_id) if conn else null


func is_tag_quality_good(server_id: String, node_id: OpcUaNodeId) -> bool:
    var conn := _get_connection(server_id)
    return conn.registry.is_quality_good(node_id) if conn else false


func write_tag(server_id: String, node_id: OpcUaNodeId, value: Variant) -> bool:
    var conn := _get_connection(server_id)
    return conn.write_tag(node_id, value) if conn else false


func set_tag_visible(server_id: String, node_id: OpcUaNodeId, visible: bool) -> void:
    var conn := _get_connection(server_id)
    if conn:
        conn.registry.set_tag_visible(node_id, visible)


func is_server_connected(server_id: String) -> bool:
    var conn := _get_connection(server_id)
    return conn.is_server_connected() if conn else false


func get_raw_client(server_id: String) -> GodotOpcUa:
    var conn := _get_connection(server_id)
    return conn._client if conn else null

# ── ProjectManager integration ────────────────────────────────────────────────

func _on_configs_changed() -> void:
    var registry: OpcUaConfigRegistry = ProjectManager.opc_ua_registry

    # Remove servers no longer in the config
    for server_id in _connections.keys():
        if registry.get_config(server_id) == null:
            remove_server(server_id)

    # Add new servers and sync their groups
    for cfg: OpcUaServerConfig in registry.get_all_configs():
        if not _connections.has(cfg.id):
            add_server(cfg)
        else:
            _sync_groups(cfg)


## Reconciles the groups on an existing connection against the current config.
## Adds groups that are in the config but not yet on the connection.
## Removes groups that have been deleted from the config.
## Updates groups whose interval or display name has changed.
func _sync_groups(cfg: OpcUaServerConfig) -> void:
    var conn := _get_connection(cfg.id)
    if conn == null:
        return

    # Build a set of config group ids for fast lookup
    var config_group_ids: Dictionary = {}
    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        config_group_ids[group.id] = true

    # Remove groups no longer in config
    for group_id in conn.get_group_ids():
        if not config_group_ids.has(group_id):
            conn.remove_group(group_id)

    # Add or update groups from config
    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        if conn.has_group(group.id):
            conn.update_group(group)
        else:
            conn.add_group(group)

# ── Private ───────────────────────────────────────────────────────────────────

func _get_connection(server_id: String) -> OpcUaServerConnection:
    var conn: OpcUaServerConnection = _connections.get(server_id, null)
    if conn == null:
        push_warning("OpcUaManager: unknown server id '%s'." % server_id)
    return conn
