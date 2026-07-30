class_name OpcUaServer
extends Node

## One instance == one ReactiveOpcUaServer, for the instance's entire
## lifetime. Owned and reconciled by OpcUaManager: created when a server
## is added to the project config, torn down (see teardown()) when it's
## removed. The config reference is fixed at construction — it is never
## rebound to a different ReactiveOpcUaServer object.
##
## Because config.reactive_changed bubbles up from any nested mutation
## (endpoint/security params, subscription added/removed, tag added/
## removed/toggled, deadband changed, etc.), ANY change anywhere in the
## config tree triggers a full teardown + rebuild of all subscriptions,
## and a full disconnect/reconnect if currently connected.
##
## This trades performance for simplicity: a single tag's `is_active`
## toggle costs the same as changing the endpoint URL (full session
## reconnect). Acceptable for MVP; revisit with tiered reconciliation
## if churn becomes a real-world problem.
var config: ReactiveOpcUaServer

var _client: GodotOpcUa
var _last_tick_ms: int = 0
var _poll_accum_sec: float = 0.0
var _subscriptions: Dictionary = {}
var _config_changed_callable: Callable = Callable()

var client: GodotOpcUa:
    get: return _client

func _init(cfg: ReactiveOpcUaServer) -> void:
    _client = GodotOpcUa.new()

    config = cfg
    name = "OpcUaServerConnection_%s" % config.id.value

    _config_changed_callable = func(_origin: Reactive) -> void:
        _on_config_changed()
    config.connect_self_changed(_config_changed_callable)

    _rebuild_subscriptions_from_config()

func _process(delta: float) -> void:
    if not _is_connected():
        return
    _poll_accum_sec += delta
    var interval: float = maxf(config.poll_interval_sec.value, 0.001)
    if _poll_accum_sec < interval:
        return
    _poll_accum_sec = 0.0

    var err: Error = _client.iterate(1)
    if err != OK:
        _handle_iterate_error(err)

func _exit_tree() -> void:
    if _is_connected():
        disconnect_from_server()

# ── Reactive binding ──────────────────────────────────────────────────────

## Fires on any change anywhere in the config tree (after the initial
## construction-time build). Tears down and recreates the full
## subscription set; reconnects from scratch if a connection was already
## active.
func _on_config_changed() -> void:
    var was_connected: bool = _is_connected()

    if was_connected:
        disconnect_from_server()

    _rebuild_subscriptions_from_config()

    if was_connected:
        connect_to_server()

# ── Subscription (re)build ───────────────────────────────────────────────

func _rebuild_subscriptions_from_config() -> void:
    for subscription_id: String in _subscriptions.keys().duplicate():
        _teardown_subscription(subscription_id)

    var seen_ids: Dictionary = {}
    for sub_cfg: ReactiveOpcUaSubscription in config.subscriptions.values():
        var subscription_id: String = sub_cfg.id.value
        if seen_ids.has(subscription_id):
            push_warning("OpcUaServerConnection [%s]: duplicate subscription id '%s' — skipping duplicate." % [config.id.value, subscription_id])
            continue
        seen_ids[subscription_id] = true
        _spawn_subscription(sub_cfg)


func _spawn_subscription(sub_cfg: ReactiveOpcUaSubscription) -> void:
    var subscription: OpcUaSubscription = OpcUaSubscription.new(sub_cfg)
    _subscriptions[sub_cfg.id.value] = subscription

    if _is_connected():
        subscription.rebuild(_client)


func _teardown_subscription(subscription_id: String) -> void:
    var subscription: OpcUaSubscription = _subscriptions.get(subscription_id)
    if subscription != null:
        subscription.teardown(_client)
    _subscriptions.erase(subscription_id)

# ── Connection ────────────────────────────────────────────────────────────

func connect_to_server() -> bool:
    config.set_connecting()

    var err: Error
    if config.username.value.is_empty():
        err = _client.connect_to_server(config.endpoint_url.value)
    else:
        err = _client.connect_with_credentials(
            config.endpoint_url.value, config.username.value, config.password.value
        )

    if err != OK:
        var message: String = "Connection attempt failed: %s" % error_string(err)
        push_warning("OpcUaServerConnection [%s]: %s" % [config.id.value, message])
        config.set_connection_failed(message)
        return false

    _rebuild_all_subscriptions()
    _last_tick_ms = Time.get_ticks_msec()
    config.set_connected()
    return true


func disconnect_from_server() -> void:
    for subscription: OpcUaSubscription in _subscriptions.values():
        subscription.delete(_client)
    _client.disconnect_server()
    config.set_disconnected()


## Called by OpcUaManager when this connection's server has been removed
## from the project config entirely.
func teardown() -> void:
    if _is_connected():
        disconnect_from_server()

    for subscription_id: String in _subscriptions.keys().duplicate():
        _teardown_subscription(subscription_id)

    if _config_changed_callable.is_valid():
        config.reactive_changed.disconnect(_config_changed_callable)
    _config_changed_callable = Callable()

    queue_free()

# ── Poll error handling ─────────────────────────────────────────────────

func _handle_iterate_error(err: Error) -> void:
    match err:
        Error.ERR_CONNECTION_ERROR, Error.ERR_DOES_NOT_EXIST:
            var message: String = "Connection lost during polling: %s" % error_string(err)
            push_warning("OpcUaServerConnection [%s]: %s" % [config.id.value, message])
            config.set_connection_failed(message)
        Error.ERR_TIMEOUT:
            push_warning("OpcUaServerConnection [%s]: iterate() timed out." % config.id.value)
        _:
            push_warning("OpcUaServerConnection [%s]: iterate() error: %s" % [config.id.value, error_string(err)])

# ── Write ─────────────────────────────────────────────────────────────────

func write_tag(node_id: OpcUaNodeId, value: Variant) -> bool:
    var subscription: OpcUaSubscription = find_subscription_for_tag(node_id)
    if subscription == null:
        push_warning("OpcUaServerConnection [%s]: write on unregistered tag '%s'." % [config.id.value, node_id.to_string()])
        return false
    return subscription.write_tag(node_id, value, _client)

# ── Tag / subscription lookup ────────────────────────────────────────────────

func find_subscription_for_tag(node_id: OpcUaNodeId) -> OpcUaSubscription:
    for subscription: OpcUaSubscription in _subscriptions.values():
        if subscription.has_tag(node_id):
            return subscription
    return null


func get_tag(node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
    var subscription: OpcUaSubscription = find_subscription_for_tag(node_id)
    return subscription.get_tag(node_id) if subscription != null else null

# ── Accessors ─────────────────────────────────────────────────────────────

func is_server_connected() -> bool:
    return _is_connected()


func get_active_subscription_count() -> int:
    return _subscriptions.size()


func get_subscription_ids() -> Array:
    return _subscriptions.keys()


func get_subscription(subscription_id: String) -> OpcUaSubscription:
    return _subscriptions.get(subscription_id, null)


func _rebuild_all_subscriptions() -> void:
    for subscription: OpcUaSubscription in _subscriptions.values():
        subscription.rebuild(_client)

# ── Internal helpers ──────────────────────────────────────────────────────

func _is_connected() -> bool:
    return config.connection_status.value == ReactiveOpcUaServer.ConnectionStatus.CONNECTED
