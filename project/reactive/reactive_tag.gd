class_name ReactiveTag
extends Reactive

var server_id :ReactiveString   # OPC UA server identifier
var group_id  :ReactiveString   # OPC UA group identifier
var node_id   :ReactiveVariant  # holds an OpcUaNodeId (or null)
var is_dirty  :ReactiveBool     # unsaved changes

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveTag") -> void:
    super._init(initial_owner, label)

    server_id = ReactiveString.new("", self, "server_id")
    group_id  = ReactiveString.new("", self, "group_id")
    node_id   = ReactiveVariant.new(null, self, "node_id")
    is_dirty  = ReactiveBool.new(false, self, "is_dirty")

    server_id.connect_self_changed(
        func(_v: ReactiveString) -> void:
            is_dirty.value = true
    )
    group_id.connect_self_changed(
        func(_v: ReactiveString) -> void:
            is_dirty.value = true
    )
    node_id.connect_self_changed(
        func(_v: ReactiveVariant) -> void:
            is_dirty.value = true
    )

    if not data.is_empty():
        from_data(data)


func to_tag_name() -> String:
    var node :OpcUaNodeId = node_id.value
    return node.to_tag_name() if node != null else ""


func from_data(data: Dictionary) -> void:
    server_id.value = data.get("server_id", "")
    group_id.value  = data.get("group_id", "")

    var node_data : String = data.get("node_id", null)
    node_id.value = OpcUaNodeId.parse(node_data) if node_data != "" else null


func to_data() -> Dictionary:
    var node :OpcUaNodeId = node_id.value
    return {
        "server_id": server_id.value,
        "group_id":  group_id.value,
        "node_id":   node.to_tag_name() if node != null else ""
    }
