# resources/widget_data.gd
class_name WidgetData
extends Resource

# ── Identity ──────────────────────────────────────────────────────────────────

## Unique identifier for this widget instance.
@export var widget_id: String = ""

## The registered class name — used to resolve the correct scene via NODE_REGISTRY.
## e.g. "ButtonWidget", "GaugeWidget"
@export var widget_type: String = ""

## Human-readable label — shown in the inspector and used for debugging.
@export var widget_name: String = ""

# ── Layout ────────────────────────────────────────────────────────────────────

@export var position: Vector2 = Vector2.ZERO
@export var size: Vector2     = Vector2(100.0, 100.0)
@export var z_index: int      = 0

# ── Hierarchy ─────────────────────────────────────────────────────────────────

## ID of the parent widget, or empty string if parented directly to the canvas.
@export var parent_id: String = ""

## Child widgets — only populated if this widget is a container.
@export var children: Array[WidgetData] = []

# ── Properties ────────────────────────────────────────────────────────────────

## Flexible key-value store for widget-specific properties.
## e.g. { "label_text": "Start", "background_color": "#FF0000" }
@export var properties: Dictionary = {}

# ── OPC UA Binding ────────────────────────────────────────────────────────────

## Optional OPC UA node binding — empty string if unbound.
@export var node_id: String    = ""
@export var server_id: String  = ""

# ── Factory ───────────────────────────────────────────────────────────────────

static func create(type: String, name: String = "") -> WidgetData:
    var data         := WidgetData.new()
    data.widget_id   =  _generate_id()
    data.widget_type = type
    data.widget_name = name if name != "" else type
    return data


static func from_dict(payload: Dictionary) -> WidgetData:
    var data := WidgetData.new()
    if not data.deserialize(payload):
        return null
    return data

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_children: Array = []
    for child: WidgetData in children:
        serialised_children.append(child.serialize())

    return {
        "widget_id":   widget_id,
        "widget_type": widget_type,
        "widget_name": widget_name,
        "position":    { "x": position.x, "y": position.y },
        "size":        { "x": size.x,     "y": size.y     },
        "z_index":     z_index,
        "parent_id":   parent_id,
        "node_id":     node_id,
        "server_id":   server_id,
        "properties":  properties,
        "children":    serialised_children,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────

func deserialize(payload: Dictionary) -> bool:
    if not _validate(payload):
        return false

    widget_id   = payload.get("widget_id",   _generate_id())
    widget_type = payload.get("widget_type", "")
    widget_name = payload.get("widget_name", widget_type)
    z_index     = payload.get("z_index",     0)
    parent_id   = payload.get("parent_id",   "")
    node_id     = payload.get("node_id",     "")
    server_id   = payload.get("server_id",   "")
    properties  = payload.get("properties",  {})

    var pos    : Dictionary = payload.get("position", {})
    var sz     : Dictionary = payload.get("size",     {})
    position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
    size     = Vector2(sz.get("x",  100.0), sz.get("y", 100.0))

    children.clear()
    for child_data: Dictionary in payload.get("children", []):
        var child := WidgetData.from_dict(child_data)
        if child != null:
            children.append(child)

    return true


func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("WidgetData: Empty payload passed to deserialize().")
        return false
    if not payload.has("widget_type"):
        push_warning("WidgetData: Missing required field 'widget_type'.")
        return false
    return true

# ── Helpers ───────────────────────────────────────────────────────────────────

func is_bound() -> bool:
    return node_id != "" and server_id != ""


func is_container() -> bool:
    return not children.is_empty()


static func _generate_id() -> String:
    return "%s-%s" % [
        Time.get_unix_time_from_system(),
        randi() % 0xFFFF
    ]
