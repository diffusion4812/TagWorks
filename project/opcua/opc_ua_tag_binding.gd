class_name OpcUaTagBinding
extends RefCounted

var server_id: String
var group_id:  String
var node_id:   OpcUaNodeId

func _init(
    server_id_val: String      = "",
    group_id_val:  String      = "",
    node_id_val:   OpcUaNodeId = null
) -> void:
    server_id = server_id_val
    group_id  = group_id_val
    node_id   = node_id_val

func is_valid() -> bool:
    return server_id != "" and group_id != "" and node_id != null

func node_id_string() -> String:
    return node_id.to_string() if node_id != null else ""
