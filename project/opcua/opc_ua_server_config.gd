# resources/opc_ua_server_config.gd
class_name OpcUaServerConfig
extends RefCounted

var id:                    String = ""
var display_name:          String = ""
var endpoint_url:          String = ""
var security_policy:       String = "None"
var message_mode:          String = "None"
var username:              String = ""
var password:              String = ""
var pub_interval_ms:       float  = 50.0
var poll_interval_sec:     float  = 0.01
var reconnect_interval_sec: float = 3.0
var max_reconnect_attempts: int   = 10

## Ordered list of OpcUaSubscriptionGroupConfig
var subscription_groups: Array[OpcUaSubscriptionGroupConfig] = []

func add_group(group: OpcUaSubscriptionGroupConfig) -> void:
    subscription_groups.append(group)


func remove_group(group_id: String) -> void:
    subscription_groups = subscription_groups.filter(
        func(g: OpcUaSubscriptionGroupConfig) -> bool: return g.id != group_id
    )


func get_group(group_id: String) -> OpcUaSubscriptionGroupConfig:
    for g: OpcUaSubscriptionGroupConfig in subscription_groups:
        if g.id == group_id:
            return g
    return null


func serialize() -> Dictionary:
    return {
        "id":                    id,
        "display_name":          display_name,
        "endpoint_url":          endpoint_url,
        "security_policy":       security_policy,
        "message_mode":          message_mode,
        "username":              username,
        "password":              password,
        "pub_interval_ms":       pub_interval_ms,
        "poll_interval_sec":     poll_interval_sec,
        "reconnect_interval_sec": reconnect_interval_sec,
        "max_reconnect_attempts": max_reconnect_attempts,
        "subscription_groups":   subscription_groups.map(
            func(g: OpcUaSubscriptionGroupConfig) -> Dictionary: return g.serialize()
        )
    }


static func deserialize(data: Dictionary) -> OpcUaServerConfig:
    var cfg                    :OpcUaServerConfig = OpcUaServerConfig.new()
    cfg.id                     = data.get("id",                    "")
    cfg.display_name           = data.get("display_name",          "")
    cfg.endpoint_url           = data.get("endpoint_url",          "")
    cfg.security_policy        = data.get("security_policy",       "None")
    cfg.message_mode           = data.get("message_mode",          "None")
    cfg.username               = data.get("username",              "")
    cfg.password               = data.get("password",              "")
    cfg.pub_interval_ms        = data.get("pub_interval_ms",       50.0)
    cfg.poll_interval_sec      = data.get("poll_interval_sec",     0.01)
    cfg.reconnect_interval_sec = data.get("reconnect_interval_sec", 3.0)
    cfg.max_reconnect_attempts = data.get("max_reconnect_attempts", 10)
    for entry: Dictionary in data.get("subscription_groups", []):
        cfg.subscription_groups.append(
            OpcUaSubscriptionGroupConfig.deserialize(entry)
        )
    return cfg
