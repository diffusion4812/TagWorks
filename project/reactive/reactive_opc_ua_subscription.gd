class_name ReactiveOpcUaSubscription
extends Reactive

var id: ReactiveString
var display_name: ReactiveString
var pub_interval_ms: ReactiveFloat
var tags: ReactiveDictionary   # key: String (canonical OpcUaNodeId), value: ReactiveOpcUaTag

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaSubscription") -> void:
    super._init(initial_owner, label)

    id = ReactiveString.new("", self, "id")
    display_name = ReactiveString.new("", self, "display_name")
    pub_interval_ms = ReactiveFloat.new(1000.0, self, "pub_interval_ms")
    tags = ReactiveDictionary.new(
        {}, self, "tags",
        TYPE_STRING, &"", null,
        TYPE_OBJECT, &"Resource", null
    )

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
        var key: String = tag.node_id.value
        if tags.has_entry(key):
            push_warning("ReactiveOpcUaSubscription: duplicate node id '%s' — overwriting." % key)
        tags.set_entry(key, tag)

func to_data() -> Dictionary:
    var result: Array = []
    for item: Variant in tags.values():
        if item is ReactiveOpcUaTag:
            result.append(item.to_data())
        else:
            push_warning("ReactiveOpcUaSubscription: item in tags is not a ReactiveOpcUaTag — skipping.")

    return {
        "id": id.value,
        "pub_interval_ms": pub_interval_ms.value,
        "tags": result,
    }

## --- Convenience accessors ---

func get_tag(node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
    return tags.get_entry(node_id.to_string(), null)

func has_tag(node_id: OpcUaNodeId) -> bool:
    return tags.has_entry(node_id.to_string())

func remove_tag(node_id: OpcUaNodeId) -> bool:
    return tags.erase_entry(node_id.to_string())

func add_tag(tag: ReactiveOpcUaTag) -> void:
    var key: String = tag.node_id.value
    if tags.has_entry(key):
        push_warning("ReactiveOpcUaSubscription: duplicate node id '%s' — overwriting." % key)
    tags.set_entry(key, tag)
