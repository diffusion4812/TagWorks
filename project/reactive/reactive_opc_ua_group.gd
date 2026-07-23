# data/reactive_opc_ua_group.gd
class_name ReactiveOpcUaGroup
extends Reactive

var id: ReactiveString
var pub_interval_ms: ReactiveFloat
var tags: ReactiveArray   # ReactiveArray of ReactiveOpcUaTag

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaGroup") -> void:
    super._init(initial_owner, label)

    id = ReactiveString.new("", self, "id")
    pub_interval_ms = ReactiveFloat.new(1000.0, self, "pub_interval_ms")
    tags = ReactiveArray.new([], self, "tags")

    if not data.is_empty():
        from_data(data)

func _describe_value() -> String:
    return ""

func from_data(data: Dictionary) -> void:
    id.value = data.get("id", "")
    pub_interval_ms.value = data.get("pub_interval_ms", 1000.0)

    tags.clear()
    for tag_data: Dictionary in data.get("tags", []):
        var tag: ReactiveOpcUaTag = ReactiveOpcUaTag.new(tag_data, self, "tag")
        tags.append(tag)

func to_data() -> Dictionary:
    var result: Array = []
    for item: Variant in tags.values():
        if item is ReactiveOpcUaTag:
            result.append(item.to_data())
        else:
            push_warning("ReactiveOpcUaGroup: item in tags is not a ReactiveOpcUaTag — skipping.")

    return {
        "id": id.value,
        "pub_interval_ms": pub_interval_ms.value,
        "tags": result,
    }
