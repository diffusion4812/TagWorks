class_name OpcUaTagBinding
extends RefCounted

var server_id       : String
var subscription_id : String
var tag_id          : String

func _init(
    server_id_val       : String = "",
    subscription_id_val : String = "",
    tag_id_val          : String = ""
) -> void:
    server_id       = server_id_val
    subscription_id = subscription_id_val
    tag_id          = tag_id_val
