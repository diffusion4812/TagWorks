class_name OpcUaServerConnection
extends Node

## No more connected/connection_lost/connection_failed signals — status is
## now conveyed exclusively via config.connection_status /
## config.last_error, which UI binds to directly. This class still emits
## tag_value_changed for now (see note below on whether to drop that too).
signal tag_value_changed(subscription_id: String, node_id: OpcUaNodeId, value: Variant)

var config: ReactiveOpcUaServer

var _client: GodotOpcUa
var _last_tick_ms: int = 0
var _poll_accum_sec: float = 0.0
var _subscriptions: Dictionary = {}
var _bound_subscriptions: ReactiveArray = null
var _subscriptions_changed_callable: Callable = Callable()

var client: GodotOpcUa:
    get: return _client

func _init() -> void:
    _client = GodotOpcUa.new()

func _process(delta: float) -> void:
    if config == null or not _is_connected():
        return
    _poll_accum_sec += delta
    var interval: float = maxf(config.poll_interval_sec.value, 0.001)
    if _poll_accum_sec < interval:
        return
    _poll_accum_sec = 0.0
    poll()

func _exit_tree() -> void:
    if _is_connected():
        disconnect_from_server()

func apply_config(cfg: ReactiveOpcUaServer) -> void:
    var is_initial: bool = config == null
    var connection_params_changed: bool = is_initial \
        or config.endpoint_url.value != cfg.endpoint_url.value \
        or config.security_policy.value != cfg.security_policy.value \
        or config.message_mode.value != cfg.message_mode.value \
        or config.username.value != cfg.username.value \
        or config.password.value != cfg.password.value

    config = cfg
    name = "OpcUaServerConnection_%s" % cfg.id.value

    if connection_params_changed:
        _client.set_reconnect_interval(cfg.reconnect_interval_sec.value)
        _client.set_max_reconnect_attempts(cfg.max_reconnect_attempts.value)

    _bind_subscriptions(cfg.subscriptions)
    _reconcile_subscriptions()

    if connection_params_changed and _is_connected():
        disconnect_from_server()

# ── Binding ─────────────────────────────────────────────────────────────────

func _bind_subscriptions(subscriptions: ReactiveArray) -> void:
    if _bound_subscriptions != null and _subscriptions_changed_callable.is_valid():
        _bound_subscriptions.reactive_changed.disconnect(_subscriptions_changed_callable)

    _bound_subscriptions = null
    _subscriptions_changed_callable = Callable()

    if subscriptions == null:
        return

    _subscriptions_changed_callable = func(_origin: Reactive) -> void:
        _reconcile_subscriptions()

    subscriptions.connect_self_changed(_subscriptions_changed_callable)
    _bound_subscriptions = subscriptions

# ── Reconciliation ──────────────────────────────────────────────────────────

func _reconcile_subscriptions() -> void:
    if config == null:
        return

    var configured_ids: Dictionary = {}

    for sub_cfg: ReactiveOpcUaSubscription in config.subscriptions.values():
        var subscription_id: String = sub_cfg.id.value

        if configured_ids.has(subscription_id):
            push_warning("OpcUaServerConnection [%s]: duplicate subscription id '%s' — skipping duplicate." % [config.id.value, subscription_id])
            continue
        configured_ids[subscription_id] = true

        if _subscriptions.has(subscription_id):
            var subscription: OpcUaSubscription = _subscriptions[subscription_id]
            subscription.apply_config(sub_cfg)
        else:
            _spawn_subscription(sub_cfg)

    for subscription_id: String in _subscriptions.keys().duplicate():
        if not configured_ids.has(subscription_id):
            _teardown_subscription(subscription_id)


