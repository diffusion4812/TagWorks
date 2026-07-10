# opcua/opc_ua_subscription_mode.gd
class_name OpcUaSubscriptionMode

enum Mode {
    ALWAYS,           ## Subscribe regardless of widget visibility
    VISIBLE_ONLY,     ## Only subscribe while the owning widget is visible
}
