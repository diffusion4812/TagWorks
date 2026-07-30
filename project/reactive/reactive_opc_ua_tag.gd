# data/reactive_opc_ua_tag.gd
class_name ReactiveOpcUaTag
extends Reactive

## OPC UA tag data types relevant for value coercion, UI formatting, and
## write validation. Extend as needed to match your server's supported types.
enum TagType {
    BOOL,
    INT32,
    UINT32,
    FLOAT,
    DOUBLE,
    STRING,
}

## ── Persisted configuration ────────────────────────────────────────────────
var id: ReactiveString
var node_id: ReactiveString
var display_name: ReactiveString
var is_active: ReactiveBool
var sampling_ms: ReactiveFloat
var deadband: ReactiveFloat
var tag_type: ReactiveInt          # stores a TagType enum value

## ── Runtime-only state ──────────────────────────────────────────────────────
## NOT persisted (excluded from to_data()/from_data()) and NOT propagated to
## the parent's self_changed signal — these update at poll rate and must not
## trigger reconciliation cascades or spurious "unsaved changes" dirty-flags
## up the ownership chain. UI code binds to these directly via
## connect_self_changed() on the individual field, same as any other
## Reactive value.
var value: ReactiveVariant
var quality: ReactiveInt       # e.g. OPC UA StatusCode / Good-Uncertain-Bad
var timestamp: ReactiveInt       # Unix time of last update, for staleness checks

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaTag") -> void:
    super._init(initial_owner, label)

    id = ReactiveString.new("", self, "id")
    node_id = ReactiveString.new("", self, "node_id")
    display_name = ReactiveString.new("", self, "display_name")
    is_active = ReactiveBool.new(true, self, "is_active")
    sampling_ms = ReactiveFloat.new(0.0, self, "sampling_ms")
    deadband = ReactiveFloat.new(0.0, self, "deadband")
    tag_type = ReactiveInt.new(TagType.FLOAT, self, "tag_type")

    # Runtime-only fields: constructed WITHOUT `self` as owner so they never
    # bubble into this tag's (or any ancestor's) self_changed signal.
    value = ReactiveVariant.new(null, null, "value")
    quality = ReactiveInt.new(0, null, "quality")
    timestamp = ReactiveInt.new(0, null, "timestamp")

    if not data.is_empty():
        from_data(data)

func _describe_value() -> String:
    return ""

func from_data(data: Dictionary) -> void:
    id.value = data.get("id", "")
    node_id.value = data.get("node_id", "")
    display_name.value = data.get("display_name", "")
    is_active.value = data.get("is_active", true)
    sampling_ms.value = data.get("sampling_ms", 0.0)
    deadband.value = data.get("deadband", 0.0)
    tag_type.value = data.get("tag_type", TagType.FLOAT)

func to_data() -> Dictionary:
    return {
        "id": id.value,
        "node_id": node_id.value,
        "display_name": display_name.value,
        "is_active": is_active.value,
        "sampling_ms": sampling_ms.value,
        "deadband": deadband.value,
        "tag_type": tag_type.value,
    }

## ── Runtime update helper ──────────────────────────────────────────────────
## Called by OpcUaGroup.apply_update() on each poll cycle. Centralizing the
## three-field update here (rather than having the group set each field
## individually) keeps the "what counts as a runtime update" logic in one
## place and makes it easy to add e.g. change-detection/deadband logic later.
func apply_runtime_update(new_value: Variant, new_quality: Variant, new_timestamp: float) -> void:
    value.value = new_value
    quality.value = new_quality
    timestamp.value = new_timestamp
