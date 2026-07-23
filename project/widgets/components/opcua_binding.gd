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
var group_id: String = ""

## The OPC UA node this binding subscribes to.
var node_id: OpcUaNodeId = null

# ── Private ───────────────────────────────────────────────────────────────────

var _registered: bool = false

# =============================================================================
# Public API
# =============================================================================

## Primary setup method. Call this after add_child() to configure the binding,
## and again any time the widget's server_id/group_id/node_id properties change.
func setup(
    p_server_id: String,
    p_group_id:  String,
    p_node_id:   OpcUaNodeId,
    p_read_only: bool = false
) -> void:
    server_id = p_server_id
    group_id  = p_group_id
    node_id   = p_node_id
    read_only = p_read_only

    _registered = server_id != "" and group_id != "" and node_id != null

    if _registered and is_inside_tree() and OpcUaManager.is_server_connected(server_id):
        value_changed.emit(OpcUaManager.get_tag_value(server_id, node_id))


## Writes a value back to the bound node on the server.
## Silently ignored when read_only is true or the binding is incomplete.
func write_value(value: Variant) -> void:
    if read_only or not _registered:
        return
    OpcUaManager.write_tag(server_id, node_id, value)


## Returns the current cached value from the manager, or null.
func get_current_value() -> Variant:
    if not _registered:
        return null
    return OpcUaManager.get_tag_value(server_id, node_id)


## Serializes this binding's configuration into a Dictionary.
## Matches the three flat properties used by the property panel
## ("server_id", "group_id", "node_id") plus read_only.
func serialize() -> Dictionary:
    if node_id == null:
        return {}
    return {
        "server_id": server_id,
        "group_id":  group_id,
        "node_id":   node_id.to_string(),
        "read_only": read_only,
    }


## Restores this binding's configuration from a serialized Dictionary.
func deserialize(data: Dictionary) -> void:
    if data.is_empty():
        return

    var p_server_id: String = data.get("server_id", "")
    var p_group_id:  String = data.get("group_id",  "")
    var p_read_only: bool   = data.get("read_only", false)
    var p_node_id_str: String = data.get("node_id", "")

    var p_node_id: OpcUaNodeId = null
    if p_node_id_str != "":
        p_node_id = OpcUaNodeId.parse(p_node_id_str)

    setup(p_server_id, p_group_id, p_node_id, p_read_only)

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
    OpcUaManager.tag_value_changed.connect(_on_tag_value_changed)
    OpcUaManager.connected.connect(_on_server_connected)

    if _registered and OpcUaManager.is_server_connected(server_id):
        value_changed.emit(OpcUaManager.get_tag_value(server_id, node_id))


func _exit_tree() -> void:
    if OpcUaManager.tag_value_changed.is_connected(_on_tag_value_changed):
        OpcUaManager.tag_value_changed.disconnect(_on_tag_value_changed)

    if OpcUaManager.connected.is_connected(_on_server_connected):
        OpcUaManager.connected.disconnect(_on_server_connected)

# =============================================================================
# Signal handlers
# =============================================================================

func _on_server_connected(connected_server_id: String) -> void:
    if not _registered or connected_server_id != server_id:
        return
    value_changed.emit(OpcUaManager.get_tag_value(server_id, node_id))


## OpcUaManager.tag_value_changed now carries (server_id, group_id, node_id, value)
## directly from OpcUaServerConnection, so filtering is a simple three-way
## equality check — no need to re-resolve group config on every update.
func _on_tag_value_changed(
    changed_server_id: String,
    changed_group_id:  String,
    changed_node_id:   OpcUaNodeId,
    value:             Variant
) -> void:
    if not _registered:
        return

    if changed_server_id != server_id:
        return

    if changed_group_id != group_id:
        return

    if changed_node_id.to_string() != node_id.to_string():
        return

    value_changed.emit(value)
