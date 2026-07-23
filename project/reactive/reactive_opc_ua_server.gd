class_name ReactiveOpcUaServer
extends Reactive

var id: ReactiveString
var display_name: ReactiveString
var endpoint_url: ReactiveString
var security_policy: ReactiveString
var message_mode: ReactiveString
var username: ReactiveString
var password: ReactiveString
var pub_interval_ms: ReactiveFloat
var poll_interval_sec: ReactiveFloat
var reconnect_interval_sec: ReactiveFloat
var max_reconnect_attempts: ReactiveInt
var groups: ReactiveArray   # ReactiveArray of ReactiveOpcUaGroup

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveOpcUaServer") -> void:
    super._init(initial_owner, label)

    id = ReactiveString.new("", self, "id")
    display_name = ReactiveString.new("", self, "display_name")
    endpoint_url = ReactiveString.new("", self, "endpoint_url")
    security_policy = ReactiveString.new("None", self, "security_policy")
    message_mode = ReactiveString.new("None", self, "message_mode")
    username = ReactiveString.new("", self, "username")
    password = ReactiveString.new("", self, "password")
    pub_interval_ms = ReactiveFloat.new(50.0, self, "pub_interval_ms")
    poll_interval_sec = ReactiveFloat.new(0.01, self, "poll_interval_sec")
    reconnect_interval_sec = ReactiveFloat.new(3.0, self, "reconnect_interval_sec")
    max_reconnect_attempts = ReactiveInt.new(10, self, "max_reconnect_attempts")
    groups = ReactiveArray.new([], self, "groups")

    if not data.is_empty():
        from_data(data)

func _describe_value() -> String:
    return ""

func from_data(data: Dictionary) -> void:
    id.value = data.get("id", "")
    display_name.value = data.get("display_name", "")
    endpoint_url.value = data.get("endpoint_url", "")
    security_policy.value = data.get("security_policy", "None")
    message_mode.value = data.get("message_mode", "None")
    username.value = data.get("username", "")
    password.value = data.get("password", "")
    pub_interval_ms.value = data.get("pub_interval_ms", 50.0)
    poll_interval_sec.value = data.get("poll_interval_sec", 0.01)
    reconnect_interval_sec.value = data.get("reconnect_interval_sec", 3.0)
    max_reconnect_attempts.value = data.get("max_reconnect_attempts", 10)

    groups.clear()
    for group_data: Dictionary in data.get("groups", []):
        var group: ReactiveOpcUaGroup = ReactiveOpcUaGroup.new(group_data, self, "group")
        groups.append(group)

func to_data() -> Dictionary:
    var group_results: Array = []
    for item: Variant in groups.values():
        if item is ReactiveOpcUaGroup:
            group_results.append(item.to_data())
        else:
            push_warning("ReactiveOpcUaServer: item in groups is not a ReactiveOpcUaGroup — skipping.")

    return {
        "id": id.value,
        "display_name": display_name.value,
        "endpoint_url": endpoint_url.value,
        "security_policy": security_policy.value,
        "message_mode": message_mode.value,
        "username": username.value,
        "password": password.value,
        "pub_interval_ms": pub_interval_ms.value,
        "poll_interval_sec": poll_interval_sec.value,
        "reconnect_interval_sec": reconnect_interval_sec.value,
        "max_reconnect_attempts": max_reconnect_attempts.value,
        "groups": group_results,
    }
