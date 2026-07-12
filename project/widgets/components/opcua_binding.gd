# widgets/base_widget/opcua_binding.gd
#
# A self-contained, reusable component that manages a single OPC UA
# node subscription on behalf of a parent widget.
#
# Each binding is associated with a specific server and subscription group.
# The widget will only receive updates when the group that the tag belongs
# to is updated by the server.
#
# Usage (single binding):
#   var _binding := OpcUaBinding.new()
#   add_child(_binding)
#   _binding.value_changed.connect(_on_value_changed)
#   _binding.setup("server_01", "group_01", OpcUaNodeId.numeric(1, 1001))
#
# Usage (multiple bindings):
#   var _binding_a := OpcUaBinding.new()
#   var _binding_b := OpcUaBinding.new()
#   add_child(_binding_a)
#   add_child(_binding_b)
#   _binding_a.setup("server_01", "group_fast", node_id_a)
#   _binding_b.setup("server_01", "group_slow", node_id_b)
#   _binding_a.value_changed.connect(_on_setpoint_changed)
#   _binding_b.value_changed.connect(_on_feedback_changed)
# =============================================================================
class_name OpcUaBinding
extends Node

## Emitted whenever the bound OPC UA node publishes a new value.
signal value_changed(value: Variant)

# ── Public state ──────────────────────────────────────────────────────────────

## When true, write_value() calls are silently ignored.
var read_only: bool = false

## The server this binding targets.
var server_id: String = ""

## The subscription group this tag belongs to.
## The binding will only react to tag_value_changed signals that originate
## from a server whose group pub_interval_ms matches this group's interval.
var group_id: String = ""

## The OPC UA node this binding subscribes to.
var node_id: OpcUaNodeId = null

# ── Private ───────────────────────────────────────────────────────────────────

## Cached pub_interval_ms resolved from group_id at registration time.
## Used to validate that incoming updates originate from the correct group.
var _group_interval_ms: float = -1.0

# =============================================================================
# Public API
# =============================================================================

## Primary setup method. Call this after add_child() to configure the binding.
## Handles unregistering any previous binding before applying the new one.
func setup(
    p_server_id: String,
    p_group_id:  String,
    p_node_id:   OpcUaNodeId,
    p_read_only: bool = false
) -> void:
    _unregister()

    server_id = p_server_id
    group_id  = p_group_id
    node_id   = p_node_id
    read_only = p_read_only

    _register()


## Writes a value back to the bound node on the server.
## Silently ignored when read_only is true or no node_id is set.
func write_value(value: Variant) -> void:
    if read_only or node_id == null or server_id == "":
        return
    OpcUaManager.write_tag(server_id, node_id, value)


## Returns the current cached value from the manager, or null.
func get_current_value() -> Variant:
    if node_id == null or server_id == "":
        return null
    return OpcUaManager.get_tag_value(server_id, node_id)


## Serializes this binding's configuration into a Dictionary.
func serialize() -> Dictionary:
    if node_id == null:
        return {}
    return {
        "server_id": server_id,
        "group_id":  group_id,
        "ns":        node_id.namespace_index,
        "id":        node_id.identifier,
        "type":      node_id.identifier_type,
        "read_only": read_only,
    }


## Restores this binding's configuration from a serialized Dictionary.
func deserialize(data: Dictionary) -> void:
    if data.is_empty():
        return

    var p_server_id: String = data.get("server_id", "")
    var p_group_id:  String = data.get("group_id",  "")
    var p_read_only: bool   = data.get("read_only", false)

    var ns:      int    = data.get("ns",   0)
    var raw_id          = data.get("id",   0)
    var id_type: String = data.get("type", "numeric")

    var p_node_id: OpcUaNodeId
    if id_type == "string":
        p_node_id = OpcUaNodeId.from_string_id(ns, str(raw_id))
    else:
        p_node_id = OpcUaNodeId.numeric(ns, int(raw_id))

    setup(p_server_id, p_group_id, p_node_id, p_read_only)

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
    OpcUaManager.tag_value_changed.connect(_on_tag_value_changed)
    OpcUaManager.connected.connect(_on_server_connected)

    # Register if setup() was called before the node entered the tree
    if node_id != null and server_id != "":
        _register()
        if OpcUaManager.is_server_connected(server_id):
            value_changed.emit(OpcUaManager.get_tag_value(server_id, node_id))


func _exit_tree() -> void:
    _unregister()

    if OpcUaManager.tag_value_changed.is_connected(_on_tag_value_changed):
        OpcUaManager.tag_value_changed.disconnect(_on_tag_value_changed)

    if OpcUaManager.connected.is_connected(_on_server_connected):
        OpcUaManager.connected.disconnect(_on_server_connected)

# =============================================================================
# Registration
# =============================================================================

func _register() -> void:
    if node_id == null or server_id == "" or group_id == "":
        return

    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        push_warning("OpcUaBinding: server '%s' not found in registry." % server_id)
        return

    var group := cfg.get_group(group_id)
    if group == null:
        push_warning(
            "OpcUaBinding: group '%s' not found on server '%s'." \
            % [group_id, server_id]
        )
        return

    # Cache the interval so _on_tag_value_changed can filter by group
    _group_interval_ms = group.pub_interval_ms

    OpcUaManager.register_tag(
        server_id,
        node_id,
        group.pub_interval_ms,   # sampling_ms matches the group publishing rate
        group.pub_interval_ms,   # pub_interval_ms — assigns tag to the correct group
        0.0,
        OpcUaSubscriptionMode.Mode.ALWAYS
    )


func _unregister() -> void:
    if node_id != null and server_id != "":
        OpcUaManager.unregister_tag(server_id, node_id)
    _group_interval_ms = -1.0

# =============================================================================
# Signal handlers
# =============================================================================

func _on_server_connected(connected_server_id: String) -> void:
    if connected_server_id != server_id or node_id == null:
        return
    # Re-register in case the subscription was lost during reconnection
    _register()
    value_changed.emit(OpcUaManager.get_tag_value(server_id, node_id))


func _on_tag_value_changed(
    changed_server_id: String,
    changed_node_id:   OpcUaNodeId,
    value:             Variant
) -> void:
    if node_id == null:
        return

    # Ignore updates from other servers
    if changed_server_id != server_id:
        return

    # Ignore updates for other nodes
    if changed_node_id.to_tag_name() != node_id.to_tag_name():
        return

    # Ignore updates that did not originate from the correct subscription group.
    # The OpcUaTagRegistry only emits for active entries, but we additionally
    # guard here to ensure the widget update rate matches the group rate exactly.
    if _group_interval_ms >= 0.0:
        var cfg   := ProjectManager.opc_ua_registry.get_config(server_id)
        var group := cfg.get_group(group_id) if cfg else null
        if group == null or group.pub_interval_ms != _group_interval_ms:
            return

    value_changed.emit(value)
