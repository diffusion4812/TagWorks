class_name ReactiveOpcUaServer
extends Reactive

## Connection lifecycle states for UI display (status icons, badges, etc.).
## Mirrors the signals emitted by OpcUaServerConnection.
enum ConnectionStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    CONNECTION_FAILED,
}

## ── Persisted configuration ────────────────────────────────────────────────
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
var subscriptions: ReactiveDictionary   # key: String (subscription id), value: ReactiveOpcUaSubscription

## ── Runtime-only state ──────────────────────────────────────────────────────
## NOT persisted (excluded from to_data()/from_data()) and NOT propagated to
## the parent's self_changed signal — driven by OpcUaServerConnection /
## OpcUaManager as connection state changes. UI binds directly to these via
## connect_self_changed() for live status indicators, exactly as it would
## bind to any other Reactive field.
var connection_status: ReactiveInt      # stores a ConnectionStatus enum value
var last_error: ReactiveString          # human-readable reason for last failure/loss

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
    subscriptions = ReactiveDictionary.new(
        {}, self, "subscriptions",
        TYPE_STRING, &"", null,
        TYPE_OBJECT, &"Resource", null
    )

    # Runtime-only fields: constructed WITHOUT `self` as owner so they never
    # bubble into this server's (or any ancestor's) self_changed signal, and
    # are never touched by to_data()/from_data().
    # TODO: confirm this matches your Reactive base class's actual
    # no-propagation constructor signature/flag — same open item noted for
    # ReactiveOpcUaTag's runtime fields.
    connection_status = ReactiveInt.new(ConnectionStatus.DISCONNECTED, null, "connection_status")
    last_error = ReactiveString.new("", null, "last_error")

    if not data.is_empty():
        deserialize(data)

func _describe_value() -> String:
    return ""

func deserialize(data: Dictionary) -> void:
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

    subscriptions.clear()
    for subscription_data: Dictionary in data.get("subscriptions", []):
        var subscription: ReactiveOpcUaSubscription = ReactiveOpcUaSubscription.new(subscription_data, self, "subscription")
        subscriptions.set_entry(subscription.id.value, subscription)

func serialize() -> Dictionary:
    var serialised_subscriptions: Array = []
    for item: Variant in subscriptions.values():
        if item is ReactiveOpcUaSubscription:
            serialised_subscriptions.append(item.to_data())
        else:
            push_warning("ReactiveOpcUaServer: item in subscriptions is not a ReactiveOpcUaSubscription — skipping.")

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
        "subscriptions": serialised_subscriptions,
    }

## ── Runtime update helpers ──────────────────────────────────────────────────
## Called by OpcUaServerConnection (via OpcUaManager, which owns the
## server_id -> ReactiveOpcUaServer / OpcUaServerConnection association) as
## connection lifecycle events occur. Centralizing these here — rather than
## having callers set connection_status.value directly — keeps "what counts
## as a status transition" logic in one place.
func set_connected() -> void:
    connection_status.value = ConnectionStatus.CONNECTED
    last_error.value = ""

func set_disconnected() -> void:
    connection_status.value = ConnectionStatus.DISCONNECTED

func set_connecting() -> void:
    connection_status.value = ConnectionStatus.CONNECTING

func set_connection_failed(reason: String = "") -> void:
    connection_status.value = ConnectionStatus.CONNECTION_FAILED
    last_error.value = reason
