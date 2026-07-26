# opcua/opc_ua_subscription.gd
## Represents one live OPC UA subscription (a published, deadbanded set of
## monitored items) — the runtime counterpart of a ReactiveOpcUaSubscription
## config entry.
##
## SIMPLE MODE: this version does not diff individual tag changes. Any
## change to the underlying config's `tags` array causes the full entry
## list to be rebuilt and the subscription marked dirty, so the next
## rebuild() call tears down and recreates the OPC UA subscription from
## scratch. Fine for correctness and clarity; revisit with per-tag
## reconciliation later if subscription churn becomes a performance concern.
class_name OpcUaSubscription
extends RefCounted

signal tag_value_changed(node_id: OpcUaNodeId, value: Variant)

## Runtime entry: a reference to the live tag, plus its parsed node id
## (avoids re-parsing on every lookup).
class SubscriptionEntry:
    var node_id: OpcUaNodeId
    var tag: ReactiveOpcUaTag   # reference to the shared, live tag object

# ── Identity / config ──────────────────────────────────────────────────────

var subscription_id: String
var pub_interval_ms: float
var config: ReactiveOpcUaSubscription

var _entries: Dictionary = {}   # tag key (String) -> SubscriptionEntry
var _sub_handle: int = -1
var _dirty: bool = false

var _bound_tags: ReactiveArray = null
var _tags_changed_callable: Callable = Callable()

# ── Init ──────────────────────────────────────────────────────────────────

func _init(p_subscription_id: String) -> void:
    subscription_id = p_subscription_id

# ── Config application ──────────────────────────────────────────────────────

func apply_config(cfg: ReactiveOpcUaSubscription) -> void:
    config = cfg
    subscription_id = cfg.id.value

    if not is_equal_approx(pub_interval_ms, cfg.pub_interval_ms.value):
        pub_interval_ms = cfg.pub_interval_ms.value
        _dirty = true

    _bind_tags(cfg.tags)
    _rebuild_entries()

# ── Binding ─────────────────────────────────────────────────────────────────

func _bind_tags(tags: ReactiveArray) -> void:
    if _bound_tags != null and _tags_changed_callable.is_valid():
        _bound_tags.reactive_changed.disconnect(_tags_changed_callable)

    _bound_tags = null
    _tags_changed_callable = Callable()

    if tags == null:
        return

    _tags_changed_callable = func(_origin: Reactive) -> void:
        _rebuild_entries()

    tags.connect_self_changed(_tags_changed_callable)
    _bound_tags = tags

# ── Key helper ───────────────────────────────────────────────────────────────

static func _key(node_id: OpcUaNodeId) -> String:
    return node_id.to_tag_name()

# ── Entry list rebuild (no diffing) ─────────────────────────────────────────

## Discards and rebuilds the entire _entries map from the current config
## every time it's called (initial apply_config, or any subsequent tag
## list change). Always marks the subscription dirty, so the connection's
## poll loop will call rebuild() to recreate the actual OPC UA subscription.
func _rebuild_entries() -> void:
    _entries.clear()

    if config == null:
        _dirty = true
        return

    for tag_cfg: ReactiveOpcUaTag in config.tags.values():
        var node_id: OpcUaNodeId = OpcUaNodeId.parse(tag_cfg.node_id.value)
        if node_id == null:
            push_warning("OpcUaSubscription [%s]: could not parse node_id '%s' — skipping tag." % [subscription_id, tag_cfg.node_id.value])
            continue

        var key: String = _key(node_id)
        if _entries.has(key):
            push_warning("OpcUaSubscription [%s]: duplicate tag key '%s' — skipping duplicate." % [subscription_id, key])
            continue

        var entry: SubscriptionEntry = SubscriptionEntry.new()
        entry.node_id = node_id
        entry.tag = tag_cfg
        _entries[key] = entry

    _dirty = true

# ── Runtime state ───────────────────────────────────────────────────────────

func is_dirty() -> bool:
    return _dirty


func is_empty() -> bool:
    return _entries.is_empty()


func has_tag(node_id: OpcUaNodeId) -> bool:
    return _entries.has(_key(node_id))

# ── Subscription lifecycle ────────────────────────────────────────────────────

func rebuild(client: GodotOpcUa) -> void:
    _dirty = false

    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1

    var specs: Array = []
    for entry: SubscriptionEntry in _entries.values():
        if entry.tag.is_active.value:
            specs.append({
                "node_id": entry.node_id,
                "display_name": entry.tag.display_name.value,
                "sampling_ms": entry.tag.sampling_ms.value,
                "deadband": entry.tag.deadband.value,
            })

    if specs.is_empty():
        return

    _sub_handle = client.create_subscription(specs, pub_interval_ms)
    if _sub_handle == -1:
        push_warning(
            "OpcUaSubscription [%s]: failed to create subscription at %dms." \
            % [subscription_id, pub_interval_ms]
        )


func delete(client: GodotOpcUa) -> void:
    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1


func get_handle() -> int:
    return _sub_handle

# ── Value updates / writes ───────────────────────────────────────────────────

func apply_update(node_id: OpcUaNodeId, value: Variant, quality: Variant = null, timestamp: float = -1.0) -> bool:
    var entry: SubscriptionEntry = _entries.get(_key(node_id))
    if entry == null:
        return false

    var ts: float = timestamp if timestamp >= 0.0 else Time.get_unix_time_from_system()
    entry.tag.apply_runtime_update(value, quality, ts)
    tag_value_changed.emit(node_id, value)
    return true


func get_value(node_id: OpcUaNodeId) -> Variant:
    var entry: SubscriptionEntry = _entries.get(_key(node_id))
    if entry == null:
        return null
    return entry.tag.value.value


func get_tag(node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
    var entry: SubscriptionEntry = _entries.get(_key(node_id))
    return entry.tag if entry != null else null


func write_tag(node_id: OpcUaNodeId, value: Variant, client: GodotOpcUa) -> bool:
    if not has_tag(node_id):
        push_warning("OpcUaSubscription [%s]: write on unregistered tag '%s'." % [subscription_id, node_id.to_string()])
        return false
    return client.write_node(node_id, value)

# ── Teardown ─────────────────────────────────────────────────────────────────

func teardown(client: GodotOpcUa) -> void:
    delete(client)

    if _bound_tags != null and _tags_changed_callable.is_valid():
        _bound_tags.reactive_changed.disconnect(_tags_changed_callable)

    _bound_tags = null
    _tags_changed_callable = Callable()
    _entries.clear()
