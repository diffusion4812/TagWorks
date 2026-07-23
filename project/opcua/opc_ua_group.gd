# opcua/opc_ua_group.gd
class_name OpcUaGroup
extends RefCounted

signal tag_value_changed(node_id: OpcUaNodeId, value: Variant)

class TagEntry:
    var node_id: OpcUaNodeId
    var display_name: String
    var is_active: bool
    var sampling_ms: float
    var deadband: float
    var value: Variant = null   # runtime-only — never persisted to the reactive layer

# ── Identity / config ──────────────────────────────────────────────────────

var group_id: String
var pub_interval_ms: float
var config: ReactiveOpcUaGroup

var _entries: Dictionary = {}   # node_id.to_string() (String) -> TagEntry
var _sub_handle: int = -1
var _dirty: bool = false

var _bound_tags: ReactiveArray = null
var _tags_changed_callable: Callable = Callable()

# ── Init ──────────────────────────────────────────────────────────────────

func _init(p_group_id: String) -> void:
    group_id = p_group_id

# ── Config application ──────────────────────────────────────────────────────

func apply_config(cfg: ReactiveOpcUaGroup) -> void:
    config = cfg
    group_id = cfg.id.value

    if not is_equal_approx(pub_interval_ms, cfg.pub_interval_ms.value):
        pub_interval_ms = cfg.pub_interval_ms.value
        _dirty = true

    _bind_tags(cfg.tags)
    _reconcile_tags()

# ── Binding ─────────────────────────────────────────────────────────────────

func _bind_tags(tags: ReactiveArray) -> void:
    if _bound_tags != null and _tags_changed_callable.is_valid():
        _bound_tags.disconnect_self_changed(_tags_changed_callable)

    _bound_tags = null
    _tags_changed_callable = Callable()

    if tags == null:
        return

    _tags_changed_callable = func(_origin: Reactive) -> void:
        _reconcile_tags()

    tags.connect_self_changed(_tags_changed_callable)
    _bound_tags = tags

# ── Reconciliation ──────────────────────────────────────────────────────────

func _reconcile_tags() -> void:
    if config == null:
        return

    var configured_keys: Dictionary = {}

    for tag_cfg: ReactiveOpcUaTag in config.tags.values():
        var node_id: OpcUaNodeId = OpcUaNodeId.parse(tag_cfg.node_id.value)
        var key: String = node_id.to_string()
        configured_keys[key] = true

        if _entries.has(key):
            var entry: TagEntry = _entries[key]
            var changed: bool = entry.is_active != tag_cfg.is_active.value \
                or not is_equal_approx(entry.sampling_ms, tag_cfg.sampling_ms.value) \
                or not is_equal_approx(entry.deadband, tag_cfg.deadband.value)

            entry.display_name = tag_cfg.display_name.value
            entry.is_active = tag_cfg.is_active.value
            entry.sampling_ms = tag_cfg.sampling_ms.value
            entry.deadband = tag_cfg.deadband.value

            if changed:
                _dirty = true
        else:
            var entry: TagEntry = TagEntry.new()
            entry.node_id = node_id
            entry.display_name = tag_cfg.display_name.value
            entry.is_active = tag_cfg.is_active.value
            entry.sampling_ms = tag_cfg.sampling_ms.value
            entry.deadband = tag_cfg.deadband.value
            _entries[key] = entry
            _dirty = true

    for key: String in _entries.keys().duplicate():
        if not configured_keys.has(key):
            _entries.erase(key)
            _dirty = true

# ── Runtime state ───────────────────────────────────────────────────────────

func is_dirty() -> bool:
    return _dirty


func is_empty() -> bool:
    return _entries.is_empty()


func has_tag(node_id: OpcUaNodeId) -> bool:
    return _entries.has(node_id.to_string())

# ── Subscription lifecycle ────────────────────────────────────────────────────

func rebuild(client: GodotOpcUa) -> void:
    _dirty = false

    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1

    var specs: Array = []
    for entry: TagEntry in _entries.values():
        if entry.is_active:
            specs.append({
                "node_id": entry.node_id,
                "display_name": entry.display_name,
                "sampling_ms": entry.sampling_ms,
                "deadband": entry.deadband,
            })

    if specs.is_empty():
        return

    _sub_handle = client.create_subscription(specs, pub_interval_ms)
    if _sub_handle == -1:
        push_warning(
            "OpcUaGroup [%s]: failed to create subscription at %dms." \
            % [group_id, pub_interval_ms]
        )


func delete(client: GodotOpcUa) -> void:
    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1


func get_handle() -> int:
    return _sub_handle

# ── Value updates / writes ───────────────────────────────────────────────────

func apply_update(node_id: OpcUaNodeId, value: Variant) -> bool:
    var entry: TagEntry = _entries.get(node_id.to_string())
    if entry == null:
        return false
    entry.value = value
    tag_value_changed.emit(node_id, value)
    return true


func get_value(node_id: OpcUaNodeId) -> Variant:
    var entry: TagEntry = _entries.get(node_id.to_string())
    if entry == null:
        return null
    return entry.value


func write_tag(node_id: OpcUaNodeId, value: Variant, client: GodotOpcUa) -> bool:
    if not has_tag(node_id):
        push_warning("OpcUaGroup [%s]: write on unregistered tag '%s'." % [group_id, node_id.to_string()])
        return false
    return client.write_node(node_id, value)

# ── Teardown ─────────────────────────────────────────────────────────────────

func teardown(client: GodotOpcUa) -> void:
    delete(client)

    if _bound_tags != null and _tags_changed_callable.is_valid():
        _bound_tags.disconnect_self_changed(_tags_changed_callable)

    _bound_tags = null
    _tags_changed_callable = Callable()
    _entries.clear()
