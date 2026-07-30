# data/reactive_opc_ua_tag_binding.gd
class_name ReactiveOpcUaTagBinding
extends Reactive

var server_id       : ReactiveString
var subscription_id : ReactiveString
var tag_id          : ReactiveString

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaTagBinding") -> void:
    super._init(initial_owner, label)

    server_id       = ReactiveString.new("", self, "server_id")
    subscription_id = ReactiveString.new("", self, "subscription_id")
    tag_id          = ReactiveString.new("", self, "tag_id")

    if not data.is_empty():
        from_data(data)


func _describe_value() -> String:
    return ""

func from_data(data: Dictionary) -> void:
    server_id.value       = data.get("server_id", "")
    subscription_id.value = data.get("subscription_id",  "")
    tag_id.value         = data.get("tag_id",   "")


func to_data() -> Dictionary:
    return {
        "server_id": server_id.value,
        "subscription_id":  subscription_id.value,
        "tag_id":   tag_id.value,
    }
