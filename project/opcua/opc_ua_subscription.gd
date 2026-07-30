## Represents one live OPC UA subscription (a published, deadbanded set of
## monitored items) — the runtime counterpart of a ReactiveOpcUaSubscription
## config entry.
##
## One instance == one ReactiveOpcUaSubscription, for the instance's entire
## lifetime. Owned and reconciled by OpcUaServerConnection: instances are
## always fully recreated (never reused/rebound) whenever ANY part of the
## server config changes — see OpcUaServerConnection._on_config_changed().
## Because of that, this class does not listen for its own config changes;
## config is supplied once, at construction, and _entries is built
## immediately.
class_name OpcUaSubscription
extends RefCounted

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

# ── Init (one-shot build) ──────────────────────────────────────────────────

func _init(cfg: ReactiveOpcUaSubscription) -> void:
    config = cfg
    subscription_id = cfg.id.value
    pub_interval_ms = cfg.pub_interval_ms.value
    _build_entries()

# ── Key helper ───────────────────────────────────────────────────────────────

static func _key(node_id: OpcUaNodeId) -> String:
    return node_id.to_tag_name()

# ── Entry list build ──────────────────────────────────────────────────────

func _build_entries() -> void:
    _entries.clear()

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

# ── Runtime state ───────────────────────────────────────────────────────────

func is_empty() -> bool:
    return _entries.is_empty()


func has_tag(node_id: OpcUaNodeId) -> bool:
    return _entries.has(_key(node_id))

# ── Subscription lifecycle ────────────────────────────────────────────────────

func rebuild(client: GodotOpcUa) -> void:
    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1

    _sub_handle = client.create_subscription(pub_interval_ms)
    if _sub_handle == -1:
        push_warning(
            "OpcUaSubscription [%s]: failed to create subscription at %dms." \
            % [subscription_id, pub_interval_ms]
        )

    for entry: SubscriptionEntry in _entries.values():
        var on_data: Callable = func(_d: Dictionary) -> void:
            entry.tag.quality.value   = _d.get("quality")
            entry.tag.value.value     = _d.get("value")
            entry.tag.timestamp.value = _d.get("timestamp_ms")

        client.subscribe(
            _sub_handle,
            entry.node_id,
            on_data,
            100.0,
            0.0
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
    _entries.clear()