func _spawn_subscription(sub_cfg: ReactiveOpcUaSubscription) -> void:
    var subscription_id: String = sub_cfg.id.value
    var subscription: OpcUaSubscription = OpcUaSubscription.new(subscription_id)

    subscription.tag_value_changed.connect(
        func(node_id: OpcUaNodeId, value: Variant) -> void:
            tag_value_changed.emit(subscription_id, node_id, value)
    )

    _subscriptions[subscription_id] = subscription
    subscription.apply_config(sub_cfg)

    # If already connected when a new subscription is added at runtime,
    # bring it live immediately rather than waiting for the next poll's
    # dirty-check (apply_config() itself always marks new subscriptions
    # dirty, so rebuild() here is what actually creates the OPC UA
    # subscription without waiting a full poll interval).
    if _is_connected() and subscription.is_dirty():
        subscription.rebuild(_client)


func _teardown_subscription(subscription_id: String) -> void:
    var subscription: OpcUaSubscription = _subscriptions.get(subscription_id)
    if subscription != null:
        subscription.teardown(_client)
    _subscriptions.erase(subscription_id)

# ── Connection ────────────────────────────────────────────────────────────

## Explicitly connects to the server. This is the ONLY way a connection is
## ever established — never called automatically by apply_config() or
## reconciliation. Callers (typically OpcUaManager, on behalf of the UI or
## an explicit app-level policy) decide when this should happen.
func connect_to_server() -> bool:
    if config == null:
        push_warning("OpcUaServerConnection: connect attempted before apply_config().")
        return false

    config.set_connecting()

    var ok: bool
    if config.username.value.is_empty():
        ok = _client.connect_to_server(config.endpoint_url.value)
    else:
        ok = _client.connect_with_credentials(
            config.endpoint_url.value, config.username.value, config.password.value
        )

    if not ok:
        push_warning("OpcUaServerConnection [%s]: connection failed." % config.id.value)
        config.set_connection_failed("Connection attempt failed")
        return false

    _rebuild_all_subscriptions()
    _last_tick_ms = Time.get_ticks_msec()
    _client.start_polling(config.poll_interval_sec.value)
    config.set_connected()
    return true


## Explicitly disconnects from the server. Connection will not resume
## automatically under any circumstance — connect_to_server() must be
## called again explicitly.
func disconnect_from_server() -> void:
    for subscription: OpcUaSubscription in _subscriptions.values():
        subscription.delete(_client)
    _client.disconnect_server()
    config.set_disconnected()


func teardown() -> void:
    disconnect_from_server()

    for subscription_id: String in _subscriptions.keys().duplicate():
        _teardown_subscription(subscription_id)

    if _bound_subscriptions != null and _subscriptions_changed_callable.is_valid():
        _bound_subscriptions.reactive_changed.disconnect(_subscriptions_changed_callable)

    _bound_subscriptions = null
    _subscriptions_changed_callable = Callable()

    queue_free()

# ── Poll ─────────────────────────────────────────────────────────────────────

## Only ever called while connected (see _process() guard above).
## Handles: detecting the underlying client-level connection dropping
## (e.g. network loss) and applying incoming tag updates. Does NOT attempt
## to reconnect — that remains an explicit, external decision.
func poll() -> void:
    var a = _client.has_connection_failed()
    var b = _client.is_server_connected()
    if _client.has_connection_failed() or not _client.is_server_connected():
        _poll_accum_sec = 0.0
        for subscription: OpcUaSubscription in _subscriptions.values():
            subscription.delete(_client)
        config.set_disconnected()
        return

    for subscription: OpcUaSubscription in _subscriptions.values():
        if subscription.is_dirty():
            subscription.rebuild(_client)

    var changed: Dictionary = _client.get_changed_tags_since(_last_tick_ms)
    _last_tick_ms = Time.get_ticks_msec()

    for node_id: String in changed:
        var subscription: OpcUaSubscription = find_subscription_for_tag(OpcUaNodeId.parse(node_id))
        if subscription != null:
            subscription.apply_update(OpcUaNodeId.parse(node_id), changed[node_id])

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

## Single source of truth for "are we connected", derived from
## config.connection_status rather than any internally tracked flag.
func _is_connected() -> bool:
    return config != null \
        and config.connection_status.value == ReactiveOpcUaServer.ConnectionStatus.CONNECTED
