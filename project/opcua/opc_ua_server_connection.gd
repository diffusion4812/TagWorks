# opcua/opc_ua_server_connection.gd
class_name OpcUaServerConnection
extends RefCounted

signal connected(server_id: String)
signal connection_lost(server_id: String)
signal connection_failed(server_id: String)
signal tag_value_changed(server_id: String, node_id: OpcUaNodeId, value: Variant)

var server_id: String
var config:    OpcUaServerConfig
var registry:  OpcUaTagRegistry = OpcUaTagRegistry.new()

var _client:        GodotOpcUa
var _connected:     bool = false
var _last_tick_ms:  int  = 0

## { pub_interval_ms: float -> OpcUaSubscriptionGroup }
var _groups: Dictionary = {}
var _group_configs: Dictionary = {}

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(p_config: OpcUaServerConfig) -> void:
    config    = p_config
    server_id = p_config.id

    _client = GodotOpcUa.new()
    _client.set_reconnect_interval(p_config.reconnect_interval_sec)
    _client.set_max_reconnect_attempts(p_config.max_reconnect_attempts)

    registry.tag_registered.connect(_on_tag_registered)
    registry.tag_unregistered.connect(_on_tag_unregistered)
    registry.tag_activation_changed.connect(_on_tag_activation_changed)

# ── Connection ────────────────────────────────────────────────────────────────

func connect_to_server() -> bool:
    var ok: bool
    if config.username.is_empty():
        ok = _client.connect_to_server(config.endpoint_url)
    else:
        ok = _client.connect_with_credentials(
            config.endpoint_url, config.username, config.password
        )

    if not ok:
        push_warning("OpcUaServerConnection [%s]: connection failed." % server_id)
        return false

    _rebuild_all_groups()
    _client.start_polling(config.poll_interval_sec)
    _last_tick_ms = Time.get_ticks_msec()
    return true


func disconnect_from_server() -> void:
    for group: OpcUaSubscriptionGroup in _groups.values():
        group.delete(_client)
    _groups.clear()
    _client.disconnect_server()
    _connected = false

# ── Poll (called each frame by OpcUaManager) ──────────────────────────────────

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

    # Rebuild any groups marked dirty this frame
    for group: OpcUaSubscriptionGroup in _groups.values():
        if group.is_dirty():
            group.rebuild(_client)

    var changed: Dictionary = _client.get_changed_tags_since(_last_tick_ms)
    _last_tick_ms = Time.get_ticks_msec()

    for tag_name: String in changed:
        if registry.apply_update(tag_name, changed[tag_name]):
            var entry: OpcUaTagRegistry.TagEntry = registry.get_entry_by_name(tag_name)
            if entry:
                tag_value_changed.emit(server_id, entry.node_id, entry.value)

# ── Write ─────────────────────────────────────────────────────────────────────

func write_tag(node_id: OpcUaNodeId, value: Variant) -> bool:
    if not registry.has_tag(node_id):
        push_warning("OpcUaServerConnection [%s]: write on unregistered tag." % server_id)
        return false
    var ok: bool = _client.write_node(node_id, value)
    if ok:
        registry.mark_dirty(node_id)
    return ok

# ── Accessors ─────────────────────────────────────────────────────────────────

func is_server_connected() -> bool:
    return _connected


func get_active_group_count() -> int:
    return _groups.size()

# ── Group management (internal) ───────────────────────────────────────────────

func _get_or_create_group(interval_ms: float) -> OpcUaSubscriptionGroup:
    if not _groups.has(interval_ms):
        _groups[interval_ms] = OpcUaSubscriptionGroup.new(interval_ms)
    return _groups[interval_ms]


func _remove_entry_from_groups(tag_name: String) -> void:
    var to_delete: Array = []
    for interval_ms: float in _groups:
        var group: OpcUaSubscriptionGroup = _groups[interval_ms]
        group.remove_entry(tag_name)
        if group.is_empty():
            group.delete(_client)
            to_delete.append(interval_ms)
    for key: float in to_delete:
        _groups.erase(key)


## Full rebuild from registry state — used on reconnect.
func _rebuild_all_groups() -> void:
    for group: OpcUaSubscriptionGroup in _groups.values():
        group.delete(_client)
    _groups.clear()

    var by_interval: Dictionary = registry.get_active_entries_by_interval()
    for interval_ms: float in by_interval:
        var group: OpcUaSubscriptionGroup = _get_or_create_group(interval_ms)
        for entry: OpcUaTagRegistry.TagEntry in by_interval[interval_ms]:
            group.add_entry(entry)
        group.rebuild(_client)

# ── Registry signal handlers ──────────────────────────────────────────────────

func _on_tag_registered(tag_name: String) -> void:
    var entry: OpcUaTagRegistry.TagEntry = registry.get_entry_by_name(tag_name)
    if entry == null or not entry.is_active:
        return
    var group: OpcUaSubscriptionGroup = _get_or_create_group(entry.pub_interval_ms)
    group.add_entry(entry)


func _on_tag_unregistered(tag_name: String) -> void:
    _remove_entry_from_groups(tag_name)


func _on_tag_activation_changed(tag_name: String, active: bool) -> void:
    var entry: OpcUaTagRegistry.TagEntry = registry.get_entry_by_name(tag_name)
    if entry == null:
        return

    if active:
        var group: OpcUaSubscriptionGroup = _get_or_create_group(entry.pub_interval_ms)
        group.add_entry(entry)
    else:
        _remove_entry_from_groups(tag_name)
        
func has_group(group_id: String) -> bool:
    return _group_configs.has(group_id)


func get_group_ids() -> Array:
    return _group_configs.keys()


func add_group(group: OpcUaSubscriptionGroupConfig) -> void:
    _group_configs[group.id] = group
    # Create the runtime subscription group keyed by interval
    var sub_group: OpcUaSubscriptionGroup = _get_or_create_group(group.pub_interval_ms)
    if _connected:
        sub_group.rebuild(_client)


func remove_group(group_id: String) -> void:
    var cfg: OpcUaSubscriptionGroupConfig = _group_configs.get(group_id, null)
    if cfg == null:
        return
    _group_configs.erase(group_id)

    # Remove the runtime group if no other config shares its interval
    var interval_still_used: bool = false
    for remaining: OpcUaSubscriptionGroupConfig in _group_configs.values():
        if is_equal_approx(remaining.pub_interval_ms, cfg.pub_interval_ms):
            interval_still_used = true
            break

    if not interval_still_used:
        var sub_group: OpcUaSubscriptionGroup = _groups.get(cfg.pub_interval_ms, null)
        if sub_group != null:
            sub_group.delete(_client)
            _groups.erase(cfg.pub_interval_ms)


func update_group(group: OpcUaSubscriptionGroupConfig) -> void:
    var old_cfg: OpcUaSubscriptionGroupConfig = _group_configs.get(group.id, null)
    if old_cfg == null:
        return

    var interval_changed: bool = not is_equal_approx(
        old_cfg.pub_interval_ms, group.pub_interval_ms
    )
    _group_configs[group.id] = group

    if interval_changed:
        # Remove from old interval group and rebuild at new interval
        remove_group(old_cfg.id)
        add_group(group)
