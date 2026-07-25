# data/reactive_opc_ua_tag_binding.gd
class_name ReactiveOpcUaTagBinding
extends Reactive

var server_id: ReactiveString
var group_id:  ReactiveString
var node_id:   ReactiveString

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaTagBinding") -> void:
    super._init(initial_owner, label)

    server_id = ReactiveString.new("", self, "server_id")
    group_id  = ReactiveString.new("", self, "group_id")
    node_id   = ReactiveString.new("", self, "node_id")

    if not data.is_empty():
        from_data(data)


func _describe_value() -> String:
    return ""


func is_valid() -> bool:
    return server_id.value != "" and group_id.value != "" and node_id.value != ""


func parsed_node_id() -> OpcUaNodeId:
    return OpcUaNodeId.parse(node_id.value) if node_id.value != "" else null


func from_data(data: Dictionary) -> void:
    server_id.value = data.get("server_id", "")
    group_id.value  = data.get("group_id",  "")
    node_id.value   = data.get("node_id",   "")


func to_data() -> Dictionary:
    return {
        "server_id": server_id.value,
        "group_id":  group_id.value,
        "node_id":   node_id.value,
    }
