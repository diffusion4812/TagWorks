# opcua/opc_ua_tag_registry.gd
class_name OpcUaTagRegistry
extends RefCounted

signal tag_registered(key: String)
signal tag_unregistered(key: String)
signal tag_activation_changed(key: String, active: bool)

var _entries: Dictionary = {}

# ── Registration ──────────────────────────────────────────────────────────────

func register(
    node_id:         OpcUaNodeId,
    sampling_ms:     float                   = 100.0,
    pub_interval_ms: float                   = 50.0,
    deadband:        float                   = 0.0,
    mode:            OpcUaSubscriptionMode.Mode = OpcUaSubscriptionMode.Mode.ALWAYS
) -> void:
    var key := node_id.to_tag_name()
    if not _entries.has(key):
        _entries[key] = TagEntry.new(key)

    var entry: TagEntry     = _entries[key]
    entry.node_id           = node_id
    entry.sampling_ms       = sampling_ms
    entry.pub_interval_ms   = pub_interval_ms
    entry.deadband          = deadband
    entry.subscribe_mode    = mode

    # ALWAYS-mode tags are immediately active
    var should_be_active := (mode == OpcUaSubscriptionMode.Mode.ALWAYS)
    if entry.is_active != should_be_active:
        entry.is_active = should_be_active

    tag_registered.emit(key)


func unregister(node_id: OpcUaNodeId) -> void:
    var key := node_id.to_tag_name()
    if _entries.erase(key):
        tag_unregistered.emit(key)

# ── Visibility gate ───────────────────────────────────────────────────────────

## Called by the widget when its visibility changes.
## Has no effect on ALWAYS-mode tags.
func set_tag_visible(node_id: OpcUaNodeId, visible: bool) -> void:
    var entry := _get_entry(node_id)
    if entry == null:
        return
    if entry.subscribe_mode == OpcUaSubscriptionMode.Mode.ALWAYS:
        return

    var was_active := entry.is_active
    entry.is_active = visible
    if entry.is_active != was_active:
        tag_activation_changed.emit(entry.tag_name, entry.is_active)

# ── Value access ──────────────────────────────────────────────────────────────

func get_value(node_id: OpcUaNodeId) -> Variant:
    var entry := _get_entry(node_id)
    return entry.value if entry else null


func is_quality_good(node_id: OpcUaNodeId) -> bool:
    var entry := _get_entry(node_id)
    return entry.quality_good if entry else false


func has_tag(node_id: OpcUaNodeId) -> bool:
    return _entries.has(node_id.to_tag_name())


func mark_dirty(node_id: OpcUaNodeId) -> void:
    var entry := _get_entry(node_id)
    if entry:
        entry.is_dirty = true

# ── Update ────────────────────────────────────────────────────────────────────

func apply_update(tag_name: String, raw: Dictionary) -> bool:
    var entry: TagEntry = _entries.get(tag_name, null)
    if entry == null or not entry.is_active:
        return false

    var new_value: Variant = raw.get("value", null)
    var quality:   bool    = raw.get("quality_good", false)

    if new_value == entry.value:
        return false

    entry.value        = new_value
    entry.quality_good = quality
    entry.last_updated = Time.get_ticks_msec() / 1000.0
    entry.is_dirty     = false
    return true

# ── Group query helpers ───────────────────────────────────────────────────────

## Returns all active entries grouped by pub_interval_ms.
## { interval_ms: float -> Array[TagEntry] }
func get_active_entries_by_interval() -> Dictionary:
    var groups: Dictionary = {}
    for entry: TagEntry in _entries.values():
        if not entry.is_active:
            continue
        var key: float = entry.pub_interval_ms
        if not groups.has(key):
            groups[key] = []
        groups[key].append(entry)
    return groups

## Returns all active entries belonging to a specific group.
## Array[TagEntry]
func get_active_entries_for_group(p_group_id: String) -> Array:
    var result: Array = []
    for entry: TagEntry in _entries.values():
        if entry.is_active and entry.group_id == p_group_id:
            result.append(entry)
    return result

func get_entry_by_name(tag_name: String) -> TagEntry:
    return _entries.get(tag_name, null)


func get_entry(node_id: OpcUaNodeId) -> TagEntry:
    return _get_entry(node_id)


func is_empty() -> bool:
    return _entries.is_empty()

# ── Private ───────────────────────────────────────────────────────────────────

func _get_entry(node_id: OpcUaNodeId) -> TagEntry:
    return _entries.get(node_id.to_tag_name(), null)

# ── Inner class ───────────────────────────────────────────────────────────────

class TagEntry:
    var node_id:          OpcUaNodeId
    var tag_name:         String
    var group_id:         String                       = ""
    var value:            Variant                      = null
    var quality_good:     bool                         = false
    var last_updated:     float                        = 0.0
    var is_dirty:         bool                         = false
    var sampling_ms:      float                        = 100.0
    ## Which SubscriptionGroup this tag belongs to
    var pub_interval_ms:  float                        = 50.0
    var deadband:         float                        = 0.0
    var subscribe_mode:   OpcUaSubscriptionMode.Mode   = OpcUaSubscriptionMode.Mode.ALWAYS
    ## Whether the tag is currently actively subscribed
    var is_active:        bool                         = true

    func _init(p_tag_name: String) -> void:
        tag_name = p_tag_name
