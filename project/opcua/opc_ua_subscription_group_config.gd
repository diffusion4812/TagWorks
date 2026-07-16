# resources/opc_ua_subscription_group_config.gd
class_name OpcUaSubscriptionGroupConfig
extends RefCounted

var id:             String = ""
var display_name:   String = ""
var pub_interval_ms: float = 500.0

func serialize() -> Dictionary:
    return {
        "id":              id,
        "display_name":    display_name,
        "pub_interval_ms": pub_interval_ms,
    }


static func deserialize(data: Dictionary) -> OpcUaSubscriptionGroupConfig:
    var cfg: OpcUaSubscriptionGroupConfig = OpcUaSubscriptionGroupConfig.new()
    cfg.id               = data.get("id",              "")
    cfg.display_name     = data.get("display_name",    "")
    cfg.pub_interval_ms  = data.get("pub_interval_ms", 500.0)
    return cfg
