# opcua/opc_ua_subscription_group.gd
class_name OpcUaSubscriptionGroup
extends RefCounted

## Publishing interval that defines this group
var pub_interval_ms: float

## { tag_name: String -> TagEntry } — only tags assigned to this group
var _entries: Dictionary = {}

var _sub_handle: int = -1
var _dirty:      bool = false

func _init(p_interval_ms: float) -> void:
    pub_interval_ms = p_interval_ms

# ── Entry management ──────────────────────────────────────────────────────────

func add_entry(entry: OpcUaTagRegistry.TagEntry) -> void:
    _entries[entry.tag_name] = entry
    _dirty = true


func remove_entry(tag_name: String) -> void:
    if _entries.erase(tag_name):
        _dirty = true


func has_entry(tag_name: String) -> bool:
    return _entries.has(tag_name)


func is_empty() -> bool:
    return _entries.is_empty()


func is_dirty() -> bool:
    return _dirty

# ── Subscription lifecycle ────────────────────────────────────────────────────

## Rebuilds the OPC UA subscription for all entries in this group.
func rebuild(client: GodotOpcUa) -> void:
    _dirty = false

    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1

    if _entries.is_empty():
        return

    var specs: Array = []
    for entry: OpcUaTagRegistry.TagEntry in _entries.values():
        specs.append({
            "node_id":     entry.node_id,
            "sampling_ms": entry.sampling_ms,
            "deadband":    entry.deadband,
        })

    _sub_handle = client.create_subscription(specs, pub_interval_ms)
    if _sub_handle == -1:
        push_warning(
            "OpcUaSubscriptionGroup: failed to create subscription at %dms." \
            % pub_interval_ms
        )


func delete(client: GodotOpcUa) -> void:
    if _sub_handle != -1:
        client.delete_subscription(_sub_handle)
        _sub_handle = -1
    _entries.clear()
    _dirty = false


func get_handle() -> int:
    return _sub_handle
