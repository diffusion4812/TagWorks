class_name ReactiveOpcUaWriteTarget
extends Reactive

var server_id : ReactiveString
var node_id   : ReactiveString

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaWriteTarget") -> void:
    super._init(initial_owner, label)

    server_id = ReactiveString.new("", self, "server_id")
    node_id   = ReactiveString.new("", self, "node_id")

    if not data.is_empty():
        deserialize(data)

func _describe_value() -> String:
    return node_id.value

func deserialize(data: Dictionary) -> void:
    server_id.value = data.get("server_id", "")
    node_id.value   = data.get("node_id", "")

func serialize() -> Dictionary:
    return {
        "server_id": server_id.value,
        "node_id": node_id.value,
    }
