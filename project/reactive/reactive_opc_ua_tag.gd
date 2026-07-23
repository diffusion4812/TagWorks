# data/reactive_opc_ua_tag.gd
class_name ReactiveOpcUaTag
extends Reactive

var node_id: ReactiveString
var display_name: ReactiveString
var is_active: ReactiveBool
var sampling_ms: ReactiveFloat
var deadband: ReactiveFloat

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaTag") -> void:
    super._init(initial_owner, label)

    node_id = ReactiveString.new("", self, "node_id")
    display_name = ReactiveString.new("", self, "display_name")
    is_active = ReactiveBool.new(true, self, "is_active")
    sampling_ms = ReactiveFloat.new(0.0, self, "sampling_ms")
    deadband = ReactiveFloat.new(0.0, self, "deadband")

    if not data.is_empty():
        from_data(data)

func _describe_value() -> String:
    return ""

func from_data(data: Dictionary) -> void:
    node_id.value = data.get("node_id", "")
    display_name.value = data.get("display_name", "")
    is_active.value = data.get("is_active", true)
    sampling_ms.value = data.get("sampling_ms", 0.0)
    deadband.value = data.get("deadband", 0.0)

func to_data() -> Dictionary:
    return {
        "node_id": node_id.value,
        "display_name": display_name.value,
        "is_active": is_active.value,
        "sampling_ms": sampling_ms.value,
        "deadband": deadband.value,
    }
